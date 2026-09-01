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
  FrameNotLoaded(Int)
  FrameNotFound(Int)
  NoFrameSelected
  NoVisibleCaller(Int)
  NoVisibleCallee(Int)
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
  stack : StackSnapshot
  mut frame : FrameSelection?
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
  match self.stable_stop {
    Some(stop) => stop.frame
    None => None
  }
}

///|
fn DebugApplicationState::stack_snapshot(
  self : DebugApplicationState,
) -> StackSnapshot? {
  self.stable_stop.map(stop => stop.stack)
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
fn DebugApplicationState::accept_stopped(
  self : DebugApplicationState,
  snapshot : StopSnapshot,
  stack : StackSnapshot,
) -> Unit {
  self.stop_number += 1
  let execution = ExecutionEpoch::new(self.execution_number)
  self.stable_stop = Some({
    epoch: StopEpoch::new(execution, self.stop_number),
    snapshot,
    thread: stack.thread(),
    stack,
    frame: stack.default_selection(),
  })
  self.phase = Stopped
}

///|
fn DebugApplicationState::accept_exit(self : DebugApplicationState) -> Unit {
  self.stable_stop = None
  self.phase = Ready
}

///|
fn DebugApplicationState::select_frame(
  self : DebugApplicationState,
  physical_index : Int,
) -> StackFrameSnapshot raise DebugSessionError {
  guard self.phase is Stopped && self.stable_stop is Some(stop) else {
    raise OperationNotAllowed(state=self.phase, action="select a frame")
  }
  guard stop.stack.is_loaded(physical_index) else {
    raise FrameNotLoaded(physical_index)
  }
  guard stop.stack.frame(physical_index) is Some(frame) else {
    raise FrameNotFound(physical_index)
  }
  stop.frame = Some(FrameSelection::at(physical_index))
  frame
}

///|
fn DebugApplicationState::select_visible_caller(
  self : DebugApplicationState,
) -> StackFrameSnapshot raise DebugSessionError {
  guard self.phase is Stopped &&
    self.stable_stop is Some(stop) &&
    stop.frame is Some(selection) else {
    if self.phase is Stopped {
      raise NoFrameSelected
    }
    raise OperationNotAllowed(state=self.phase, action="select a caller frame")
  }
  match stop.stack.visible_caller(selection) {
    FrameAvailable(frame) => self.select_frame(frame.index())
    MoreFramesRequired(start_frame~) => raise FrameNotLoaded(start_frame)
    VisibleFrameBoundary => raise NoVisibleCaller(selection.index())
  }
}

///|
fn DebugApplicationState::select_visible_callee(
  self : DebugApplicationState,
) -> StackFrameSnapshot raise DebugSessionError {
  guard self.phase is Stopped &&
    self.stable_stop is Some(stop) &&
    stop.frame is Some(selection) else {
    if self.phase is Stopped {
      raise NoFrameSelected
    }
    raise OperationNotAllowed(state=self.phase, action="select a callee frame")
  }
  match stop.stack.visible_callee(selection) {
    FrameAvailable(frame) => self.select_frame(frame.index())
    MoreFramesRequired(start_frame~) => raise FrameNotLoaded(start_frame)
    VisibleFrameBoundary => raise NoVisibleCallee(selection.index())
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
