///|
/// Owns debugger configuration and application state for one frontend
/// session. Adapter resources and protocol state are held behind backend.
pub struct DebugSession {
  priv executable : String
  priv source_breakpoints : Array[SourceBreakpoint]
  priv function_breakpoints : Array[FunctionBreakpoint]
  priv mut next_breakpoint_id : Int
  priv backend : &DebugBackend
  priv debug_context : DebugContext
  priv application : DebugApplicationState
}

///|
/// Creates a session around an injected debugger backend.
pub fn DebugSession::new(
  executable : String,
  backend : &DebugBackend,
  debug_context? : DebugContext = DebugContext::empty(),
) -> DebugSession {
  {
    executable,
    source_breakpoints: [],
    function_breakpoints: [],
    next_breakpoint_id: 1,
    backend,
    debug_context,
    application: DebugApplicationState::new(),
  }
}

///|
pub fn DebugSession::state(self : DebugSession) -> DebugSessionState {
  self.application.phase
}

///|
pub fn DebugSession::execution_epoch(self : DebugSession) -> ExecutionEpoch? {
  self.application.execution_epoch()
}

///|
pub fn DebugSession::stop_epoch(self : DebugSession) -> StopEpoch? {
  self.application.stop_epoch()
}

///|
pub fn DebugSession::selected_thread(self : DebugSession) -> ThreadSelection? {
  self.application.selected_thread()
}

///|
pub fn DebugSession::selected_frame(self : DebugSession) -> FrameSelection? {
  self.application.selected_frame()
}

///|
pub fn DebugSession::add_source_breakpoint(
  self : DebugSession,
  source_path : String,
  line : Int,
) -> BreakpointSnapshot raise DebugSessionError {
  guard self.application.phase is Ready else {
    raise OperationNotAllowed(
      state=self.application.phase,
      action="add source breakpoint",
    )
  }
  let breakpoint = SourceBreakpoint::new(
    self.next_breakpoint_id,
    source_path,
    line,
  )
  self.next_breakpoint_id += 1
  self.source_breakpoints.push(breakpoint)
  breakpoint.pending_snapshot()
}

///|
pub fn DebugSession::add_function_breakpoint(
  self : DebugSession,
  request : FunctionBreakpointRequest,
) -> FunctionBreakpointSnapshot raise {
  guard self.application.phase is Ready else {
    raise OperationNotAllowed(
      state=self.application.phase,
      action="add function breakpoint",
    )
  }
  let current_package = self.debug_context.current_package()
  let (package_name, function_name, entry_point) = match request {
    CurrentPackageFunction(function_name) =>
      (current_package, function_name, function_name == "main")
    ImportedPackageFunction(package_alias, function_name) =>
      (
        self.debug_context.package_for_alias(package_alias),
        function_name,
        false,
      )
  }
  let physical_name = if entry_point {
    "moonbit_main"
  } else {
    @name_mangle.mangle_top_level_function_base(package_name, function_name)
  }
  let breakpoint = FunctionBreakpoint::new(
    self.next_breakpoint_id,
    request.display_name(),
    physical_name,
  )
  self.next_breakpoint_id += 1
  self.function_breakpoints.push(breakpoint)
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
  self.source_breakpoints.map(breakpoint => {
    match snapshots_by_id.get(breakpoint.id()) {
      Some(snapshot) => snapshot
      None => breakpoint.pending_snapshot()
    }
  })
}

///|
pub fn DebugSession::function_breakpoints(
  self : DebugSession,
) -> Array[FunctionBreakpointSnapshot] {
  let backend_snapshots = self.backend.function_breakpoint_snapshots()
  let snapshots_by_id : Map[Int, FunctionBreakpointSnapshot] = Map([])
  for snapshot in backend_snapshots {
    snapshots_by_id.set(snapshot.id(), snapshot)
  }
  self.function_breakpoints.map(breakpoint => {
    match snapshots_by_id.get(breakpoint.id()) {
      Some(snapshot) => snapshot
      None => breakpoint.pending_snapshot()
    }
  })
}

///|
pub fn DebugSession::last_stop_snapshot(self : DebugSession) -> StopSnapshot? {
  self.application.last_stop_snapshot()
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
  self.application.accept_outcome(outcome)
  outcome
}

///|
fn[A] DebugSession::backend_failed(
  self : DebugSession,
  message : String,
  next_state~ : DebugSessionState,
) -> A raise DebugSessionError {
  self.application.transition_without_stop(next_state)
  raise AdapterFailure(message)
}

///|
pub async fn DebugSession::run(self : DebugSession) -> RunOutcome {
  guard self.application.phase is Ready || self.application.phase is Stopped else {
    raise DebugSessionError::OperationNotAllowed(
      state=self.application.phase,
      action="run the program",
    )
  }
  self.application.begin_execution()
  let outcome = self.backend.launch(
    self.executable,
    self.source_breakpoints,
    self.function_breakpoints,
  ) catch {
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
  operation : async (ThreadSelection) -> RunOutcome,
) -> RunOutcome {
  guard self.application.phase is Stopped &&
    self.application.selected_thread() is Some(thread) else {
    raise DebugSessionError::OperationNotAllowed(
      state=self.application.phase,
      action~,
    )
  }
  self.application.begin_resume()
  let outcome = operation(thread) catch {
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
  self.resume_execution("continue execution", thread => {
    self.backend.continue_execution(thread)
  })
}

///|
pub async fn DebugSession::next(self : DebugSession) -> RunOutcome {
  self.resume_execution("step over", thread => self.backend.next(thread))
}

///|
pub async fn DebugSession::step(self : DebugSession) -> RunOutcome {
  self.resume_execution("step into", thread => self.backend.step(thread))
}

///|
pub async fn DebugSession::finish(self : DebugSession) -> RunOutcome {
  self.resume_execution("step out", thread => self.backend.finish(thread))
}

///|
pub async fn DebugSession::find_variable(
  self : DebugSession,
  name : String,
) -> VariableLookupResult {
  guard self.application.phase is Stopped &&
    self.application.selected_thread() is Some(thread) &&
    self.application.selected_frame() is Some(frame) else {
    raise DebugSessionError::OperationNotAllowed(
      state=self.application.phase,
      action="inspect a variable",
    )
  }
  self.backend.find_variable(thread, frame, name) catch {
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
  self.application.transition_without_stop(Exited)
}

///|
pub fn DebugSession::close(self : DebugSession) -> Unit {
  self.backend.close()
  self.application.transition_without_stop(Exited)
}
