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
fn DapScope::is_locals(self : DapScope) -> Bool {
  self.presentation_hint == Some("locals") ||
  (self.presentation_hint is None && self.name == "Locals")
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
fn DapVariable::source_local_name(self : DapVariable) -> String {
  match self.evaluate_name {
    Some(name) if name.trim() != "" => name.trim().to_owned()
    _ =>
      match self.name.split_once(" @ ") {
        Some((name, _)) if name.trim() != "" => name.trim().to_owned()
        _ => self.name
      }
  }
}

///|
fn DapVariable::source_type_name(self : DapVariable) -> String? {
  guard self.type_name is Some(debug_type) else { return None }
  if self.moonbit_array_element_name() is Some(element_debug_type) {
    let element_type = @runtime_value.source_name_from_debug_type(
      element_debug_type,
    ).unwrap_or(element_debug_type)
    return Some("Array[\{element_type}]")
  }
  @runtime_value.source_name_from_debug_type(debug_type)
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
priv struct DapEnumVariant {
  variant_name : String
  tag : Int
  payload_reference : Int
  payload_pointer : String
}

///|
priv enum DapEnumLayout {
  NotDapEnum
  DapEnum(Array[DapEnumVariant])
}

///|
fn parse_dap_enum_variant(
  variable : DapVariable,
) -> DapEnumVariant raise DapSessionError {
  guard variable.name.rev_split_once("_") is Some((variant_name, tag_text)) &&
    variant_name != "" &&
    tag_text != "" &&
    tag_text.all(char => char is ('0'..='9')) else {
    raise InvalidEnumValue(
      "enum variant '\{variable.name}' does not end in a decimal tag",
    )
  }
  let tag = Some(@string.parse_int(tag_text, base=10)) catch { _ => None }
  guard tag is Some(tag) && tag >= 0 && tag <= 255 else {
    raise InvalidEnumValue(
      "enum variant '\{variable.name}' has an out-of-range tag",
    )
  }
  guard parse_native_payload_pointer(variable.value)
    is Some(PayloadPointer(payload_pointer)) else {
    raise InvalidEnumValue(
      "enum variant '\{variable.name}' has malformed payload pointer '\{variable.value}'",
    )
  }
  {
    variant_name: variant_name.to_owned(),
    tag,
    payload_reference: variable.variables_reference,
    payload_pointer,
  }
}

///|
fn detect_dap_enum_layout(
  children : Array[DapVariable],
) -> DapEnumLayout raise DapSessionError {
  let mut marker_count = 0
  let mut marker_type_valid = false
  for child in children {
    guard child.name == "__moonbit_enum_marker" else { continue }
    marker_count += 1
    marker_type_valid = child.type_name == Some("moonbit.enum")
  }
  guard marker_count > 0 else { return NotDapEnum }
  guard marker_count == 1 && marker_type_valid else {
    raise InvalidEnumValue(
      "boxed enum must have exactly one moonbit.enum marker",
    )
  }
  let variants : Array[DapEnumVariant] = []
  let tags : Map[Int, Unit] = Map([])
  let mut shared_pointer : String? = None
  for child in children {
    guard child.name != "__moonbit_enum_marker" else { continue }
    let variant = parse_dap_enum_variant(child)
    guard tags.get(variant.tag) is None else {
      raise InvalidEnumValue("boxed enum repeats tag \{variant.tag}")
    }
    tags.set(variant.tag, ())
    match shared_pointer {
      None => shared_pointer = Some(variant.payload_pointer)
      Some(pointer) if pointer == variant.payload_pointer => ()
      Some(_) =>
        raise InvalidEnumValue(
          "boxed enum variants do not share one payload pointer",
        )
    }
    variants.push(variant)
  }
  guard variants.length() > 0 else {
    raise InvalidEnumValue("boxed enum marker has no variant views")
  }
  DapEnum(variants)
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
  mut frame_index : Int?
  mut scopes : Array[DapScope]?
  variables : Map[Int, Array[DapVariable]]
  evaluated_variables : Map[String, DapVariable]
  snapshots : Map[String, @moondbg.VariableSnapshot]
  local_snapshots : Map[Int, @moondbg.LocalVariablesSnapshot]
}

///|
priv struct VariableCacheIdentity {
  epoch : Int
  frame_index : Int
}

///|
fn StopVariableCache::new() -> StopVariableCache {
  {
    epoch: 0,
    frame_index: None,
    scopes: None,
    variables: Map([]),
    evaluated_variables: Map([]),
    snapshots: Map([]),
    local_snapshots: Map([]),
  }
}

///|
fn StopVariableCache::reset(self : StopVariableCache, epoch : Int) -> Unit {
  self.epoch = epoch
  self.frame_index = None
  self.scopes = None
  self.variables.clear()
  self.evaluated_variables.clear()
  self.snapshots.clear()
  self.local_snapshots.clear()
}

///|
/// Selects the cache identity for one physical frame. LLDB may reuse the same
/// variablesReference for different frames, so every frame change discards
/// raw scope/reference/evaluate entries. Fully materialized domain snapshots
/// remain keyed by physical frame for the lifetime of this stop.
fn StopVariableCache::select_frame(
  self : StopVariableCache,
  epoch : Int,
  frame_index : Int,
) -> Unit {
  if self.epoch != epoch {
    self.reset(epoch)
  }
  guard self.frame_index != Some(frame_index) else { return }
  self.frame_index = Some(frame_index)
  self.scopes = None
  self.variables.clear()
  self.evaluated_variables.clear()
}

///|
fn StopVariableCache::is_current(
  self : StopVariableCache,
  identity : VariableCacheIdentity,
) -> Bool {
  self.epoch == identity.epoch && self.frame_index == Some(identity.frame_index)
}

///|
fn DebugExecution::ensure_variable_identity(
  self : DebugExecution,
  identity : VariableCacheIdentity,
) -> Unit raise DapSessionError {
  guard self.machine.current_stop_epoch() == Some(identity.epoch) &&
    self.variable_cache.is_current(identity) else {
    raise StaleVariableResult(
      expected_epoch=identity.epoch,
      expected_frame=identity.frame_index,
    )
  }
}

///|
fn StopVariableCache::cached_snapshot(
  self : StopVariableCache,
  identity : VariableCacheIdentity,
  key : String,
) -> @moondbg.VariableSnapshot? {
  guard self.is_current(identity) else { return None }
  self.snapshots.get(key)
}

///|
fn StopVariableCache::store_snapshot(
  self : StopVariableCache,
  identity : VariableCacheIdentity,
  key : String,
  snapshot : @moondbg.VariableSnapshot,
) -> Unit {
  guard self.is_current(identity) else { return }
  self.snapshots.set(key, snapshot)
}

///|
fn StopVariableCache::cached_local_snapshot(
  self : StopVariableCache,
  identity : VariableCacheIdentity,
) -> @moondbg.LocalVariablesSnapshot? {
  guard self.is_current(identity) else { return None }
  self.local_snapshots.get(identity.frame_index)
}

///|
fn StopVariableCache::store_local_snapshot(
  self : StopVariableCache,
  identity : VariableCacheIdentity,
  snapshot : @moondbg.LocalVariablesSnapshot,
) -> Unit {
  guard self.is_current(identity) else { return }
  self.local_snapshots.set(identity.frame_index, snapshot)
}

///|
fn StopVariableCache::cached_scopes(
  self : StopVariableCache,
  identity : VariableCacheIdentity,
) -> Array[DapScope]? {
  guard self.is_current(identity) else { return None }
  self.scopes
}

///|
fn StopVariableCache::store_scopes(
  self : StopVariableCache,
  identity : VariableCacheIdentity,
  scopes : Array[DapScope],
) -> Unit {
  guard self.is_current(identity) else { return }
  self.scopes = Some(scopes)
}

///|
fn StopVariableCache::cached_variables(
  self : StopVariableCache,
  identity : VariableCacheIdentity,
  reference : Int,
) -> Array[DapVariable]? {
  guard self.is_current(identity) else { return None }
  self.variables.get(reference)
}

///|
fn StopVariableCache::store_variables(
  self : StopVariableCache,
  identity : VariableCacheIdentity,
  reference : Int,
  variables : Array[DapVariable],
) -> Unit {
  guard self.is_current(identity) else { return }
  self.variables.set(reference, variables)
}

///|
fn StopVariableCache::cached_evaluated_variable(
  self : StopVariableCache,
  identity : VariableCacheIdentity,
  key : String,
) -> DapVariable? {
  guard self.is_current(identity) else { return None }
  self.evaluated_variables.get(key)
}

///|
fn StopVariableCache::store_evaluated_variable(
  self : StopVariableCache,
  identity : VariableCacheIdentity,
  key : String,
  variable : DapVariable,
) -> Unit {
  guard self.is_current(identity) else { return }
  self.evaluated_variables.set(key, variable)
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
fn normalize_indexed_element_type(type_name : String) -> String {
  let trimmed = type_name.trim()
  guard trimmed.strip_suffix(" *") is Some(base) &&
    base.rev_split_once("/") is Some((package_name, source_name)) &&
    package_name != "" &&
    source_name != "" else {
    return trimmed.to_owned()
  }
  "\{base} &"
}

///|
fn parse_indexed_element_evaluate_response(
  body : Json,
  name : String,
) -> DapVariable raise DapSessionError {
  guard body is Object(object) &&
    object.get("result") is Some(String(result)) &&
    object.get("type") is Some(String(type_name)) &&
    type_name.trim() != "" &&
    object.get("variablesReference") is Some(Number(reference, ..)) &&
    reference.to_int() >= 0 else {
    raise InvalidIndexedElementValue(
      "lldb-dap returned an incomplete indexed element",
    )
  }
  match object.get("memoryReference") {
    None | Some(String(_)) => ()
    Some(_) =>
      raise InvalidIndexedElementValue(
        "lldb-dap returned a malformed indexed element memory reference",
      )
  }
  {
    name,
    value: result,
    type_name: Some(normalize_indexed_element_type(type_name)),
    variables_reference: reference.to_int(),
    evaluate_name: None,
  }
}

///|
async fn DebugExecution::load_scopes(
  self : DebugExecution,
  identity : VariableCacheIdentity,
  frame_id : Int,
) -> Array[DapScope] {
  match self.variable_cache.cached_scopes(identity) {
    Some(scopes) => return scopes
    None => ()
  }
  let response = self.request("scopes", { "frameId": frame_id })
  self.ensure_variable_identity(identity)
  guard parse_scopes(response.body()) is Some(scopes) else {
    raise InvalidMessage(response.body())
  }
  for scope in scopes {
    self.machine.remember_variable_reference(scope.variables_reference)
  }
  self.variable_cache.store_scopes(identity, scopes)
  scopes
}

///|
async fn DebugExecution::load_variables(
  self : DebugExecution,
  identity : VariableCacheIdentity,
  reference : Int,
) -> Array[DapVariable] {
  match self.variable_cache.cached_variables(identity, reference) {
    Some(variables) => return variables
    None => ()
  }
  let response = self.request("variables", { "variablesReference": reference })
  self.ensure_variable_identity(identity)
  guard parse_variables(response.body()) is Some(variables) else {
    raise InvalidMessage(response.body())
  }
  for variable in variables {
    if variable.variables_reference > 0 {
      self.machine.remember_variable_reference(variable.variables_reference)
    }
  }
  self.variable_cache.store_variables(identity, reference, variables)
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
priv struct DapIndexedCollectionLayout {
  kind : @moondbg.IndexedCollectionKind
  body : DapVariable
  element_type : @runtime_value.NativeArrayElementType
  payload_pointer : NativePayloadPointer
  total_length : Int
}

///|
async fn DebugExecution::load_native_indexed_collection_layout(
  self : DebugExecution,
  kind : @moondbg.IndexedCollectionKind,
  body : DapVariable,
  logical_length : Int?,
) -> DapIndexedCollectionLayout {
  guard body.type_name is Some(pointer_type) &&
    @runtime_value.native_array_element_from_pointer_type(pointer_type)
    is Some(element_type) else {
    raise InvalidIndexedCollectionValue(
      "\{kind.source_name()} has no typed body pointer",
    )
  }
  guard parse_native_payload_pointer(body.value) is Some(payload_pointer) else {
    raise InvalidIndexedCollectionValue(
      "\{kind.source_name()} body has malformed payload pointer '\{body.value}'",
    )
  }
  let capacity = match payload_pointer {
    NullPayloadPointer => 0
    PayloadPointer(memory_reference) => {
      let header = self.read_memory(
        memory_reference,
        @runtime_value.NATIVE_ARRAY_HEADER_OFFSET,
        @runtime_value.NATIVE_ARRAY_HEADER_SIZE,
      )
      @runtime_value.decode_native_array_capacity(header) catch {
        error => raise InvalidIndexedCollectionValue(@debug.to_string(error))
      }
    }
  }
  let total_length = logical_length.unwrap_or(capacity)
  @runtime_value.validate_array_length(total_length, capacity) catch {
    error => raise InvalidIndexedCollectionValue(@debug.to_string(error))
  }
  { kind, body, element_type, payload_pointer, total_length, }
}

///|
async fn DebugExecution::load_fixed_array_layout(
  self : DebugExecution,
  identity : VariableCacheIdentity,
  variable : DapVariable,
) -> DapIndexedCollectionLayout {
  let children = self.load_variables(identity, variable.variables_reference)
  guard children.named_child("body") is Some(body) else {
    raise InvalidIndexedCollectionValue("FixedArray has no body field")
  }
  self.load_native_indexed_collection_layout(
    @moondbg.FixedArrayCollection,
    body,
    None,
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
async fn DebugExecution::load_array_layout(
  self : DebugExecution,
  identity : VariableCacheIdentity,
  variable : DapVariable,
) -> DapIndexedCollectionLayout {
  let children = self.load_variables(identity, variable.variables_reference)
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
  let buffer_children = self.load_variables(
    identity,
    buffer.variables_reference,
  )
  guard buffer_children.named_child("body") is Some(body) else {
    raise InvalidIndexedCollectionValue("Array buffer has no body field")
  }
  self.load_native_indexed_collection_layout(
    @moondbg.ArrayCollection,
    body,
    Some(logical_length),
  )
}

///|
async fn DebugExecution::load_indexed_collection_layout(
  self : DebugExecution,
  identity : VariableCacheIdentity,
  variable : DapVariable,
) -> DapIndexedCollectionLayout? {
  if variable.is_moonbit_array_candidate() {
    return Some(self.load_array_layout(identity, variable))
  }
  if variable.is_moonbit_fixed_array_candidate() {
    return Some(self.load_fixed_array_layout(identity, variable))
  }
  None
}

///|
async fn DebugExecution::resolve_indexed_element(
  self : DebugExecution,
  identity : VariableCacheIdentity,
  frame_id : Int,
  owner : String,
  index : Int,
  variable : DapVariable,
) -> DapVariableResolution {
  guard variable.is_moonbit_array_candidate() ||
    variable.is_moonbit_fixed_array_candidate() else {
    return DapVariableResolutionFailed(
      @moondbg.VariableLookupResult::index_access_on_non_collection(
        owner,
        index,
        variable.type_name,
      ),
    )
  }
  let element_name = "\{owner}[\{index}]"
  let cache_key = "\{frame_id}:\{element_name}"
  if self.variable_cache.cached_evaluated_variable(identity, cache_key)
    is Some(cached) {
    return DapVariableResolved(cached)
  }
  guard self.load_indexed_collection_layout(identity, variable) is Some(layout) else {
    return DapVariableResolutionFailed(
      @moondbg.VariableLookupResult::index_access_on_non_collection(
        owner,
        index,
        variable.type_name,
      ),
    )
  }
  guard index >= 0 && index < layout.total_length else {
    return DapVariableResolutionFailed(
      @moondbg.VariableLookupResult::index_out_of_bounds(
        owner,
        index,
        layout.total_length,
      ),
    )
  }
  guard layout.body.evaluate_name is Some(evaluate_name) &&
    evaluate_name.trim() != "" else {
    raise InvalidIndexedElementValue(
      "\{layout.kind.source_name()} body has no evaluateName for indexed access",
    )
  }
  let expression = "\{evaluate_name}[\{index}]"
  let response = self.request("evaluate", {
    "expression": expression,
    "frameId": frame_id,
    "context": "watch",
  }) catch {
    error =>
      raise InvalidIndexedElementValue(
        "lldb-dap could not evaluate indexed element: \{@debug.to_string(error)}",
      )
  }
  self.ensure_variable_identity(identity)
  let evaluated = parse_indexed_element_evaluate_response(
    response.body(),
    element_name,
  )
  guard evaluated.is_available() else {
    raise InvalidIndexedElementValue(
      "indexed element '\{element_name}' is unavailable at the current location",
    )
  }
  guard !evaluated.is_moonbit_struct_type() || evaluated.variables_reference > 0 else {
    raise InvalidIndexedElementValue(
      "indexed element '\{element_name}' has no expandable value",
    )
  }
  if evaluated.variables_reference > 0 {
    self.machine.remember_variable_reference(evaluated.variables_reference)
  }
  self.variable_cache.store_evaluated_variable(identity, cache_key, evaluated)
  DapVariableResolved(evaluated)
}

///|
async fn DebugExecution::materialize_indexed_collection(
  self : DebugExecution,
  variable : DapVariable,
  layout : DapIndexedCollectionLayout,
) -> @moondbg.VariableSnapshot {
  let element_type_name = layout.element_type.source_name()
  let total_length = layout.total_length
  let plan = @runtime_value.IndexedPreviewPlan::new(total_length) catch {
    error => raise InvalidIndexedCollectionValue(@debug.to_string(error))
  }
  let elements : Array[@moondbg.IndexedVariableElement] = []
  match layout.element_type {
    @runtime_value.NativeArrayScalar(scalar) =>
      match layout.payload_pointer {
        NullPayloadPointer => {
          guard total_length == 0 else {
            raise InvalidIndexedCollectionValue(
              "\{layout.kind.source_name()} has a null non-empty payload",
            )
          }
        }
        PayloadPointer(memory_reference) => {
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
              error =>
                raise InvalidIndexedCollectionValue(@debug.to_string(error))
            }
            guard offset is Some(offset) else {
              raise InvalidIndexedCollectionValue(
                "\{layout.kind.source_name()} preview lost its tail offset",
              )
            }
            let payload = self.read_memory(memory_reference, offset, width)
            elements.push_iter(
              indexed_scalar_elements(scalar, tail_index, payload, 1).iter(),
            )
          }
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
    layout.kind,
    element_type_name,
    total_length,
    elements,
  )
  @moondbg.VariableSnapshot::indexed_collection(
    variable.name,
    variable.value,
    variable.type_name,
    collection,
  )
}

///|
async fn DebugExecution::materialize_fixed_array(
  self : DebugExecution,
  identity : VariableCacheIdentity,
  variable : DapVariable,
) -> @moondbg.VariableSnapshot {
  let layout = self.load_fixed_array_layout(identity, variable)
  self.materialize_indexed_collection(variable, layout)
}

///|
async fn DebugExecution::materialize_array(
  self : DebugExecution,
  identity : VariableCacheIdentity,
  variable : DapVariable,
) -> @moondbg.VariableSnapshot {
  let layout = self.load_array_layout(identity, variable)
  self.materialize_indexed_collection(variable, layout)
}

///|
fn direct_enum_payload_position(name : String) -> Int raise DapSessionError {
  guard name.strip_prefix(".") is Some(position_text) &&
    position_text != "" &&
    position_text.all(char => char is ('0'..='9')) else {
    raise InvalidEnumValue(
      "active enum payload '\{name}' has no decimal position",
    )
  }
  let position = Some(@string.parse_int(position_text, base=10)) catch {
    _ => None
  }
  guard position is Some(position) && position >= 0 else {
    raise InvalidEnumValue(
      "active enum payload '\{name}' has an invalid position",
    )
  }
  position
}

///|
fn direct_enum_payload(
  variable : DapVariable,
  position : Int,
) -> @moondbg.VariableEnumPayload raise DapSessionError {
  guard variable.type_name is Some(debug_type) &&
    @runtime_value.source_name_from_debug_type(debug_type) is Some(source_type) else {
    raise InvalidEnumValue("enum payload '.\{position}' has no usable type")
  }
  match @runtime_value.native_scalar_from_debug_type(debug_type) {
    Some(_) => {
      guard variable.is_available() else {
        raise InvalidEnumValue(
          "scalar enum payload '.\{position}' is unavailable",
        )
      }
      @moondbg.VariableEnumPayload::scalar(
        position,
        source_type,
        variable.value,
      )
    }
    None => @moondbg.VariableEnumPayload::aggregate(position, source_type)
  }
}

///|
async fn DebugExecution::materialize_enum(
  self : DebugExecution,
  identity : VariableCacheIdentity,
  variable : DapVariable,
  variants : Array[DapEnumVariant],
) -> @moondbg.VariableSnapshot {
  let active = self.active_enum_variant(variants)
  let direct_payload = if active.payload_reference > 0 {
    self.load_variables(identity, active.payload_reference)
  } else {
    []
  }
  let payload_by_position : Map[Int, @moondbg.VariableEnumPayload] = Map([])
  for child in direct_payload {
    let position = direct_enum_payload_position(child.name)
    guard position < direct_payload.length() &&
      payload_by_position.get(position) is None else {
      raise InvalidEnumValue(
        "active enum payload repeats or exceeds position \{position}",
      )
    }
    payload_by_position.set(position, direct_enum_payload(child, position))
  }
  let payload : Array[@moondbg.VariableEnumPayload] = []
  for position in 0..<direct_payload.length() {
    guard payload_by_position.get(position) is Some(element) else {
      raise InvalidEnumValue(
        "active enum payload is missing position \{position}",
      )
    }
    payload.push(element)
  }
  let enum_value = @moondbg.VariableEnumSnapshot::new(
    active.variant_name,
    payload,
  ) catch {
    error => raise InvalidEnumValue(@debug.to_string(error))
  }
  @moondbg.VariableSnapshot::enum_value(
    variable.name,
    variable.type_name,
    enum_value,
  )
}

///|
async fn DebugExecution::active_enum_variant(
  self : DebugExecution,
  variants : Array[DapEnumVariant],
) -> DapEnumVariant {
  self.active_enum_variant_raw(variants) catch {
    InvalidIndexedCollectionValue(message) =>
      raise InvalidEnumValue("failed to read boxed enum descriptor: \{message}")
    error => raise error
  }
}

///|
/// Reads only the enum descriptor while preserving request/protocol failures.
/// Compact locals can therefore downgrade an invalid descriptor without
/// accidentally hiding an adapter request failure.
async fn DebugExecution::active_enum_variant_raw(
  self : DebugExecution,
  variants : Array[DapEnumVariant],
) -> DapEnumVariant {
  guard variants is [first, ..] else {
    raise InvalidEnumValue("boxed enum has no variant views")
  }
  let descriptor = self.read_memory(
    first.payload_pointer,
    @runtime_value.NATIVE_ENUM_DESCRIPTOR_OFFSET,
    @runtime_value.NATIVE_ENUM_DESCRIPTOR_SIZE,
  )
  let active_tag = @runtime_value.decode_boxed_enum_tag(descriptor) catch {
    error =>
      raise InvalidEnumValue(
        "invalid boxed enum descriptor: \{@debug.to_string(error)}",
      )
  }
  for variant in variants {
    if variant.tag == active_tag {
      return variant
    }
  }
  raise InvalidEnumValue(
    "boxed enum descriptor selects unknown tag \{active_tag}",
  )
}

///|
fn ambiguous_local_summary(
  name : String,
  variables : Array[DapVariable],
) -> @moondbg.LocalVariableSnapshot {
  let mut type_name : String? = None
  let mut same_type = true
  for index, variable in variables.iter2() {
    let current = variable.source_type_name()
    if index == 0 {
      type_name = current
    } else if current != type_name {
      same_type = false
    }
  }
  @moondbg.LocalVariableSnapshot::new(
    name,
    if same_type {
      type_name
    } else {
      None
    },
    @moondbg.LocalVariableAmbiguous,
  )
}

///|
async fn DebugExecution::compact_local_variable(
  self : DebugExecution,
  identity : VariableCacheIdentity,
  variable : DapVariable,
) -> @moondbg.LocalVariableSnapshot {
  let name = variable.source_local_name()
  let source_type = variable.source_type_name()
  guard variable.is_available() else {
    return @moondbg.LocalVariableSnapshot::new(
      name,
      source_type,
      @moondbg.LocalVariableUnavailable,
    )
  }
  if variable.is_moonbit_array_candidate() ||
    variable.is_moonbit_fixed_array_candidate() {
    let layout = self.load_indexed_collection_layout(identity, variable) catch {
      InvalidIndexedCollectionValue(_) =>
        return @moondbg.LocalVariableSnapshot::new(
          name,
          source_type,
          @moondbg.LocalVariableAvailable(@moondbg.LocalOpaque),
        )
      error => raise error
    }
    guard layout is Some(layout) else {
      return @moondbg.LocalVariableSnapshot::new(
        name,
        source_type,
        @moondbg.LocalVariableAvailable(@moondbg.LocalOpaque),
      )
    }
    let type_name = Some(
      "\{layout.kind.source_name()}[\{layout.element_type.source_name()}]",
    )
    return @moondbg.LocalVariableSnapshot::new(
      name,
      type_name,
      @moondbg.LocalVariableAvailable(
        @moondbg.LocalCollection(layout.kind, layout.total_length),
      ),
    )
  }
  if variable.is_moonbit_struct_type() {
    return @moondbg.LocalVariableSnapshot::new(
      name,
      source_type,
      @moondbg.LocalVariableAvailable(@moondbg.LocalStructure),
    )
  }
  if variable.variables_reference > 0 {
    let children = self.load_variables(identity, variable.variables_reference)
    let enum_layout = detect_dap_enum_layout(children) catch {
      InvalidEnumValue(_) =>
        return @moondbg.LocalVariableSnapshot::new(
          name,
          source_type,
          @moondbg.LocalVariableAvailable(@moondbg.LocalOpaque),
        )
      error => raise error
    }
    match enum_layout {
      DapEnum(variants) => {
        let active = self.active_enum_variant_raw(variants) catch {
          InvalidIndexedCollectionValue(_) | InvalidEnumValue(_) =>
            return @moondbg.LocalVariableSnapshot::new(
              name,
              source_type,
              @moondbg.LocalVariableAvailable(@moondbg.LocalOpaque),
            )
          error => raise error
        }
        return @moondbg.LocalVariableSnapshot::new(
          name,
          source_type,
          @moondbg.LocalVariableAvailable(
            @moondbg.LocalEnumConstructor(active.variant_name),
          ),
        )
      }
      NotDapEnum => ()
    }
    return @moondbg.LocalVariableSnapshot::new(
      name,
      source_type,
      @moondbg.LocalVariableAvailable(@moondbg.LocalOpaque),
    )
  }
  @moondbg.LocalVariableSnapshot::new(
    name,
    source_type,
    @moondbg.LocalVariableAvailable(@moondbg.LocalScalar(variable.value)),
  )
}

///|
async fn DebugExecution::load_local_variables_inner(
  self : DebugExecution,
  identity : VariableCacheIdentity,
  frame_id : Int,
  thread : @moondbg.ThreadSelection,
  frame : @moondbg.FrameSelection,
) -> @moondbg.LocalVariablesSnapshot {
  if self.variable_cache.cached_local_snapshot(identity) is Some(snapshot) {
    return snapshot
  }
  let scopes = self.load_scopes(identity, frame_id)
  let local_scopes = scopes.filter(scope => scope.is_locals())
  guard local_scopes is [_, ..] else {
    let snapshot = @moondbg.LocalVariablesSnapshot::scope_unavailable(
      thread, frame,
    )
    self.variable_cache.store_local_snapshot(identity, snapshot)
    return snapshot
  }
  let groups : Map[String, Array[DapVariable]] = Map([])
  let order : Array[String] = []
  for scope in local_scopes {
    for variable in self.load_variables(identity, scope.variables_reference) {
      let name = variable.source_local_name()
      match groups.get(name) {
        Some(group) => group.push(variable)
        None => {
          groups.set(name, [variable])
          order.push(name)
        }
      }
    }
  }
  let summaries : Array[@moondbg.LocalVariableSnapshot] = []
  for name in order {
    guard groups.get(name) is Some(group) else { continue }
    match group {
      [variable] =>
        summaries.push(self.compact_local_variable(identity, variable))
      [_, _, ..] => summaries.push(ambiguous_local_summary(name, group))
      [] => ()
    }
  }
  self.ensure_variable_identity(identity)
  let snapshot = @moondbg.LocalVariablesSnapshot::available(
    thread, frame, summaries,
  )
  self.variable_cache.store_local_snapshot(identity, snapshot)
  snapshot
}

///|
async fn DebugExecution::materialize_variable(
  self : DebugExecution,
  identity : VariableCacheIdentity,
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
    return self.materialize_array(identity, variable)
  }
  if variable.is_moonbit_fixed_array_candidate() {
    return self.materialize_fixed_array(identity, variable)
  }
  if variable.is_moonbit_struct_candidate() &&
    (
      budget.is_empty() ||
      depth >= budget.max_depth ||
      budget.is_visiting(variable.variables_reference)
    ) {
    return @moondbg.VariableSnapshot::truncated(
      variable.name,
      variable.value,
      variable.type_name,
      [],
    )
  }
  guard variable.variables_reference > 0 else { return variable.snapshot() }
  let dap_children = self.load_variables(identity, variable.variables_reference)
  match detect_dap_enum_layout(dap_children) {
    DapEnum(variants) =>
      return self.materialize_enum(identity, variable, variants)
    NotDapEnum => ()
  }
  guard variable.is_moonbit_struct_candidate() else {
    return variable.snapshot()
  }
  budget.enter_reference(variable.variables_reference)
  defer budget.leave_reference(variable.variables_reference)
  let children : Array[@moondbg.VariableSnapshot] = []
  let mut truncated = false
  for child in dap_children {
    if budget.is_empty() {
      truncated = true
      break
    }
    children.push(self.materialize_variable(identity, child, depth + 1, budget))
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
  identity : VariableCacheIdentity,
  variable : DapVariable,
  max_depth : Int,
  max_nodes : Int,
) -> @moondbg.VariableSnapshot {
  let budget = VariableMaterializationBudget::new(max_depth, max_nodes)
  self.materialize_variable(identity, variable, 0, budget)
}

///|
priv enum DapVariableResolution {
  DapVariableResolved(DapVariable)
  DapVariableResolutionFailed(@moondbg.VariableLookupResult)
}

///|
async fn DebugExecution::resolve_root_variable(
  self : DebugExecution,
  identity : VariableCacheIdentity,
  frame_id : Int,
  name : String,
) -> DapVariableResolution {
  let scopes = self.load_scopes(identity, frame_id)
  for scope in scopes {
    guard scope.is_relevant() else { continue }
    match
      self
      .load_variables(identity, scope.variables_reference)
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
  identity : VariableCacheIdentity,
  frame_id : Int,
  path : @moondbg.VariablePath,
) -> DapVariableResolution {
  let mut variable = match
    self.resolve_root_variable(identity, frame_id, path.root_name()) {
    DapVariableResolved(variable) => variable
    DapVariableResolutionFailed(result) =>
      return DapVariableResolutionFailed(result)
  }
  let mut owner = path.root_name()
  for step in path.steps() {
    match step {
      @moondbg.Field(field) => {
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
        let children = self.load_variables(
          identity,
          variable.variables_reference,
        )
        match detect_dap_enum_layout(children) {
          DapEnum(_) =>
            return DapVariableResolutionFailed(
              @moondbg.VariableLookupResult::field_access_on_non_struct(
                owner,
                field,
                variable.type_name,
              ),
            )
          NotDapEnum => ()
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
      @moondbg.Index(index) =>
        match
          self.resolve_indexed_element(
            identity, frame_id, owner, index, variable,
          ) {
          DapVariableResolved(element) => {
            variable = element
            owner = "\{owner}[\{index}]"
          }
          DapVariableResolutionFailed(result) =>
            return DapVariableResolutionFailed(result)
        }
    }
  }
  DapVariableResolved({ ..variable, name: path.display_name(), })
}

///|
async fn DebugExecution::find_variable_inner(
  self : DebugExecution,
  identity : VariableCacheIdentity,
  frame_id : Int,
  path : @moondbg.VariablePath,
) -> @moondbg.VariableLookupResult {
  let cache_key = "\{identity.frame_index}:\{path.display_name()}"
  if self.variable_cache.cached_snapshot(identity, cache_key) is Some(snapshot) {
    return @moondbg.VariableLookupResult::found(snapshot)
  }
  let variable = match self.resolve_variable_path(identity, frame_id, path) {
    DapVariableResolved(variable) => variable
    DapVariableResolutionFailed(result) => return result
  }
  let snapshot = self.materialize_variable_with_limits(
    identity,
    variable,
    MAX_VARIABLE_EXPANSION_DEPTH,
    MAX_VARIABLE_EXPANSION_NODES,
  )
  self.variable_cache.store_snapshot(identity, cache_key, snapshot)
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
  self.variable_cache.select_frame(epoch, frame.index())
  let identity = VariableCacheIdentity::{ epoch, frame_index: frame.index(), }
  let frame_id = self.selected_frame_id(thread, frame, "inspect a variable")
  let result = self.find_variable_inner(identity, frame_id, path) catch {
    error => raise LldbDapBackendError::AdapterFailure(@debug.to_string(error))
  }
  guard self.machine.current_stop_epoch() == Some(epoch) &&
    self.variable_cache.is_current(identity) else {
    raise LldbDapBackendError::AdapterFailure(
      "variable result belongs to a stale stop or frame",
    )
  }
  result
}

///|
async fn DebugExecution::local_variables(
  self : DebugExecution,
  thread : @moondbg.ThreadSelection,
  frame : @moondbg.FrameSelection,
) -> @moondbg.LocalVariablesSnapshot {
  guard self.machine.state is Stopped &&
    self.machine.current_stop_epoch() is Some(epoch) else {
    raise LldbDapBackendError::OperationNotAllowed(
      state=self.machine.state,
      action="inspect local variables",
    )
  }
  self.variable_cache.select_frame(epoch, frame.index())
  let identity = VariableCacheIdentity::{ epoch, frame_index: frame.index(), }
  let frame_id = self.selected_frame_id(
    thread, frame, "inspect local variables",
  )
  let result = self.load_local_variables_inner(
    identity, frame_id, thread, frame,
  ) catch {
    error => raise LldbDapBackendError::AdapterFailure(@debug.to_string(error))
  }
  guard self.machine.current_stop_epoch() == Some(epoch) &&
    self.variable_cache.is_current(identity) else {
    raise LldbDapBackendError::AdapterFailure(
      "local-variable result belongs to a stale stop or frame",
    )
  }
  result
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

///|
async fn LldbDapSession::local_variables(
  self : LldbDapSession,
  thread : @moondbg.ThreadSelection,
  frame : @moondbg.FrameSelection,
) -> @moondbg.LocalVariablesSnapshot {
  guard self.execution is Some(execution) else {
    raise LldbDapBackendError::OperationNotAllowed(
      state=self.detached_state,
      action="inspect local variables",
    )
  }
  execution.local_variables(thread, frame) catch {
    LldbDapBackendError::AdapterFailure(message) => {
      self.recover_failed_execution(execution, try_disconnect=true) catch {
        _ => ()
      }
      raise LldbDapBackendError::AdapterFailure(message)
    }
    error => raise error
  }
}
