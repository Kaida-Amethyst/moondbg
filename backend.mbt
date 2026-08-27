///|
/// A source breakpoint configured by the application layer.
///
/// Its id is stable for the lifetime of a DebugSession. Backend-specific
/// breakpoint identifiers must not be stored in this value.
pub struct SourceBreakpoint {
  priv id : Int
  priv source_path : String
  priv requested_line : Int
}

///|
fn SourceBreakpoint::new(
  id : Int,
  source_path : String,
  requested_line : Int,
) -> SourceBreakpoint {
  { id, source_path, requested_line, }
}

///|
pub fn SourceBreakpoint::id(self : SourceBreakpoint) -> Int {
  self.id
}

///|
pub fn SourceBreakpoint::source_path(self : SourceBreakpoint) -> String {
  self.source_path
}

///|
pub fn SourceBreakpoint::requested_line(self : SourceBreakpoint) -> Int {
  self.requested_line
}

///|
fn SourceBreakpoint::pending_snapshot(
  self : SourceBreakpoint,
) -> BreakpointSnapshot {
  BreakpointSnapshot::pending(self.id, self.source_path, self.requested_line)
}

///|
/// A failure reported by a debugger backend after protocol details have been
/// translated at the adapter boundary.
pub suberror DebugBackendError {
  BackendFailure(String)
} derive(Debug)

///|
/// Creates a backend failure after an adapter has removed protocol details.
pub fn DebugBackendError::failure(message : String) -> DebugBackendError {
  BackendFailure(message)
}

///|
pub extend DebugBackendError with @debug.Debug::{to_repr}

///|
/// High-level debugger capabilities consumed by DebugSession.
///
/// Implementations own adapter processes, executions, capabilities and all
/// protocol-scoped identifiers. Inputs and results are debugger domain values;
/// implementations must not expose protocol messages or transport state.
pub(open) trait DebugBackend {
  async fn launch(
    Self,
    executable : String,
    breakpoints : Array[SourceBreakpoint],
  ) -> RunOutcome
  async fn continue_execution(Self) -> RunOutcome
  async fn next(Self) -> RunOutcome
  async fn step(Self) -> RunOutcome
  async fn finish(Self) -> RunOutcome
  async fn find_variable(Self, name : String) -> VariableLookupResult
  fn breakpoint_snapshots(Self) -> Array[BreakpointSnapshot]
  fn take_output(Self) -> Array[DebugOutput]
  async fn disconnect(Self) -> Unit
  fn close(Self) -> Unit
}
