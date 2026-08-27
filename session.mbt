///|
/// User-visible debugger state owned by DebugSession.
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
/// Owns debugger configuration and application state for one frontend
/// session. Adapter resources and protocol state are held behind backend.
pub struct DebugSession {
  priv executable : String
  priv breakpoints : Array[SourceBreakpoint]
  priv mut next_breakpoint_id : Int
  priv backend : &DebugBackend
  priv mut state : DebugSessionState
  priv mut last_stop : StopSnapshot?
}

///|
/// Creates a session around an injected debugger backend.
pub fn DebugSession::new(
  executable : String,
  backend : &DebugBackend,
) -> DebugSession {
  {
    executable,
    breakpoints: [],
    next_breakpoint_id: 1,
    backend,
    state: Ready,
    last_stop: None,
  }
}

///|
pub fn DebugSession::state(self : DebugSession) -> DebugSessionState {
  self.state
}

///|
pub fn DebugSession::add_source_breakpoint(
  self : DebugSession,
  source_path : String,
  line : Int,
) -> BreakpointSnapshot raise DebugSessionError {
  guard self.state is Ready else {
    raise OperationNotAllowed(state=self.state, action="add source breakpoint")
  }
  let breakpoint = SourceBreakpoint::new(
    self.next_breakpoint_id,
    source_path,
    line,
  )
  self.next_breakpoint_id += 1
  self.breakpoints.push(breakpoint)
  breakpoint.pending_snapshot()
}

///|
pub fn DebugSession::source_breakpoints(
  self : DebugSession,
) -> Array[BreakpointSnapshot] {
  let backend_snapshots = self.backend.breakpoint_snapshots()
  let snapshots_by_id : Map[Int, BreakpointSnapshot] = Map([])
  for snapshot in backend_snapshots {
    snapshots_by_id.set(snapshot.id(), snapshot)
  }
  self.breakpoints.map(breakpoint => {
    match snapshots_by_id.get(breakpoint.id()) {
      Some(snapshot) => snapshot
      None => breakpoint.pending_snapshot()
    }
  })
}

///|
pub fn DebugSession::last_stop_snapshot(self : DebugSession) -> StopSnapshot? {
  self.last_stop
}

///|
pub fn DebugSession::take_output(self : DebugSession) -> Array[DebugOutput] {
  self.backend.take_output()
}

///|
fn DebugSession::accept_outcome(
  self : DebugSession,
  outcome : RunOutcome,
) -> RunOutcome {
  match outcome {
    Stopped(snapshot) => {
      self.state = Stopped
      self.last_stop = Some(snapshot)
    }
    Exited(_) => {
      self.state = Ready
      self.last_stop = None
    }
  }
  outcome
}

///|
fn[A] DebugSession::backend_failed(
  self : DebugSession,
  message : String,
  next_state~ : DebugSessionState,
) -> A raise DebugSessionError {
  self.state = next_state
  self.last_stop = None
  raise AdapterFailure(message)
}

///|
pub async fn DebugSession::run(self : DebugSession) -> RunOutcome {
  guard self.state is Ready || self.state is Stopped else {
    raise DebugSessionError::OperationNotAllowed(
      state=self.state,
      action="run the program",
    )
  }
  self.state = Running
  self.last_stop = None
  let outcome = self.backend.launch(self.executable, self.breakpoints) catch {
    DebugBackendError::BackendFailure(message) =>
      self.backend_failed(message, next_state=Ready)
    error => self.backend_failed(@debug.to_string(error), next_state=Failed)
  }
  self.accept_outcome(outcome)
}

///|
async fn DebugSession::resume_execution(
  self : DebugSession,
  action : String,
  operation : async () -> RunOutcome,
) -> RunOutcome {
  guard self.state is Stopped else {
    raise DebugSessionError::OperationNotAllowed(state=self.state, action~)
  }
  self.state = Running
  self.last_stop = None
  let outcome = operation() catch {
    DebugBackendError::BackendFailure(message) =>
      self.backend_failed(message, next_state=Ready)
    error => self.backend_failed(@debug.to_string(error), next_state=Failed)
  }
  self.accept_outcome(outcome)
}

///|
pub async fn DebugSession::continue_execution(
  self : DebugSession,
) -> RunOutcome {
  self.resume_execution("continue execution", () => {
    self.backend.continue_execution()
  })
}

///|
pub async fn DebugSession::next(self : DebugSession) -> RunOutcome {
  self.resume_execution("step over", () => self.backend.next())
}

///|
pub async fn DebugSession::step(self : DebugSession) -> RunOutcome {
  self.resume_execution("step into", () => self.backend.step())
}

///|
pub async fn DebugSession::finish(self : DebugSession) -> RunOutcome {
  self.resume_execution("step out", () => self.backend.finish())
}

///|
pub async fn DebugSession::find_variable(
  self : DebugSession,
  name : String,
) -> VariableLookupResult {
  guard self.state is Stopped else {
    raise DebugSessionError::OperationNotAllowed(
      state=self.state,
      action="inspect a variable",
    )
  }
  self.backend.find_variable(name) catch {
    DebugBackendError::BackendFailure(message) =>
      self.backend_failed(message, next_state=Ready)
    error => self.backend_failed(@debug.to_string(error), next_state=Failed)
  }
}

///|
pub async fn DebugSession::disconnect(self : DebugSession) -> Unit {
  self.backend.disconnect() catch {
    _ => ()
  }
  self.state = Exited
  self.last_stop = None
}

///|
pub fn DebugSession::close(self : DebugSession) -> Unit {
  self.backend.close()
  self.state = Exited
  self.last_stop = None
}
