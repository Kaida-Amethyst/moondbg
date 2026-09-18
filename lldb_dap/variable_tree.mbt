///|
priv enum TreeAccess {
  Member(String)
  Element(Int)
}

///|
/// A source-level locator, not an LLDB variablesReference. Re-resolving the
/// path in its frame prevents LLDB's reused frame-local handles from leaking.
pub struct VariableNode {
  name : String
  value : String
  type_name : String?
  named_children : Int
  indexed_children : Int
  priv root : String
  priv access : Array[TreeAccess]
}

///|
fn VariableInspector::tree_identity(
  self : VariableInspector,
  frame : Int,
) -> VariableCacheIdentity raise {
  guard (self.current_epoch)() is Some(epoch) else {
    raise StaleVariableResult(expected_epoch=0, expected_frame=frame)
  }
  // Each tree operation reestablishes the frame's scope context. Requests from
  // other frontends/frames may have changed LLDB's shared variable handles.
  self.variable_cache.reset(epoch)
  self.variable_cache.select_frame(epoch, frame)
  { epoch, frame_index: frame, }
}

///|
async fn VariableInspector::describe_node(
  self : VariableInspector,
  identity : VariableCacheIdentity,
  variable : DapVariable,
  root : String,
  access : Array[TreeAccess],
) -> VariableNode {
  let base : VariableNode = {
    name: variable.name,
    value: variable.value,
    type_name: match variable.source_type_name() {
      Some(name) => Some(name)
      None => variable.type_name
    },
    named_children: 0,
    indexed_children: 0,
    root,
    access,
  }
  guard variable.is_available() else {
    return { ..base, value: "<unavailable>", }
  }
  try {
    if self.load_indexed_collection_layout(identity, variable) is Some(layout) {
      let type_name = "\{layout.kind.source_name()}[\{layout.element_type.source_name()}]"
      return {
        ..base,
        type_name: Some(type_name),
        value: "length = \{layout.total_length}",
        indexed_children: layout.total_length,
      }
    }
    guard variable.variables_reference > 0 else { return base }
    let children = self.load_variables(identity, variable.variables_reference)
    match detect_dap_enum_layout(children) {
      DapEnum(variants) => {
        let active = self.active_enum_variant(variants)
        let payload = if active.payload_reference > 0 {
          self.load_variables(identity, active.payload_reference)
        } else {
          []
        }
        {
          ..base,
          value: active.variant_name,
          named_children: payload.length(),
        }
      }
      NotDapEnum =>
        {
          ..base,
          value: base.type_name.unwrap_or(variable.value),
          named_children: children.length(),
        }
    }
  } catch {
    error => {
      if @async.is_cancellation_error(error) {
        raise error
      }
      self.ensure_variable_identity(identity)
      { ..base, value: "<unavailable: \{@debug.to_string(error)}>", }
    }
  }
}

///|
pub async fn VariableInspector::tree_locals(
  self : VariableInspector,
  frame_id : Int,
) -> Array[VariableNode] {
  let identity = self.tree_identity(frame_id)
  let scopes = self.load_scopes(identity, frame_id)
  let nodes = []
  for variable in self.source_locals(identity, frame_id, scopes) {
    nodes.push(self.describe_node(identity, variable, variable.name, []))
  }
  self.ensure_variable_identity(identity)
  nodes
}

///|
async fn VariableInspector::tree_direct_children(
  self : VariableInspector,
  identity : VariableCacheIdentity,
  variable : DapVariable,
) -> Array[DapVariable] {
  guard variable.variables_reference > 0 else { return [] }
  let children = self.load_variables(identity, variable.variables_reference)
  match detect_dap_enum_layout(children) {
    NotDapEnum => children
    DapEnum(variants) => {
      let active = self.active_enum_variant(variants)
      if active.payload_reference > 0 {
        self.load_variables(identity, active.payload_reference)
      } else {
        []
      }
    }
  }
}

