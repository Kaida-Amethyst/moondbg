///|
pub enum VariableExpansion {
  VariableLeaf
  VariableExpanded
  VariableTruncated
} derive(Eq, Debug)

///|
pub extend VariableExpansion with Eq::{equal, not_equal}

///|
pub extend VariableExpansion with @debug.Debug::{to_repr}

///|
pub struct VariableSnapshot {
  priv name : String
  priv value : String
  priv type_name : String?
  priv expansion : VariableExpansion
  priv children : Array[VariableSnapshot]
} derive(Eq, Debug)

///|
pub extend VariableSnapshot with Eq::{equal, not_equal}

///|
pub extend VariableSnapshot with @debug.Debug::{to_repr}

///|
/// Creates a debugger-domain variable value with no adapter reference.
pub fn VariableSnapshot::new(
  name : String,
  value : String,
  type_name : String?,
) -> VariableSnapshot {
  { name, value, type_name, expansion: VariableLeaf, children: [], }
}

///|
/// Creates a debugger-domain variable whose children were fully materialized.
pub fn VariableSnapshot::expanded(
  name : String,
  value : String,
  type_name : String?,
  children : Array[VariableSnapshot],
) -> VariableSnapshot {
  {
    name,
    value,
    type_name,
    expansion: VariableExpanded,
    children: children.copy(),
  }
}

///|
/// Creates a debugger-domain variable whose remaining children were omitted.
pub fn VariableSnapshot::truncated(
  name : String,
  value : String,
  type_name : String?,
  children : Array[VariableSnapshot],
) -> VariableSnapshot {
  {
    name,
    value,
    type_name,
    expansion: VariableTruncated,
    children: children.copy(),
  }
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
pub fn VariableSnapshot::expansion(
  self : VariableSnapshot,
) -> VariableExpansion {
  self.expansion
}

///|
pub fn VariableSnapshot::children(
  self : VariableSnapshot,
) -> ReadOnlyArray[VariableSnapshot] {
  ReadOnlyArray::from_array(self.children)
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
