///|
priv struct DapScope {
  name : String
  variables_reference : Int
  presentation_hint : String?
}

///|
fn DapScope::is_relevant(self : DapScope) -> Bool {
  self.presentation_hint != Some("registers") && self.name != "Registers"
}

///|
priv struct DapVariable {
  name : String
  value : String
  type_name : String?
  variables_reference : Int
  evaluate_name : String?
}

///|
fn DapVariable::snapshot(self : DapVariable) -> @moondbg.VariableSnapshot {
  @moondbg.VariableSnapshot::new(self.name, self.value, self.type_name)
}

///|
fn DapVariable::matches_lookup_name(self : DapVariable, name : String) -> Bool {
  self.name == name || self.evaluate_name == Some(name)
}

///|
fn DapVariable::is_available(self : DapVariable) -> Bool {
  !self.value.has_prefix("<error:") && self.value != "<variable not available>"
}

///|
priv enum DapVariableSelection {
  DapVariableSelected(DapVariable)
  DapVariableUnavailable
  DapVariableMissing
}

///|
fn Array::select_root_variable(
  self : Array[DapVariable],
  name : String,
) -> DapVariableSelection {
  let mut matched = false
  for variable in self {
    guard variable.matches_lookup_name(name) else { continue }
    matched = true
    if variable.is_available() {
      return DapVariableSelected({ ..variable, name, })
    }
  }
  if matched {
    DapVariableUnavailable
  } else {
    DapVariableMissing
  }
}

///|
fn Array::select_field_variable(
  self : Array[DapVariable],
  name : String,
) -> DapVariableSelection {
  for variable in self {
    guard variable.name == name else { continue }
    if variable.is_available() {
      return DapVariableSelected(variable)
    }
    return DapVariableUnavailable
  }
  DapVariableMissing
}

///|
fn DapVariable::is_moonbit_struct_type(self : DapVariable) -> Bool {
  guard self.type_name is Some(type_name) &&
    type_name.strip_suffix(" &") is Some(base) &&
    base.rev_split_once("/") is Some((package_name, struct_name)) else {
    return false
  }
  package_name != "" && struct_name != ""
}

///|
fn DapVariable::is_moonbit_struct_candidate(self : DapVariable) -> Bool {
  self.variables_reference > 0 && self.is_moonbit_struct_type()
}

///|
fn DapVariable::moonbit_array_element_name(self : DapVariable) -> String? {
  guard self.type_name is Some(raw_type_name) &&
    raw_type_name.trim().strip_suffix(" &") is Some(base_type) &&
    base_type.strip_prefix("moonbitlang/core/builtin/Array[")
    is Some(type_argument) &&
    type_argument.strip_suffix("]") is Some(element_type) &&
    element_type != "" else {
    return None
  }
  Some(element_type.to_owned())
}

///|
fn DapVariable::is_moonbit_array_candidate(self : DapVariable) -> Bool {
  self.variables_reference > 0 && self.moonbit_array_element_name() is Some(_)
}

///|
fn DapVariable::is_moonbit_fixed_array_candidate(self : DapVariable) -> Bool {
  guard self.variables_reference > 0 && self.type_name is Some(raw_type_name) else {
    return false
  }
  let type_name = match raw_type_name.rev_split_once("::") {
    Some((_, unqualified)) => unqualified
    None => raw_type_name
  }
  type_name.has_prefix("moonbit.array_") ||
  type_name.has_prefix("$moonbit.array_") ||
  type_name.has_prefix("FixedArray[") ||
  type_name.has_prefix("$FixedArray<") ||
  type_name.has_prefix("_M0TA") ||
  type_name.has_prefix("_M0TN") ||
  type_name.has_prefix("$_M0TA") ||
  type_name.has_prefix("$_M0TN")
}

///|
priv enum NativePayloadPointer {
  NullPayloadPointer
  PayloadPointer(String)
}

///|
fn is_ascii_hex_digit(char : Char) -> Bool {
  match char {
    '0'..='9' | 'a'..='f' | 'A'..='F' => true
    _ => false
  }
}

///|
fn parse_native_payload_pointer(value : String) -> NativePayloadPointer? {
  let address = value.trim()
  guard address.strip_prefix("0x") is Some(hex) &&
    hex != "" &&
    hex.all(is_ascii_hex_digit) else {
    return None
  }
  if hex.all(char => char == '0') {
    Some(NullPayloadPointer)
  } else {
    Some(PayloadPointer(address.to_owned()))
  }
}

