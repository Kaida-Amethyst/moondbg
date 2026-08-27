///|
/// User-visible debugger phase owned by DebugSession.
///
/// Adapter initialization and protocol configuration states intentionally do
/// not appear here.
pub enum DebugSessionState {
  Ready
  Running
  Stopped
  Exited
  Failed
} derive(Debug, Eq)

///|
pub extend DebugSessionState with @debug.Debug::{to_repr}

///|
pub extend DebugSessionState with Eq::{equal, not_equal}

///|
pub suberror DebugSessionError {
  OperationNotAllowed(state~ : DebugSessionState, action~ : String)
  AdapterFailure(String)
} derive(Debug)

///|
pub extend DebugSessionError with @debug.Debug::{to_repr}

///|
/// Identifies one launch attempt within a DebugSession. Values are monotonic
/// and contain no adapter execution identifier.
pub struct ExecutionEpoch {
  priv number : Int
} derive(Debug, Eq)

///|
pub extend ExecutionEpoch with @debug.Debug::{to_repr}

///|
pub extend ExecutionEpoch with Eq::{equal, not_equal}

///|
fn ExecutionEpoch::new(number : Int) -> ExecutionEpoch {
  { number, }
}

///|
pub fn ExecutionEpoch::number(self : ExecutionEpoch) -> Int {
  self.number
}

///|
/// Identifies one stable stop inside an application execution epoch. The stop
/// number restarts at one for each execution.
pub struct StopEpoch {
  priv execution : ExecutionEpoch
  priv number : Int
} derive(Debug, Eq)

///|
pub extend StopEpoch with @debug.Debug::{to_repr}

///|
pub extend StopEpoch with Eq::{equal, not_equal}

///|
fn StopEpoch::new(execution : ExecutionEpoch, number : Int) -> StopEpoch {
  { execution, number, }
}

///|
pub fn StopEpoch::execution(self : StopEpoch) -> ExecutionEpoch {
  self.execution
}

///|
pub fn StopEpoch::number(self : StopEpoch) -> Int {
  self.number
}

///|
/// Application-owned state for the current stable stop. Thread and frame
/// selections are logical domain values; an adapter maps them to temporary
/// protocol identifiers for the active execution.
priv struct StableStopState {
  epoch : StopEpoch
  snapshot : StopSnapshot
  thread : ThreadSelection
  frame : FrameSelection
}

///|
/// Mutable application state kept behind DebugSession. Protocol lifecycle and
/// adapter identifiers must not be added to this type.
priv struct DebugApplicationState {
  mut phase : DebugSessionState
  mut execution_number : Int
  mut stop_number : Int
  mut stable_stop : StableStopState?
}

///|
fn DebugApplicationState::new() -> DebugApplicationState {
  { phase: Ready, execution_number: 0, stop_number: 0, stable_stop: None, }
}

///|
fn DebugApplicationState::execution_epoch(
  self : DebugApplicationState,
) -> ExecutionEpoch? {
  guard self.execution_number > 0 else { return None }
  Some(ExecutionEpoch::new(self.execution_number))
}

///|
fn DebugApplicationState::stop_epoch(
  self : DebugApplicationState,
) -> StopEpoch? {
  self.stable_stop.map(stop => stop.epoch)
}

///|
fn DebugApplicationState::last_stop_snapshot(
  self : DebugApplicationState,
) -> StopSnapshot? {
  self.stable_stop.map(stop => stop.snapshot)
}

///|
fn DebugApplicationState::selected_thread(
  self : DebugApplicationState,
) -> ThreadSelection? {
  self.stable_stop.map(stop => stop.thread)
}

///|
fn DebugApplicationState::selected_frame(
  self : DebugApplicationState,
) -> FrameSelection? {
  self.stable_stop.map(stop => stop.frame)
}

///|
fn DebugApplicationState::begin_execution(self : DebugApplicationState) -> Unit {
  self.execution_number += 1
  self.stop_number = 0
  self.stable_stop = None
  self.phase = Running
}

///|
fn DebugApplicationState::begin_resume(self : DebugApplicationState) -> Unit {
  self.stable_stop = None
  self.phase = Running
}

///|
fn DebugApplicationState::accept_outcome(
  self : DebugApplicationState,
  outcome : RunOutcome,
) -> Unit {
  match outcome {
    Stopped(snapshot) => {
      self.stop_number += 1
      let execution = ExecutionEpoch::new(self.execution_number)
      self.stable_stop = Some({
        epoch: StopEpoch::new(execution, self.stop_number),
        snapshot,
        thread: ThreadSelection::initial(),
        frame: FrameSelection::initial(),
      })
      self.phase = Stopped
    }
    Exited(_) => {
      self.stable_stop = None
      self.phase = Ready
    }
  }
}

///|
fn DebugApplicationState::transition_without_stop(
  self : DebugApplicationState,
  phase : DebugSessionState,
) -> Unit {
  self.stable_stop = None
  self.phase = phase
}
