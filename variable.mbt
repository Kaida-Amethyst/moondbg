///|
pub struct VariableSnapshot {
  name : String
  value : String
  type_name : String?
  variables_reference : Int
}

///|
pub fn VariableSnapshot::name(self : VariableSnapshot) -> String {
  self.name
}

///|
pub fn VariableSnapshot::value(self : VariableSnapshot) -> String {
  self.value
}

///|
pub fn VariableSnapshot::type_name(self : VariableSnapshot) -> String? {
  self.type_name
}

///|
pub fn VariableSnapshot::variables_reference(self : VariableSnapshot) -> Int {
  self.variables_reference
}

///|
pub enum VariableLookupResult {
  VariableFound(VariableSnapshot)
  VariableNotFound(String)
}

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
fn DapVariable::snapshot(self : DapVariable) -> VariableSnapshot {
  {
    name: self.name,
    value: self.value,
    type_name: self.type_name,
    variables_reference: self.variables_reference,
  }
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