///|
fn Array::named_child(self : Array[DapVariable], name : String) -> DapVariable? {
  for variable in self {
    if variable.name == name {
      return Some(variable)
    }
  }
  None
}

///|
fn Array::has_moonbit_enum_marker(self : Array[DapVariable]) -> Bool {
  self.any(fn(variable) {
    variable.name == "__moonbit_enum_marker" &&
    variable.type_name == Some("moonbit.enum")
  })
}

///|
const MAX_VARIABLE_EXPANSION_DEPTH : Int = 8

///|
const MAX_VARIABLE_EXPANSION_NODES : Int = 256

///|
priv struct VariableMaterializationBudget {
  max_depth : Int
  mut remaining_nodes : Int
  visiting_references : Map[Int, Unit]
}

///|
fn VariableMaterializationBudget::new(
  max_depth : Int,
  max_nodes : Int,
) -> VariableMaterializationBudget {
  { max_depth, remaining_nodes: max_nodes, visiting_references: Map([]), }
}

///|
fn VariableMaterializationBudget::take_node(
  self : VariableMaterializationBudget,
) -> Bool {
  guard self.remaining_nodes > 0 else { return false }
  self.remaining_nodes -= 1
  true
}

///|
fn VariableMaterializationBudget::is_empty(
  self : VariableMaterializationBudget,
) -> Bool {
  self.remaining_nodes <= 0
}

///|
fn VariableMaterializationBudget::is_visiting(
  self : VariableMaterializationBudget,
  reference : Int,
) -> Bool {
  self.visiting_references.get(reference) is Some(_)
}

///|
fn VariableMaterializationBudget::enter_reference(
  self : VariableMaterializationBudget,
  reference : Int,
) -> Unit {
  self.visiting_references.set(reference, ())
}

///|
fn VariableMaterializationBudget::leave_reference(
  self : VariableMaterializationBudget,
  reference : Int,
) -> Unit {
  self.visiting_references.remove(reference)
}

///|
priv struct StopVariableCache {
  mut epoch : Int
  mut scopes : Array[DapScope]?
  variables : Map[Int, Array[DapVariable]]
  snapshots : Map[String, @moondbg.VariableSnapshot]
}

///|
fn StopVariableCache::new() -> StopVariableCache {
  { epoch: 0, scopes: None, variables: Map([]), snapshots: Map([]), }
}

///|
fn StopVariableCache::reset(self : StopVariableCache, epoch : Int) -> Unit {
  self.epoch = epoch
  self.scopes = None
  self.variables.clear()
  self.snapshots.clear()
}

///|
fn StopVariableCache::cached_snapshot(
  self : StopVariableCache,
  epoch : Int,
  key : String,
) -> @moondbg.VariableSnapshot? {
  guard self.epoch == epoch else { return None }
  self.snapshots.get(key)
}

///|
fn StopVariableCache::store_snapshot(
  self : StopVariableCache,
  epoch : Int,
  key : String,
  snapshot : @moondbg.VariableSnapshot,
) -> Unit {
  guard self.epoch == epoch else { return }
  self.snapshots.set(key, snapshot)
}

///|
fn StopVariableCache::cached_scopes(
  self : StopVariableCache,
  epoch : Int,
) -> Array[DapScope]? {
  guard self.epoch == epoch else { return None }
  self.scopes
}

///|
fn StopVariableCache::store_scopes(
  self : StopVariableCache,
  epoch : Int,
  scopes : Array[DapScope],
) -> Unit {
  guard self.epoch == epoch else { return }
  self.scopes = Some(scopes)
}

///|
fn StopVariableCache::cached_variables(
  self : StopVariableCache,
  epoch : Int,
  reference : Int,
) -> Array[DapVariable]? {
  guard self.epoch == epoch else { return None }
  self.variables.get(reference)
}

///|
fn StopVariableCache::store_variables(
  self : StopVariableCache,
  epoch : Int,
  reference : Int,
  variables : Array[DapVariable],
) -> Unit {
  guard self.epoch == epoch else { return }
  self.variables.set(reference, variables)
}

///|
fn json_string_field(json : Json, field : String) -> String? {
  guard json is Object(object) && object.get(field) is Some(String(value)) else {
    return None
  }
  Some(value)
}

///|
fn json_int_field(json : Json, field : String) -> Int? {
  guard json is Object(object) && object.get(field) is Some(Number(value, ..)) else {
    return None
  }
  Some(value.to_int())
}

