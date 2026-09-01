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
    source_breakpoints : Array[SourceBreakpoint],
    function_breakpoints : Array[FunctionBreakpoint],
  ) -> RunOutcome
  async fn install_source_breakpoint(Self, breakpoint : SourceBreakpoint) -> BreakpointSnapshot
  async fn install_function_breakpoint(Self, breakpoint : FunctionBreakpoint) -> FunctionBreakpointSnapshot
  async fn continue_execution(Self, thread : ThreadSelection) -> RunOutcome
  async fn next(Self, thread : ThreadSelection) -> RunOutcome
  async fn step(Self, thread : ThreadSelection) -> RunOutcome
  async fn finish(Self, thread : ThreadSelection) -> RunOutcome
  /// Returns the currently loaded application-level stack window.
  ///
  /// The result may be partial. Implementations retain protocol frame ids and
  /// perform any later paging behind this port.
  async fn stack_snapshot(Self, thread : ThreadSelection, window : StackWindow) -> StackSnapshot
  async fn find_variable(
    Self,
    thread : ThreadSelection,
    frame : FrameSelection,
    path : VariablePath,
  ) -> VariableLookupResult
  async fn local_variables(
    Self,
    thread : ThreadSelection,
    frame : FrameSelection,
  ) -> LocalVariablesSnapshot
  fn breakpoint_snapshots(Self) -> Array[BreakpointSnapshot]
  fn function_breakpoint_snapshots(Self) -> Array[FunctionBreakpointSnapshot]
  fn take_output(Self) -> Array[DebugOutput]
  async fn disconnect(Self) -> Unit
  fn close(Self) -> Unit
}
