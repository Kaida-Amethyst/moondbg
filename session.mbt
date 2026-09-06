///|
/// Owns debugger configuration and application state for one frontend
/// session. Adapter resources and protocol state are held behind backend.
pub struct DebugSession {
  priv executable : String
  priv mut source_breakpoints : Array[SourceBreakpoint]
  priv mut function_breakpoints : Array[FunctionBreakpoint]
  priv mut next_breakpoint_id : Int
  priv backend : &DebugBackend
  priv debug_context : DebugContext
  priv application : DebugApplicationState
  priv source_sync_results : Map[Int, BreakpointSnapshot]
  priv function_sync_results : Map[Int, FunctionBreakpointSnapshot]
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
    source_sync_results: Map([]),
    function_sync_results: Map([]),
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
/// Returns the currently loaded stack window for the stable stop.
pub fn DebugSession::stack_snapshot(self : DebugSession) -> StackSnapshot? {
  self.application.stack_snapshot()
}

///|
/// Returns the selected frame without changing the original stop snapshot.
pub fn DebugSession::selected_frame_snapshot(
  self : DebugSession,
) -> StackFrameSnapshot? {
  self.application.selected_frame_snapshot()
}

///|
/// Selects a frame by physical stack index, loading consecutive windows when
/// necessary.
pub async fn DebugSession::select_frame(
  self : DebugSession,
  physical_index : Int,
) -> StackFrameSnapshot raise DebugSessionError {
  guard physical_index >= 0 else { raise FrameNotFound(physical_index) }
  for ;; {
    guard self.application.phase is Stopped &&
      self.application.stack_snapshot() is Some(stack) else {
      raise OperationNotAllowed(
        state=self.application.phase,
        action="select a frame",
      )
    }
    if stack.is_loaded(physical_index) {
      return self.application.select_frame(physical_index)
    }
    guard !stack.is_complete() else { raise FrameNotFound(physical_index) }
    self.load_next_stack_window(stack) |> ignore
  }
}

///|
/// Selects the next visible caller without renumbering hidden frames.
pub async fn DebugSession::select_visible_caller_frame(
  self : DebugSession,
) -> StackFrameSnapshot raise DebugSessionError {
  for ;; {
    guard self.application.phase is Stopped &&
      self.application.stack_snapshot() is Some(stack) &&
      self.application.selected_frame() is Some(frame) else {
      if self.application.phase is Stopped {
        raise NoFrameSelected
      }
      raise OperationNotAllowed(
        state=self.application.phase,
        action="select a caller frame",
      )
    }
    match stack.visible_caller(frame) {
      FrameAvailable(selection) =>
        return self.application.select_frame(selection.index())
      MoreFramesRequired(_) => self.load_next_stack_window(stack) |> ignore
      VisibleFrameBoundary => raise NoVisibleCaller(frame.index())
    }
  }
}

///|
/// Selects the next visible callee without renumbering hidden frames.
pub fn DebugSession::select_visible_callee_frame(
  self : DebugSession,
) -> StackFrameSnapshot raise DebugSessionError {
  self.application.select_visible_callee()
}

///|
/// Loads the complete physical stack for the current thread. `totalFrames`
/// hints never terminate this loop; only a backend-confirmed short/empty page
/// marks the returned snapshot complete.
pub async fn DebugSession::complete_stack_snapshot(
  self : DebugSession,
) -> StackSnapshot raise DebugSessionError {
  for ;; {
    guard self.application.phase is Stopped &&
      self.application.stack_snapshot() is Some(stack) else {
      raise OperationNotAllowed(
        state=self.application.phase,
        action="load the complete stack",
      )
    }
    if stack.is_complete() {
      return stack
    }
    self.load_next_stack_window(stack) |> ignore
  }
}

///|
pub async fn DebugSession::add_source_breakpoint(
  self : DebugSession,
  source_path : String,
  line : Int,
  display_path? : String = source_path,
) -> BreakpointSnapshot {
  let phase = self.application.phase
  guard phase is Ready || phase is Stopped else {
    raise OperationNotAllowed(state=phase, action="add source breakpoint")
  }
  let breakpoint = SourceBreakpoint::new(
    self.next_breakpoint_id,
    source_path,
    line,
    display_path~,
  )
  self.next_breakpoint_id += 1
  self.source_breakpoints.push(breakpoint)
  guard phase is Stopped else { return breakpoint.pending_snapshot() }
  let result = self.synchronize_breakpoints(self.breakpoint_configuration())
  result
  .sources()
  .iter()
  .find_first(item => item.id() == breakpoint.id())
  .unwrap_or(breakpoint.pending_snapshot())
}

///|
pub async fn DebugSession::add_function_breakpoint(
  self : DebugSession,
  request : FunctionBreakpointRequest,
) -> FunctionBreakpointSnapshot {
  let phase = self.application.phase
  guard phase is Ready || phase is Stopped else {
    raise OperationNotAllowed(state=phase, action="add function breakpoint")
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
  let selector = if entry_point {
    ExactPhysicalFunction("moonbit_main")
  } else {
    MoonBitFunctionFamily(
      @name_mangle.mangle_top_level_function_base(package_name, function_name),
    )
  }
  let breakpoint = FunctionBreakpoint::new(
    self.next_breakpoint_id,
    request.display_name(),
    selector,
  )
  self.next_breakpoint_id += 1
  self.function_breakpoints.push(breakpoint)
  guard phase is Stopped else { return breakpoint.pending_snapshot() }
  let result = self.synchronize_breakpoints(self.breakpoint_configuration())
  result
  .functions()
  .iter()
  .find_first(item => item.id() == breakpoint.id())
  .unwrap_or(breakpoint.pending_snapshot())
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
  for id, snapshot in self.source_sync_results {
    snapshots_by_id.set(id, snapshot)
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
  for id, snapshot in self.function_sync_results {
    snapshots_by_id.set(id, snapshot)
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
async fn DebugSession::accept_outcome(
  self : DebugSession,
  outcome : RunOutcome,
) -> RunOutcome {
  match outcome {
    Stopped(snapshot) => {
      let thread = ThreadSelection::initial()
      let initial_window = StackWindow::initial()
      let initial = self.backend.stack_snapshot(thread, initial_window) catch {
        DebugBackendError::BackendFailure(message) =>
          self.backend_failed(message, next_state=Ready)
        error => self.backend_failed(@debug.to_string(error), next_state=Failed)
      }
      guard initial.thread() == thread && initial.loaded_start() == 0 else {
        self.backend_failed(
          "backend returned an invalid initial stack window",
          next_state=Ready,
        )
      }
      guard initial.loaded_count() <= initial_window.count() else {
        self.backend_failed(
          "backend returned more frames than the initial stack window",
          next_state=Ready,
        )
      }
      let stack = for stack = initial {
        if stack.default_selection() is Some(_) || stack.is_complete() {
          break stack
        }
        continue self.request_stack_extension(stack)
      }
      let initial_snapshot = match stack.default_selection() {
        Some(selection) =>
          match stack.frame(selection.index()) {
            Some(frame) =>
              StopSnapshot::new(
                snapshot.reason(),
                frame.display_name(),
                frame.source_path(),
                frame.line(),
                frame.column(),
              )
            None => snapshot
          }
        None => snapshot
      }
      self.application.accept_stopped(initial_snapshot, stack)
      RunOutcome::stopped(initial_snapshot)
    }
    Exited(exit_code) => {
      self.application.accept_exit()
      RunOutcome::exited(exit_code)
    }
  }
}

///|
async fn DebugSession::request_stack_extension(
  self : DebugSession,
  current : StackSnapshot,
) -> StackSnapshot raise DebugSessionError {
  let window = StackWindow::new(
    current.loaded_end(),
    StackWindow::initial().count(),
  ) catch {
    error => self.backend_failed(@debug.to_string(error), next_state=Failed)
  }
  let next = self.backend.stack_snapshot(current.thread(), window) catch {
    DebugBackendError::BackendFailure(message) =>
      self.backend_failed(message, next_state=Ready)
    error => self.backend_failed(@debug.to_string(error), next_state=Failed)
  }
  current.validate_extension(next) catch {
    error =>
      self.backend_failed(
        "backend returned an invalid stack extension: \{@debug.to_string(error)}",
        next_state=Ready,
      )
  }
  next
}

///|
async fn DebugSession::load_next_stack_window(
  self : DebugSession,
  current : StackSnapshot,
) -> StackSnapshot raise DebugSessionError {
  let next = self.request_stack_extension(current)
  self.application.update_stack(next)
  next
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
  self.source_sync_results.clear()
  self.function_sync_results.clear()
  let outcome = self.backend.launch(
    self.executable,
    self.source_breakpoints.filter(item => item.enabled()),
    self.function_breakpoints.filter(item => item.enabled()),
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
  self.source_sync_results.clear()
  self.function_sync_results.clear()
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
  path : VariablePath,
) -> VariableLookupResult {
  guard self.application.phase is Stopped &&
    self.application.selected_thread() is Some(thread) &&
    self.application.selected_frame() is Some(frame) else {
    raise DebugSessionError::OperationNotAllowed(
      state=self.application.phase,
      action="inspect a variable",
    )
  }
  self.backend.find_variable(thread, frame, path) catch {
    DebugBackendError::BackendFailure(message) =>
      self.backend_failed(message, next_state=Ready)
    error => self.backend_failed(@debug.to_string(error), next_state=Failed)
  }
}

///|
/// Returns bounded local-variable summaries for the selected physical frame.
pub async fn DebugSession::local_variables(
  self : DebugSession,
) -> LocalVariablesSnapshot {
  guard self.application.phase is Stopped &&
    self.application.selected_thread() is Some(thread) &&
    self.application.selected_frame() is Some(frame) else {
    raise DebugSessionError::OperationNotAllowed(
      state=self.application.phase,
      action="inspect local variables",
    )
  }
  self.backend.local_variables(thread, frame) catch {
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