///|
fn json_bool_field(json : Json, field : String) -> Bool? {
  guard json is Object(object) && object.get(field) is Some(value) else {
    return None
  }
  match value {
    True => Some(true)
    False => Some(false)
    _ => None
  }
}

///|
fn parse_scope(json : Json) -> DapScope? {
  guard json_string_field(json, "name") is Some(name) &&
    json_int_field(json, "variablesReference") is Some(reference) &&
    reference > 0 else {
    return None
  }
  Some({
    name,
    variables_reference: reference,
    presentation_hint: json_string_field(json, "presentationHint"),
  })
}

///|
fn parse_scopes(body : Json) -> Array[DapScope]? {
  guard body is { "scopes": Array(items), .. } else { return None }
  Some(items.filter_map(parse_scope))
}

///|
fn parse_variable(json : Json) -> DapVariable? {
  guard json_string_field(json, "name") is Some(name) &&
    json_string_field(json, "value") is Some(value) else {
    return None
  }
  Some({
    name,
    value,
    type_name: json_string_field(json, "type"),
    variables_reference: json_int_field(json, "variablesReference").unwrap_or(0),
    evaluate_name: json_string_field(json, "evaluateName"),
  })
}

///|
fn parse_variables(body : Json) -> Array[DapVariable]? {
  guard body is { "variables": Array(items), .. } else { return None }
  Some(items.filter_map(parse_variable))
}

///|
async fn DebugExecution::load_scopes(
  self : DebugExecution,
  epoch : Int,
  frame_id : Int,
) -> Array[DapScope] {
  match self.variable_cache.cached_scopes(epoch) {
    Some(scopes) => return scopes
    None => ()
  }
  let response = self.request("scopes", { "frameId": frame_id })
  guard parse_scopes(response.body()) is Some(scopes) else {
    raise InvalidMessage(response.body())
  }
  for scope in scopes {
    self.machine.remember_variable_reference(scope.variables_reference)
  }
  self.variable_cache.store_scopes(epoch, scopes)
  scopes
}

///|
async fn DebugExecution::load_variables(
  self : DebugExecution,
  epoch : Int,
  reference : Int,
) -> Array[DapVariable] {
  match self.variable_cache.cached_variables(epoch, reference) {
    Some(variables) => return variables
    None => ()
  }
  let response = self.request("variables", { "variablesReference": reference })
  guard parse_variables(response.body()) is Some(variables) else {
    raise InvalidMessage(response.body())
  }
  for variable in variables {
    if variable.variables_reference > 0 {
      self.machine.remember_variable_reference(variable.variables_reference)
    }
  }
  self.variable_cache.store_variables(epoch, reference, variables)
  variables
}

///|
async fn DebugExecution::read_memory(
  self : DebugExecution,
  memory_reference : String,
  offset : Int,
  count : Int,
) -> Bytes {
  guard json_bool_field(self.capabilities, "supportsReadMemoryRequest") ==
    Some(true) else {
    raise InvalidIndexedCollectionValue("lldb-dap does not support readMemory")
  }
  let response = self.request("readMemory", {
    "memoryReference": memory_reference,
    "offset": offset,
    "count": count,
  })
  let body = response.body()
  guard json_string_field(body, "data") is Some(encoded) &&
    json_int_field(body, "unreadableBytes").unwrap_or(0) == 0 else {
    raise InvalidIndexedCollectionValue(
      "lldb-dap returned an incomplete memory range",
    )
  }
  let bytes = @base64.decode(encoded) catch {
    _ =>
      raise InvalidIndexedCollectionValue(
        "lldb-dap returned malformed base64 memory data",
      )
  }
  guard bytes.length() == count else {
    raise InvalidIndexedCollectionValue(
      "lldb-dap returned \{bytes.length()} bytes for a \{count}-byte memory request",
    )
  }
  bytes
}

///|
fn indexed_scalar_elements(
  scalar : @runtime_value.NativeScalarType,
  first_index : Int,
  payload : Bytes,
  element_count : Int,
) -> Array[@moondbg.IndexedVariableElement] raise {
  @runtime_value.decode_scalar_payload(scalar, payload, element_count).mapi((
    index,
    value,
  ) => {
    let source_index = first_index + index
    @moondbg.IndexedVariableElement::with_value(
      source_index,
      @moondbg.VariableSnapshot::new(
        "[\{source_index}]",
        value,
        Some(scalar.source_name()),
      ),
    )
  })
}

