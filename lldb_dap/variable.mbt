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
        return @moondbg.VariableLookupResult::found(variable.snapshot())
      }
    }
  }
  @moondbg.VariableLookupResult::not_found(name)
}

///|
async fn DebugExecution::find_variable(
  self : DebugExecution,
  name : String,
) -> @moondbg.VariableLookupResult {
  guard self.machine.state is Stopped &&
    self.machine.current_stop_epoch() is Some(epoch) &&
    self.machine.selected_frame_id() is Some(frame_id) else {
    raise LldbDapBackendError::OperationNotAllowed(
      state=self.machine.state,
      action="inspect a variable",
    )
  }
  self.find_variable_inner(epoch, frame_id, name) catch {
    error => raise LldbDapBackendError::AdapterFailure(@debug.to_string(error))
  }
}

///|
async fn LldbDapSession::find_variable(
  self : LldbDapSession,
  name : String,
) -> @moondbg.VariableLookupResult {
  guard self.execution is Some(execution) else {
    raise LldbDapBackendError::OperationNotAllowed(
      state=self.detached_state,
      action="inspect a variable",
    )
  }
  execution.find_variable(name) catch {
    LldbDapBackendError::AdapterFailure(message) => {
      self.recover_failed_execution(execution, try_disconnect=true) catch {
        _ => ()
      }
      raise LldbDapBackendError::AdapterFailure(message)
    }
    error => raise error
  }
}
