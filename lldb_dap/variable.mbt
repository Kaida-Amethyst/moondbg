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
}

///|
fn DapVariable::snapshot(self : DapVariable) -> @moondbg.VariableSnapshot {
  @moondbg.VariableSnapshot::new(self.name, self.value, self.type_name)
}

///|
fn DapVariable::is_moonbit_struct_candidate(self : DapVariable) -> Bool {
  guard self.variables_reference > 0 &&
    self.type_name is Some(type_name) &&
    type_name.strip_suffix(" &") is Some(base) &&
    base.rev_split_once("/") is Some((package_name, struct_name)) else {
    return false
  }
  package_name != "" && struct_name != ""
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
}

///|
fn StopVariableCache::new() -> StopVariableCache {
  { epoch: 0, scopes: None, variables: Map([]), }
}

///|
fn StopVariableCache::reset(self : StopVariableCache, epoch : Int) -> Unit {
  self.epoch = epoch
  self.scopes = None
  self.variables.clear()
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
async fn DebugExecution::find_variable_inner(
  self : DebugExecution,
  epoch : Int,
  frame_id : Int,
  name : String,
) -> @moondbg.VariableLookupResult {
  let scopes = self.load_scopes(epoch, frame_id)
  for scope in scopes {
    guard scope.is_relevant() else { continue }
    for variable in self.load_variables(epoch, scope.variables_reference) {
      if variable.name == name {
        let snapshot = self.materialize_variable_with_limits(
          epoch,
          variable,
          MAX_VARIABLE_EXPANSION_DEPTH,
          MAX_VARIABLE_EXPANSION_NODES,
        )
        return @moondbg.VariableLookupResult::found(snapshot)
      }
    }
  }
  @moondbg.VariableLookupResult::not_found(name)
}

///|
async fn DebugExecution::find_variable(
  self : DebugExecution,
  thread : @moondbg.ThreadSelection,
  frame : @moondbg.FrameSelection,
  name : String,
) -> @moondbg.VariableLookupResult {
  guard self.machine.state is Stopped &&
    self.machine.current_stop_epoch() is Some(epoch) else {
    raise LldbDapBackendError::OperationNotAllowed(
      state=self.machine.state,
      action="inspect a variable",
    )
  }
  let frame_id = self.selected_frame_id(thread, frame, "inspect a variable")
  self.find_variable_inner(epoch, frame_id, name) catch {
    error => raise LldbDapBackendError::AdapterFailure(@debug.to_string(error))
  }
}

///|
async fn LldbDapSession::find_variable(
  self : LldbDapSession,
  thread : @moondbg.ThreadSelection,
  frame : @moondbg.FrameSelection,
  name : String,
) -> @moondbg.VariableLookupResult {
  guard self.execution is Some(execution) else {
    raise LldbDapBackendError::OperationNotAllowed(
      state=self.detached_state,
      action="inspect a variable",
    )
  }
  execution.find_variable(thread, frame, name) catch {
    LldbDapBackendError::AdapterFailure(message) => {
      self.recover_failed_execution(execution, try_disconnect=true) catch {
        _ => ()
      }
      raise LldbDapBackendError::AdapterFailure(message)
    }
    error => raise error
  }
}