///|
async fn DebugExecution::materialize_native_indexed_collection(
  self : DebugExecution,
  variable : DapVariable,
  kind : @moondbg.IndexedCollectionKind,
  body : DapVariable,
  logical_length : Int?,
) -> @moondbg.VariableSnapshot {
  guard body.type_name is Some(pointer_type) &&
    @runtime_value.native_array_element_from_pointer_type(pointer_type)
    is Some(element_type) else {
    raise InvalidIndexedCollectionValue(
      "\{kind.source_name()} has no typed body pointer",
    )
  }
  let element_type_name = element_type.source_name()
  guard parse_native_payload_pointer(body.value) is Some(payload_pointer) else {
    raise InvalidIndexedCollectionValue(
      "\{kind.source_name()} body has malformed payload pointer '\{body.value}'",
    )
  }
  if payload_pointer is NullPayloadPointer {
    match logical_length {
      Some(length) =>
        @runtime_value.validate_array_length(length, 0) catch {
          error => raise InvalidIndexedCollectionValue(@debug.to_string(error))
        }
      None => ()
    }
    let collection = @moondbg.IndexedCollectionSnapshot::new(
      kind,
      element_type_name,
      0,
      [],
    )
    return @moondbg.VariableSnapshot::indexed_collection(
      variable.name,
      variable.value,
      variable.type_name,
      collection,
    )
  }
  guard payload_pointer is PayloadPointer(memory_reference) else {
    raise InvalidIndexedCollectionValue(
      "\{kind.source_name()} payload pointer was unexpectedly null",
    )
  }
  let header = self.read_memory(
    memory_reference,
    @runtime_value.NATIVE_ARRAY_HEADER_OFFSET,
    @runtime_value.NATIVE_ARRAY_HEADER_SIZE,
  )
  let capacity = @runtime_value.decode_native_array_capacity(header) catch {
    error => raise InvalidIndexedCollectionValue(@debug.to_string(error))
  }
  let total_length = logical_length.unwrap_or(capacity)
  @runtime_value.validate_array_length(total_length, capacity) catch {
    error => raise InvalidIndexedCollectionValue(@debug.to_string(error))
  }
  let plan = @runtime_value.IndexedPreviewPlan::new(total_length) catch {
    error => raise InvalidIndexedCollectionValue(@debug.to_string(error))
  }
  let elements : Array[@moondbg.IndexedVariableElement] = []
  match element_type {
    @runtime_value.NativeArrayScalar(scalar) => {
      let width = scalar.byte_width()
      if plan.head_count() > 0 {
        let count = plan.head_count() * width
        let payload = self.read_memory(memory_reference, 0, count)
        elements.push_iter(
          indexed_scalar_elements(scalar, 0, payload, plan.head_count()).iter(),
        )
      }
      if plan.tail_index() is Some(tail_index) {
        let offset = plan.tail_byte_offset(width) catch {
          error => raise InvalidIndexedCollectionValue(@debug.to_string(error))
        }
        guard offset is Some(offset) else {
          raise InvalidIndexedCollectionValue(
            "\{kind.source_name()} preview lost its tail offset",
          )
        }
        let payload = self.read_memory(memory_reference, offset, width)
        elements.push_iter(
          indexed_scalar_elements(scalar, tail_index, payload, 1).iter(),
        )
      }
    }
    @runtime_value.NativeArrayOpaque(_) => {
      for index in 0..<plan.head_count() {
        elements.push(@moondbg.IndexedVariableElement::placeholder(index))
      }
      if plan.tail_index() is Some(index) {
        elements.push(@moondbg.IndexedVariableElement::placeholder(index))
      }
    }
  }
  let collection = @moondbg.IndexedCollectionSnapshot::new(
    kind, element_type_name, total_length, elements,
  )
  @moondbg.VariableSnapshot::indexed_collection(
    variable.name,
    variable.value,
    variable.type_name,
    collection,
  )
}

///|
fn parse_array_logical_length(variable : DapVariable) -> Int? {
  let value = variable.value.trim()
  guard value != "" && value.all(char => char is ('0'..='9')) else {
    return None
  }
  Some(@string.parse_int(value, base=10)) catch {
    _ => None
  }
}

