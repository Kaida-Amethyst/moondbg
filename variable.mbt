///|
pub struct VariableSnapshot {
  priv name : String
  priv value : String
  priv type_name : String?
}

///|
/// Creates a debugger-domain variable value with no adapter reference.
pub fn VariableSnapshot::new(
  name : String,
  value : String,
  type_name : String?,
) -> VariableSnapshot {
  { name, value, type_name, }
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
pub enum VariableLookupResult {
  VariableFound(VariableSnapshot)
  VariableNotFound(String)
}

///|
pub fn VariableLookupResult::found(
  variable : VariableSnapshot,
) -> VariableLookupResult {
  VariableFound(variable)
}

///|
pub fn VariableLookupResult::not_found(name : String) -> VariableLookupResult {
  VariableNotFound(name)
}
