///|
/// Whether lldb-dap exposed a Locals scope for the selected physical frame.
pub(all) enum LocalScopeAvailability {
  LocalScopeAvailable
  LocalScopeUnavailable
} derive(Eq, Debug)

///|
pub extend LocalScopeAvailability with Eq::{equal, not_equal}

///|
pub extend LocalScopeAvailability with @debug.Debug::{to_repr}

///|
/// A bounded, presentation-independent summary of one available local value.
pub(all) enum LocalCompactValue {
  LocalScalar(String)
  LocalCollection(IndexedCollectionKind, Int)
  LocalStructure
  LocalEnumConstructor(String)
  LocalOpaque
} derive(Eq, Debug)

///|
pub extend LocalCompactValue with Eq::{equal, not_equal}

///|
pub extend LocalCompactValue with @debug.Debug::{to_repr}

///|
/// Availability is kept separate from value shape so frontends never have to
/// parse adapter error strings or invent a value for an ambiguous binding.
pub(all) enum LocalVariableAvailability {
  LocalVariableAvailable(LocalCompactValue)
  LocalVariableUnavailable
  LocalVariableFailure(VariableLookupFailure)
  LocalVariableAmbiguous
} derive(Eq, Debug)

///|
pub extend LocalVariableAvailability with Eq::{equal, not_equal}

///|
pub extend LocalVariableAvailability with @debug.Debug::{to_repr}

///|
/// One source-facing local or parameter in the selected physical frame.
pub struct LocalVariableSnapshot {
  priv name : String
  priv type_name : String?
  priv availability : LocalVariableAvailability
} derive(Eq, Debug)

///|
pub extend LocalVariableSnapshot with Eq::{equal, not_equal}

///|
pub extend LocalVariableSnapshot with @debug.Debug::{to_repr}

///|
pub fn LocalVariableSnapshot::new(
  name : String,
  type_name : String?,
  availability : LocalVariableAvailability,
) -> LocalVariableSnapshot {
  { name, type_name, availability, }
}

///|
pub fn LocalVariableSnapshot::name(self : LocalVariableSnapshot) -> String {
  self.name
}

///|
pub fn LocalVariableSnapshot::type_name(
  self : LocalVariableSnapshot,
) -> String? {
  self.type_name
}

///|
pub fn LocalVariableSnapshot::availability(
  self : LocalVariableSnapshot,
) -> LocalVariableAvailability {
  self.availability
}

///|
/// The local-variable result for one selected physical frame. An available
/// empty scope is intentionally distinct from a frame with no Locals scope.
pub struct LocalVariablesSnapshot {
  priv thread : ThreadSelection
  priv frame : FrameSelection
  priv scope_availability : LocalScopeAvailability
  priv variables : Array[LocalVariableSnapshot]
} derive(Eq, Debug)

///|
pub extend LocalVariablesSnapshot with Eq::{equal, not_equal}

///|
pub extend LocalVariablesSnapshot with @debug.Debug::{to_repr}

///|
pub fn LocalVariablesSnapshot::available(
  thread : ThreadSelection,
  frame : FrameSelection,
  variables : Array[LocalVariableSnapshot],
) -> LocalVariablesSnapshot {
  {
    thread,
    frame,
    scope_availability: LocalScopeAvailable,
    variables: variables.copy(),
  }
}

///|
pub fn LocalVariablesSnapshot::scope_unavailable(
  thread : ThreadSelection,
  frame : FrameSelection,
) -> LocalVariablesSnapshot {
  { thread, frame, scope_availability: LocalScopeUnavailable, variables: [], }
}

///|
pub fn LocalVariablesSnapshot::thread(
  self : LocalVariablesSnapshot,
) -> ThreadSelection {
  self.thread
}

///|
pub fn LocalVariablesSnapshot::frame(
  self : LocalVariablesSnapshot,
) -> FrameSelection {
  self.frame
}

///|
pub fn LocalVariablesSnapshot::scope_availability(
  self : LocalVariablesSnapshot,
) -> LocalScopeAvailability {
  self.scope_availability
}

///|
pub fn LocalVariablesSnapshot::variables(
  self : LocalVariablesSnapshot,
) -> ReadOnlyArray[LocalVariableSnapshot] {
  ReadOnlyArray::from_array(self.variables)
}