///|
async fn DebugExecution::materialize_fixed_array(
  self : DebugExecution,
  epoch : Int,
  variable : DapVariable,
) -> @moondbg.VariableSnapshot {
  let children = self.load_variables(epoch, variable.variables_reference)
  guard children.named_child("body") is Some(body) else {
    raise InvalidIndexedCollectionValue("FixedArray has no body field")
  }
  self.materialize_native_indexed_collection(
    variable,
    @moondbg.FixedArrayCollection,
    body,
    None,
  )
}

///|
async fn DebugExecution::materialize_array(
  self : DebugExecution,
  epoch : Int,
  variable : DapVariable,
) -> @moondbg.VariableSnapshot {
  let children = self.load_variables(epoch, variable.variables_reference)
  guard children.named_child("buf") is Some(buffer) &&
    buffer.is_available() &&
    buffer.variables_reference > 0 else {
    raise InvalidIndexedCollectionValue("Array has no available buf field")
  }
  guard children.named_child("len") is Some(length_variable) &&
    length_variable.is_available() &&
    parse_array_logical_length(length_variable) is Some(logical_length) else {
    raise InvalidIndexedCollectionValue(
      "Array has no valid non-negative logical length",
    )
  }
  let buffer_children = self.load_variables(epoch, buffer.variables_reference)
  guard buffer_children.named_child("body") is Some(body) else {
    raise InvalidIndexedCollectionValue("Array buffer has no body field")
  }
  self.materialize_native_indexed_collection(
    variable,
    @moondbg.ArrayCollection,
    body,
    Some(logical_length),
  )
}

///|
async fn DebugExecution::materialize_variable(
  self : DebugExecution,
  epoch : Int,
  variable : DapVariable,
  depth : Int,
  budget : VariableMaterializationBudget,
) -> @moondbg.VariableSnapshot {
  guard budget.take_node() else {
    return @moondbg.VariableSnapshot::truncated(
      variable.name,
      variable.value,
      variable.type_name,
      [],
    )
  }
  if variable.is_moonbit_array_candidate() {
    return self.materialize_array(epoch, variable)
  }
  if variable.is_moonbit_fixed_array_candidate() {
    return self.materialize_fixed_array(epoch, variable)
  }
  guard variable.is_moonbit_struct_candidate() else {
    return variable.snapshot()
  }
  guard !budget.is_empty() &&
    depth < budget.max_depth &&
    !budget.is_visiting(variable.variables_reference) else {
    return @moondbg.VariableSnapshot::truncated(
      variable.name,
      variable.value,
      variable.type_name,
      [],
    )
  }
  budget.enter_reference(variable.variables_reference)
  defer budget.leave_reference(variable.variables_reference)
  let dap_children = self.load_variables(epoch, variable.variables_reference)
  guard !dap_children.has_moonbit_enum_marker() else {
    return variable.snapshot()
  }
  let children : Array[@moondbg.VariableSnapshot] = []
  let mut truncated = false
  for child in dap_children {
    if budget.is_empty() {
      truncated = true
      break
    }
    children.push(self.materialize_variable(epoch, child, depth + 1, budget))
  }
  if truncated {
    @moondbg.VariableSnapshot::truncated(
      variable.name,
      variable.value,
      variable.type_name,
      children,
    )
  } else {
    @moondbg.VariableSnapshot::expanded(
      variable.name,
      variable.value,
      variable.type_name,
      children,
    )
  }
}

///|
async fn DebugExecution::materialize_variable_with_limits(
  self : DebugExecution,
  epoch : Int,
  variable : DapVariable,
  max_depth : Int,
  max_nodes : Int,
) -> @moondbg.VariableSnapshot {
  let budget = VariableMaterializationBudget::new(max_depth, max_nodes)
  self.materialize_variable(epoch, variable, 0, budget)
}

///|
priv enum DapVariableResolution {
  DapVariableResolved(DapVariable)
  DapVariableResolutionFailed(@moondbg.VariableLookupResult)
}

///|
async fn DebugExecution::resolve_root_variable(
  self : DebugExecution,
  epoch : Int,
  frame_id : Int,
  name : String,
) -> DapVariableResolution {
  let scopes = self.load_scopes(epoch, frame_id)
  for scope in scopes {
    guard scope.is_relevant() else { continue }
    match
      self
      .load_variables(epoch, scope.variables_reference)
      .select_root_variable(name) {
      DapVariableSelected(variable) => return DapVariableResolved(variable)
      DapVariableUnavailable =>
        return DapVariableResolutionFailed(
          @moondbg.VariableLookupResult::unavailable(name),
        )
      DapVariableMissing => ()
    }
  }
  DapVariableResolutionFailed(@moondbg.VariableLookupResult::not_found(name))
}

