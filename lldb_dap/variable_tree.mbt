///|
priv enum TreeAccess {
  Member(String)
  Position(Int)
  Element(Int)
  BufferRange(Int, Int)
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
    if variable.buffer_kind() is Some(_) {
      let layout = self.buffer_layout(identity, variable)
      let preview = self.buffer_preview(identity, layout, None)
      return {
        ..base,
        value: preview.summary(),
        type_name: Some(layout.kind.type_name()),
        indexed_children: layout.length / layout.kind.page_size() +
        (if layout.length % layout.kind.page_size() == 0 { 0 } else { 1 }),
      }
    }
    if self.load_indexed_collection_layout(identity, variable) is Some(layout) {
      let type_name = "\{layout.kind.source_name()}[\{layout.element_type.source_name()}]"
      return {
        ..base,
        type_name: Some(type_name),
        value: "length = \{layout.total_length}",
        indexed_children: layout.total_length,
      }
    }
    if self.positional_members(identity, variable) is Some((kind, children)) {
      return {
        ..base,
        value: if variable.is_tuple_type() {
          base.type_name.unwrap_or("tuple")
        } else {
          kind
        },
        named_children: children.length(),
      }
    }
    guard variable.variables_reference > 0 else { return base }
    let children = self.load_variables(identity, variable.variables_reference)
    {
      ..base,
      value: base.type_name.unwrap_or(variable.value),
      named_children: children.length(),
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
  if self.positional_members(identity, variable) is Some((_, children)) {
    return children
  }
  guard variable.variables_reference > 0 else { return [] }
  self.load_variables(identity, variable.variables_reference)
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
      Position(position) =>
        match self.resolve_position(identity, variable, "tree", position) {
          DapVariableResolved(child) => child
          DapVariableResolutionFailed(@debugger.VariableLookupFailed(failure)) =>
            raise VariableEvaluationError(failure.message())
          DapVariableResolutionFailed(_) =>
            raise VariableEvaluationError("Positional member is unavailable")
        }
      BufferRange(_, _) =>
        raise BufferInspectionError("Content ranges are leaves")
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
          DapVariableResolutionFailed(@debugger.VariableLookupFailed(failure)) =>
            raise VariableEvaluationError(failure.message())
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
  if variable.buffer_kind() is Some(_) {
    let layout = self.buffer_layout(identity, variable)
    let size = layout.kind.page_size()
    let pages = layout.length / size +
      (if layout.length % size == 0 { 0 } else { 1 })
    let count = count.min((pages - start).max(0))
    for page = start; page < start + count; page = page + 1 {
      let first = page * size
      let last = (first.to_int64() + size.to_int64())
        .min(layout.length.to_int64())
        .to_int()
      let preview = self.buffer_preview(
        identity,
        layout,
        Some((first, last)),
        automatic=true,
      )
      let access = node.access.copy()
      access.push(BufferRange(preview.start, preview.end))
      result.push({
        name: "[\{preview.start}:\{preview.end}]",
        value: preview.summary(),
        type_name: Some(layout.kind.type_name()),
        named_children: 0,
        indexed_children: 0,
        root: node.root,
        access,
      })
    }
    self.ensure_variable_identity(identity)
    return result
  }
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
            DapVariableResolutionFailed(@debugger.VariableLookupFailed(failure)) =>
              raise VariableEvaluationError(failure.message())
            DapVariableResolutionFailed(_) =>
              raise InvalidIndexedElementValue("Element \{i} is unavailable")
          }
        }
    }
  } else {
    let positional = self.positional_members(identity, variable)
    let children = match positional {
      Some((_, children)) => children
      None => self.tree_direct_children(identity, variable)
    }
    for i in start..<(start + count.min((children.length() - start).max(0))) {
      let child = children[i]
      let access = node.access.copy()
      if positional is Some(_) {
        access.push(Position(i))
      } else {
        access.push(Member(child.name))
      }
      result.push(self.describe_node(identity, child, node.root, access))
    }
  }
  self.ensure_variable_identity(identity)
  result
}