///|
async fn VariableInspector::resolve_tree_node(
  self : VariableInspector,
  identity : VariableCacheIdentity,
  frame_id : Int,
  node : VariableNode,
) -> DapVariable {
  let root = match self.resolve_root_variable(identity, frame_id, node.root) {
    DapVariableResolved(variable) => variable
    DapVariableResolutionFailed(_) =>
      raise InvalidMessage(Json("Variable is unavailable"))
  }
  for variable = root, index = 0; index < node.access.length(); {
    let child = match node.access[index] {
      Member(name) => {
        let children = self.tree_direct_children(identity, variable)
        guard children.named_child(name) is Some(child) else {
          raise InvalidMessage(Json("Field '\{name}' is unavailable"))
        }
        child
      }
      Element(position) =>
        match
          self.resolve_indexed_element(
            identity,
            frame_id,
            "tree:\{index}",
            position,
            variable,
          ) {
          DapVariableResolved(variable) => variable
          DapVariableResolutionFailed(_) =>
            raise InvalidMessage(Json("Array element is unavailable"))
        }
    }
    continue child, index + 1
  } nobreak {
    variable
  }
}

///|
/// Returns a bounded slice. Scalars are read as one contiguous memory range;
/// aggregates are inspected one level only, without materializing descendants.
pub async fn VariableInspector::tree_children(
  self : VariableInspector,
  frame_id : Int,
  node : VariableNode,
  start~ : Int,
  count~ : Int,
) -> Array[VariableNode] {
  guard start >= 0 && count >= 0 && count <= 100 else {
    raise InvalidIndexedCollectionValue(
      "Variable pages must contain at most 100 elements",
    )
  }
  let identity = self.tree_identity(frame_id)
  let variable = self.resolve_tree_node(identity, frame_id, node)
  let result = []
  if self.load_indexed_collection_layout(identity, variable) is Some(layout) {
    let count = count.min((layout.total_length - start).max(0))
    guard count > 0 else { return [] }
    match layout.element_type {
      @runtime_value.NativeArrayScalar(scalar) => {
        guard layout.payload_pointer is PayloadPointer(pointer) else {
          raise InvalidIndexedCollectionValue("Non-empty array has no payload")
        }
        let offset = start.to_int64() * scalar.byte_width().to_int64()
        guard offset <= 2147483647L else {
          raise InvalidIndexedCollectionValue(
            "Array page offset exceeds supported memory range",
          )
        }
        let bytes = self.read_memory(
          pointer,
          offset.to_int(),
          count * scalar.byte_width(),
        )
        for
          i, value in @runtime_value.decode_scalar_payload(scalar, bytes, count) {
          let access = node.access.copy()
          access.push(Element(start + i))
          result.push({
            name: "[\{start + i}]",
            value,
            type_name: Some(scalar.source_name()),
            named_children: 0,
            indexed_children: 0,
            root: node.root,
            access,
          })
        }
      }
      @runtime_value.NativeArrayOpaque(_) =>
        for i in start..<(start + count) {
          let access = node.access.copy()
          access.push(Element(i))
          match
            self.resolve_indexed_element(
              identity, frame_id, "page", i, variable,
            ) {
            DapVariableResolved(child) =>
              result.push(
                self.describe_node(
                  identity,
                  { ..child, name: "[\{i}]", },
                  node.root,
                  access,
                ),
              )
            DapVariableResolutionFailed(_) =>
              raise InvalidIndexedElementValue("Element \{i} is unavailable")
          }
        }
    }
  } else {
    let children = self.tree_direct_children(identity, variable)
    for i in start..<(start + count.min((children.length() - start).max(0))) {
      let child = children[i]
      let access = node.access.copy()
      access.push(Member(child.name))
      result.push(self.describe_node(identity, child, node.root, access))
    }
  }
  self.ensure_variable_identity(identity)
  result
}