///|
async fn DebugExecution::resolve_variable_path(
  self : DebugExecution,
  epoch : Int,
  frame_id : Int,
  path : @moondbg.VariablePath,
) -> DapVariableResolution {
  let mut variable = match
    self.resolve_root_variable(epoch, frame_id, path.root_name()) {
    DapVariableResolved(variable) => variable
    DapVariableResolutionFailed(result) =>
      return DapVariableResolutionFailed(result)
  }
  let mut owner = path.root_name()
  for step in path.steps() {
    let @moondbg.Field(field) = step
    guard variable.is_moonbit_struct_type() else {
      return DapVariableResolutionFailed(
        @moondbg.VariableLookupResult::field_access_on_non_struct(
          owner,
          field,
          variable.type_name,
        ),
      )
    }
    guard variable.variables_reference > 0 else {
      return DapVariableResolutionFailed(
        @moondbg.VariableLookupResult::field_not_found(owner, field),
      )
    }
    let children = self.load_variables(epoch, variable.variables_reference)
    guard !children.has_moonbit_enum_marker() else {
      return DapVariableResolutionFailed(
        @moondbg.VariableLookupResult::field_access_on_non_struct(
          owner,
          field,
          variable.type_name,
        ),
      )
    }
    match children.select_field_variable(field) {
      DapVariableSelected(child) => {
        variable = child
        owner = "\{owner}.\{field}"
      }
      DapVariableUnavailable =>
        return DapVariableResolutionFailed(
          @moondbg.VariableLookupResult::unavailable("\{owner}.\{field}"),
        )
      DapVariableMissing =>
        return DapVariableResolutionFailed(
          @moondbg.VariableLookupResult::field_not_found(owner, field),
        )
    }
  }
  DapVariableResolved({ ..variable, name: path.display_name(), })
}

///|
async fn DebugExecution::find_variable_inner(
  self : DebugExecution,
  epoch : Int,
  frame_id : Int,
  path : @moondbg.VariablePath,
) -> @moondbg.VariableLookupResult {
  let cache_key = "\{frame_id}:\{path.display_name()}"
  if self.variable_cache.cached_snapshot(epoch, cache_key) is Some(snapshot) {
    return @moondbg.VariableLookupResult::found(snapshot)
  }
  let variable = match self.resolve_variable_path(epoch, frame_id, path) {
    DapVariableResolved(variable) => variable
    DapVariableResolutionFailed(result) => return result
  }
  let snapshot = self.materialize_variable_with_limits(
    epoch,
    variable,
    MAX_VARIABLE_EXPANSION_DEPTH,
    MAX_VARIABLE_EXPANSION_NODES,
  )
  self.variable_cache.store_snapshot(epoch, cache_key, snapshot)
  @moondbg.VariableLookupResult::found(snapshot)
}

///|
async fn DebugExecution::find_variable(
  self : DebugExecution,
  thread : @moondbg.ThreadSelection,
  frame : @moondbg.FrameSelection,
  path : @moondbg.VariablePath,
) -> @moondbg.VariableLookupResult {
  guard self.machine.state is Stopped &&
    self.machine.current_stop_epoch() is Some(epoch) else {
    raise LldbDapBackendError::OperationNotAllowed(
      state=self.machine.state,
      action="inspect a variable",
    )
  }
  let frame_id = self.selected_frame_id(thread, frame, "inspect a variable")
  self.find_variable_inner(epoch, frame_id, path) catch {
    error => raise LldbDapBackendError::AdapterFailure(@debug.to_string(error))
  }
}

///|
async fn LldbDapSession::find_variable(
  self : LldbDapSession,
  thread : @moondbg.ThreadSelection,
  frame : @moondbg.FrameSelection,
  path : @moondbg.VariablePath,
) -> @moondbg.VariableLookupResult {
  guard self.execution is Some(execution) else {
    raise LldbDapBackendError::OperationNotAllowed(
      state=self.detached_state,
      action="inspect a variable",
    )
  }
  execution.find_variable(thread, frame, path) catch {
    LldbDapBackendError::AdapterFailure(message) => {
      self.recover_failed_execution(execution, try_disconnect=true) catch {
        _ => ()
      }
      raise LldbDapBackendError::AdapterFailure(message)
    }
    error => raise error
  }
}
