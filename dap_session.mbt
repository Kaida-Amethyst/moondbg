///|
priv suberror DapSessionError {
  InvalidMessage(Json)
  RequestFailed(command~ : String, message~ : String)
  UnsupportedAdapterRequest(String)
  DuplicateResponse(Int)
  InvalidSequence(Int)
  MismatchedResponseCommand(expected~ : String, actual~ : String)
  InvalidSessionTransition(state~ : DebugSessionState, action~ : String)
} derive(Debug)

///|
pub suberror DebugSessionError {
  OperationNotAllowed(state~ : DebugSessionState, action~ : String)
  AdapterFailure(String)
} derive(Debug)

///|
pub extend DebugSessionError with @debug.Debug::{to_repr}

///|
fn validate_response(
  response : DapResponse,
  command : String,
) -> DapResponse raise DapSessionError {
  guard response.command is None || response.command == Some(command) else {
    raise MismatchedResponseCommand(
      expected=command,
      actual=response.command.unwrap(),
    )
  }
  guard response.success else {
    raise RequestFailed(
      command~,
      message=response.message.unwrap_or(
        "the adapter did not provide an error message",
      ),
    )
  }
  response
}

///|
fn validate_response_command(
  response : DapResponse,
  command : String,
) -> DapResponse raise DapSessionError {
  guard response.command is None || response.command == Some(command) else {
    raise MismatchedResponseCommand(
      expected=command,
      actual=response.command.unwrap(),
    )
  }
  response
}

///|
// Owns adapter-scoped resources and protocol state for one execution.
#warnings("-unused_field")
priv struct DebugExecution {
  dispatcher : DapDispatcher
  machine : DebugSessionMachine
  events : Array[DapEvent]
  mut capabilities : Json
  mut stop_reason : String
  mut exit_code : Int?
  mut last_snapshot : StopSnapshot?
  variable_cache : StopVariableCache
  breakpoint_state : ExecutionBreakpointState
  pending_output : Array[DebugOutput]
}

///|
/// Owns debugger configuration that remains stable for the REPL lifetime.
/// Adapter processes and DAP references are isolated inside the current
/// execution and can be replaced without changing logical breakpoint IDs.
pub struct DebugSession {
  priv executable : String
  priv breakpoints : Array[LogicalBreakpoint]
  priv mut next_breakpoint_id : Int
  priv mut preparation : @async.Task[DebugExecution]?
  priv mut preparation_error : String?
  priv mut execution : DebugExecution?
  priv mut detached_state : DebugSessionState
}

///|
async fn[X] DebugExecution::prepare(
  group : @async.TaskGroup[X],
  adapter : String,
) -> DebugExecution {
  let dispatcher = DapDispatcher::start(group, adapter)
  let execution = {
    dispatcher,
    machine: DebugSessionMachine::new(),
    events: [],
    capabilities: null,
    stop_reason: "stopped",
    exit_code: None,
    last_snapshot: None,
    variable_cache: StopVariableCache::new(),
    breakpoint_state: ExecutionBreakpointState::new(),
    pending_output: [],
  }
  errdefer execution.close()
  let initialize = execution.request("initialize", {
    "adapterID": "lldb",
    "clientID": "moondbg",
    "clientName": "moondbg",
    "columnsStartAt1": true,
    "linesStartAt1": true,
    "pathFormat": "path",
    "supportsRunInTerminalRequest": false,
    "supportsVariableType": true,
  })
  execution.capabilities = initialize.body
  execution
}

///|
/// Starts preparing lldb-dap in the background without creating a target.
/// Local REPL commands can use the returned session immediately; a later
/// `run` waits for and consumes this exact preparation result.
pub fn[X] DebugSession::start(
  group : @async.TaskGroup[X],
  adapter : String,
  executable : String,
) -> DebugSession {
  {
    executable,
    breakpoints: [],
    next_breakpoint_id: 1,
    preparation: Some(
      group.spawn(allow_failure=true, () => {
        DebugExecution::prepare(group, adapter)
      }),
    ),
    preparation_error: None,
    execution: None,
    detached_state: Ready,
  }
}

///|
/// Returns the current stable or transitional debugger state.
pub fn DebugSession::state(self : DebugSession) -> DebugSessionState {
  match self.execution {
    Some(execution) => execution.state()
    None => self.detached_state
  }
}

///|
fn DebugExecution::state(self : DebugExecution) -> DebugSessionState {
  self.machine.state
}

///|
fn DebugExecution::accept_event(
  self : DebugExecution,
  event : DapEvent,
) -> Unit raise DapSessionError {
  if output_from_event(event) is Some(output) {
    self.pending_output.push(output)
  }
  match event.name {
    "stopped" =>
      self.stop_reason = match event.body {
        { "description": String(description), .. } => description
        { "reason": String(reason), .. } => reason
        _ => "stopped"
      }
    "exited" =>
      self.exit_code = match event.body {
        { "exitCode": Number(code, ..), .. } => Some(code.to_int())
        _ => None
      }
    _ => ()
  }
  self.machine.accept_event(event)
  match event.name {
    "stopped" => {
      self.last_snapshot = None
      if self.machine.current_stop_epoch() is Some(epoch) {
        self.variable_cache.reset(epoch)
      }
    }
    "exited" | "terminated" => {
      self.last_snapshot = None
      self.variable_cache.reset(0)
    }
    _ => ()
  }
  self.events.push(event)
}

///|
async fn DebugExecution::wait_for_response_inner(
  self : DebugExecution,
  request_seq : Int,
  command : String,
  terminal_event_completes? : Bool = false,
) -> DapResponse? {
  for ;; {
    let routed = self.dispatcher.next_for_request(request_seq) catch {
      AdapterClosed => {
        if terminal_event_completes {
          self.machine.finish()
          return None
        }
        raise AdapterClosed
      }
      error => raise error
    }
    match routed {
      Matched(response) =>
        return Some(validate_response_command(response, command))
      BufferedResponse => continue
      SessionEvent(event) => {
        self.accept_event(event)
        if terminal_event_completes &&
          (event.name == "exited" || event.name == "terminated") {
          return None
        }
      }
      AdapterRequest(request) =>
        raise UnsupportedAdapterRequest(request.command)
    }
  }
}

///|
async fn DebugExecution::request(
  self : DebugExecution,
  command : String,
  arguments : Json,
) -> DapResponse {
  let seq = self.dispatcher.send_request(command, arguments)
  guard self.wait_for_response(seq, command) is Some(response) else {
    raise RequestFailed(command~, message="adapter exited before responding")
  }
  validate_response(response, command)
}

///|
pub fn DebugSession::add_source_breakpoint(
  self : DebugSession,
  source_path : String,
  line : Int,
) -> BreakpointSnapshot raise DebugSessionError {
  let state = self.state()
  guard state is Ready else {
    raise DebugSessionError::OperationNotAllowed(
      state~,
      action="add source breakpoint",
    )
  }
  let breakpoint = LogicalBreakpoint::new(
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
  match self.execution {
    Some(execution) =>
      self.breakpoints.map(breakpoint => {
        execution.breakpoint_state.snapshot(breakpoint)
      })
    None => self.breakpoints.map(LogicalBreakpoint::pending_snapshot)
  }
}

///|
pub fn DebugSession::last_stop_snapshot(self : DebugSession) -> StopSnapshot? {
  match self.execution {
    Some(execution) => execution.last_snapshot
    None => None
  }
}

///|
pub fn DebugSession::take_output(self : DebugSession) -> Array[DebugOutput] {
  guard self.execution is Some(execution) else { return [] }
  execution.take_output()
}

///|
fn DebugExecution::take_output(self : DebugExecution) -> Array[DebugOutput] {
  let output = self.pending_output.copy()
  self.pending_output.clear()
  output
}

///|
async fn DebugExecution::load_scopes(
  self : DebugExecution,
  epoch : Int,
  frame_id : Int,
) -> Array[DapScope] {
  match self.variable_cache.cached_scopes(epoch) {
    Some(scopes) => return scopes
    None => ()
  }
  let response = self.request("scopes", { "frameId": frame_id })
  guard parse_scopes(response.body) is Some(scopes) else {
    raise InvalidMessage(response.body)
  }
  for scope in scopes {
    self.machine.remember_variable_reference(scope.variables_reference)
  }
  self.variable_cache.store_scopes(epoch, scopes)
  scopes
}

///|
async fn DebugExecution::load_variables(
  self : DebugExecution,
  epoch : Int,
  reference : Int,
) -> Array[DapVariable] {
  match self.variable_cache.cached_variables(epoch, reference) {
    Some(variables) => return variables
    None => ()
  }
  let response = self.request("variables", { "variablesReference": reference })
  guard parse_variables(response.body) is Some(variables) else {
    raise InvalidMessage(response.body)
  }
  for variable in variables {
    if variable.variables_reference > 0 {
      self.machine.remember_variable_reference(variable.variables_reference)
    }
  }
  self.variable_cache.store_variables(epoch, reference, variables)
  variables
}

///|
async fn DebugExecution::find_variable_inner(
  self : DebugExecution,
  epoch : Int,
  frame_id : Int,
  name : String,
) -> VariableLookupResult {
  let scopes = self.load_scopes(epoch, frame_id)
  for scope in scopes {
    guard scope.is_relevant() else { continue }
    for variable in self.load_variables(epoch, scope.variables_reference) {
      if variable.name == name {
        return VariableFound(variable.snapshot())
      }
    }
  }
  VariableNotFound(name)
}

///|
async fn DebugExecution::find_variable(
  self : DebugExecution,
  name : String,
) -> VariableLookupResult {
  guard self.machine.state is Stopped &&
    self.machine.current_stop_epoch() is Some(epoch) &&
    self.machine.selected_frame_id() is Some(frame_id) else {
    raise DebugSessionError::OperationNotAllowed(
      state=self.machine.state,
      action="inspect a variable",
    )
  }
  self.find_variable_inner(epoch, frame_id, name) catch {
    error => raise DebugSessionError::AdapterFailure(@debug.to_string(error))
  }
}

///|
pub async fn DebugSession::find_variable(
  self : DebugSession,
  name : String,
) -> VariableLookupResult {
  guard self.execution is Some(execution) else {
    raise DebugSessionError::OperationNotAllowed(
      state=self.detached_state,
      action="inspect a variable",
    )
  }
  execution.find_variable(name)
}

///|
fn breakpoint_response_message(response : DapResponse) -> String {
  response.message.unwrap_or("lldb-dap rejected the source breakpoints")
}

///|
fn breakpoint_result_line(result : Json) -> Int? {
  match result {
    { "line": Number(line, ..), .. } => Some(line.to_int())
    _ => None
  }
}

///|
fn breakpoint_result_id(result : Json) -> Int? {
  match result {
    { "id": Number(id, ..), .. } => Some(id.to_int())
    _ => None
  }
}

///|
fn breakpoint_result_message(result : Json) -> String {
  match result {
    { "message": String(message), .. } => message
    _ => "lldb-dap could not verify this breakpoint"
  }
}

///|
fn update_breakpoint_from_result(
  breakpoint_state : ExecutionBreakpointState,
  breakpoint : LogicalBreakpoint,
  result : Json,
) -> Unit {
  match result {
    { "verified": True, .. } =>
      breakpoint_state.verify(
        breakpoint,
        breakpoint_result_line(result),
        breakpoint_result_id(result),
      )
    _ => breakpoint_state.reject(breakpoint, breakpoint_result_message(result))
  }
}

///|
fn reject_breakpoints(
  breakpoint_state : ExecutionBreakpointState,
  breakpoints : Array[LogicalBreakpoint],
  message : String,
) -> Unit {
  for breakpoint in breakpoints {
    breakpoint_state.reject(breakpoint, message)
  }
}

///|
fn apply_breakpoint_response(
  breakpoint_state : ExecutionBreakpointState,
  breakpoints : Array[LogicalBreakpoint],
  response : DapResponse,
) -> Unit {
  guard response.success else {
    reject_breakpoints(
      breakpoint_state,
      breakpoints,
      breakpoint_response_message(response),
    )
    return
  }
  guard response.body is { "breakpoints": Array(results), .. } else {
    reject_breakpoints(
      breakpoint_state, breakpoints, "lldb-dap returned no breakpoint results",
    )
    return
  }
  for index, breakpoint in breakpoints {
    match results.get(index) {
      Some(result) =>
        update_breakpoint_from_result(breakpoint_state, breakpoint, result)
      None =>
        breakpoint_state.reject(
          breakpoint, "lldb-dap omitted this breakpoint result",
        )
    }
  }
}

///|
fn breakpoints_for_source(
  breakpoints : Array[LogicalBreakpoint],
  source_path : String,
) -> Array[LogicalBreakpoint] {
  let selected : Array[LogicalBreakpoint] = []
  for breakpoint in breakpoints {
    if breakpoint.source_path == source_path {
      selected.push(breakpoint)
    }
  }
  selected
}

///|
fn set_breakpoints_arguments(
  source_path : String,
  breakpoints : Array[LogicalBreakpoint],
) -> Json {
  let dap_breakpoints : Array[Json] = []
  for breakpoint in breakpoints {
    dap_breakpoints.push({ "line": breakpoint.requested_line })
  }
  {
    "source": { "path": source_path },
    "breakpoints": dap_breakpoints,
    "sourceModified": false,
  }
}

///|
async fn DebugExecution::configure_breakpoints(
  self : DebugExecution,
  breakpoints : Array[LogicalBreakpoint],
) -> Unit {
  let configured : Map[String, Bool] = Map([])
  for breakpoint in breakpoints {
    guard configured.get(breakpoint.source_path) is None else { continue }
    configured.set(breakpoint.source_path, true)
    let source_breakpoints = breakpoints_for_source(
      breakpoints,
      breakpoint.source_path,
    )
    let arguments = set_breakpoints_arguments(
      breakpoint.source_path,
      source_breakpoints,
    )
    let seq = self.dispatcher.send_request("setBreakpoints", arguments)
    guard self.wait_for_response(seq, "setBreakpoints") is Some(response) else {
      reject_breakpoints(
        self.breakpoint_state,
        source_breakpoints,
        "lldb-dap exited before verifying the breakpoints",
      )
      continue
    }
    apply_breakpoint_response(
      self.breakpoint_state,
      source_breakpoints,
      response,
    )
  }
}

///|
async fn DebugExecution::wait_for_initialized(
  self : DebugExecution,
  launch_seq : Int,
) -> DapResponse? {
  let mut launch_response : DapResponse? = None
  while self.machine.state is Preparing {
    match self.dispatcher.next_for_request(launch_seq) {
      Matched(response) =>
        launch_response = Some(validate_response(response, "launch"))
      BufferedResponse => continue
      SessionEvent(event) => self.accept_event(event)
      AdapterRequest(request) =>
        raise UnsupportedAdapterRequest(request.command)
    }
  }
  launch_response
}

///|
async fn DebugExecution::wait_until_stable(self : DebugExecution) -> Unit {
  while self.machine.state is Running {
    let routed = self.dispatcher.next() catch {
      AdapterClosed => {
        if self.machine.state is Exited {
          return
        }
        raise AdapterClosed
      }
      error => raise error
    }
    match routed {
      Matched(_) => continue
      BufferedResponse => continue
      SessionEvent(event) => self.accept_event(event)
      AdapterRequest(request) =>
        raise UnsupportedAdapterRequest(request.command)
    }
  }
}

///|
fn first_thread_id(body : Json) -> Int? {
  guard body is { "threads": Array(threads), .. } else { return None }
  for thread in threads {
    if thread is { "id": Number(id, ..), .. } {
      return Some(id.to_int())
    }
  }
  None
}

///|
priv struct ParsedStackFrame {
  id : Int
  name : String
  source_path : String?
  line : Int?
  column : Int?
}

///|
fn stack_frame_source_path(frame : Json) -> String? {
  match frame {
    { "source": { "path": String(source_path), .. }, .. } => Some(source_path)
    _ => None
  }
}

///|
fn stack_frame_line(frame : Json) -> Int? {
  match frame {
    { "line": Number(line, ..), .. } => Some(line.to_int())
    _ => None
  }
}

///|
fn stack_frame_column(frame : Json) -> Int? {
  match frame {
    { "column": Number(column, ..), .. } => Some(column.to_int())
    _ => None
  }
}

///|
fn parse_stack_frame(frame : Json) -> ParsedStackFrame? {
  guard frame is { "id": Number(id, ..), "name": String(name), .. } else {
    return None
  }
  Some({
    id: id.to_int(),
    name,
    source_path: stack_frame_source_path(frame),
    line: stack_frame_line(frame),
    column: stack_frame_column(frame),
  })
}

///|
fn select_stack_frame(body : Json) -> ParsedStackFrame? {
  guard body is { "stackFrames": Array(frames), .. } else { return None }
  let mut first : ParsedStackFrame? = None
  for frame in frames {
    guard parse_stack_frame(frame) is Some(parsed) else { continue }
    if first is None {
      first = Some(parsed)
    }
    if parsed.source_path is Some(source_path) && source_path.has_suffix(".mbt") {
      return Some(parsed)
    }
  }
  first
}

///|
async fn DebugExecution::resolve_stopped_thread(self : DebugExecution) -> Int {
  match self.machine.selected_thread_id() {
    Some(thread_id) => thread_id
    None => {
      let response = self.request("threads", {})
      guard first_thread_id(response.body) is Some(thread_id) else {
        raise InvalidMessage(response.body)
      }
      thread_id
    }
  }
}

///|
async fn DebugExecution::build_stop_snapshot(
  self : DebugExecution,
) -> StopSnapshot {
  let thread_id = self.resolve_stopped_thread()
  let response = self.request("stackTrace", {
    "threadId": thread_id,
    "startFrame": 0,
    "levels": 20,
  })
  guard select_stack_frame(response.body) is Some(frame) else {
    raise InvalidMessage(response.body)
  }
  self.machine.select_frame(frame.id)
  StopSnapshot::new(
    self.stop_reason,
    thread_id,
    frame.id,
    frame.name,
    frame.source_path,
    frame.line,
    frame.column,
  )
}

///|
async fn DebugExecution::complete_execution(
  self : DebugExecution,
) -> RunOutcome {
  self.wait_until_stable()
  match self.machine.state {
    Stopped => {
      let snapshot = self.build_stop_snapshot()
      self.last_snapshot = Some(snapshot)
      Stopped(snapshot)
    }
    Exited => Exited(self.exit_code)
    state =>
      raise InvalidSessionTransition(
        state~,
        action="complete execution transaction",
      )
  }
}

///|
async fn DebugExecution::run_transaction(
  self : DebugExecution,
  executable : String,
  breakpoints : Array[LogicalBreakpoint],
) -> RunOutcome {
  errdefer self.machine.fail("run transaction failed")
  self.machine.begin_execution()
  let launch_seq = self.dispatcher.send_request("launch", {
    "program": executable,
    "stopOnEntry": false,
  })
  let mut launch_response = self.wait_for_initialized(launch_seq)
  if self.machine.state is Exited {
    return Exited(self.exit_code)
  }
  self.configure_breakpoints(breakpoints)
  self.machine.mark_running()
  self.request("configurationDone", {}) |> ignore
  if launch_response is None {
    launch_response = self.wait_for_response(launch_seq, "launch")
  }
  if launch_response is Some(response) {
    validate_response(response, "launch") |> ignore
  }
  self.complete_execution()
}

///|
async fn DebugExecution::run(
  self : DebugExecution,
  executable : String,
  breakpoints : Array[LogicalBreakpoint],
) -> RunOutcome {
  guard self.machine.state is Ready else {
    raise DebugSessionError::OperationNotAllowed(
      state=self.machine.state,
      action="run the program",
    )
  }
  self.run_transaction(executable, breakpoints) catch {
    error => raise DebugSessionError::AdapterFailure(@debug.to_string(error))
  }
}

///|
async fn DebugSession::prepared_execution(
  self : DebugSession,
) -> DebugExecution raise DebugSessionError {
  match self.execution {
    Some(execution) => return execution
    None => ()
  }
  match self.preparation_error {
    Some(message) => raise DebugSessionError::AdapterFailure(message)
    None => ()
  }
  guard self.preparation is Some(preparation) else {
    raise DebugSessionError::OperationNotAllowed(
      state=self.detached_state,
      action="run the program",
    )
  }
  let execution = preparation.wait() catch {
    error => {
      let message = @debug.to_string(error)
      self.preparation = None
      self.preparation_error = Some(message)
      self.detached_state = Failed
      raise DebugSessionError::AdapterFailure(message)
    }
  }
  self.preparation = None
  self.execution = Some(execution)
  execution
}

///|
pub async fn DebugSession::run(self : DebugSession) -> RunOutcome {
  let execution = self.prepared_execution()
  execution.run(self.executable, self.breakpoints)
}

///|
async fn DebugExecution::continue_transaction(
  self : DebugExecution,
  thread_id : Int,
) -> RunOutcome {
  errdefer self.machine.fail("continue transaction failed")
  self.machine.mark_resumed()
  self.last_snapshot = None
  self.variable_cache.reset(0)
  self.request("continue", { "threadId": thread_id, "singleThread": false })
  |> ignore
  self.complete_execution()
}

///|
async fn DebugExecution::continue_execution(
  self : DebugExecution,
) -> RunOutcome {
  guard self.machine.state is Stopped &&
    self.machine.selected_thread_id() is Some(thread_id) else {
    raise DebugSessionError::OperationNotAllowed(
      state=self.machine.state,
      action="continue execution",
    )
  }
  self.continue_transaction(thread_id) catch {
    error => raise DebugSessionError::AdapterFailure(@debug.to_string(error))
  }
}

///|
pub async fn DebugSession::continue_execution(
  self : DebugSession,
) -> RunOutcome {
  guard self.execution is Some(execution) else {
    raise DebugSessionError::OperationNotAllowed(
      state=self.detached_state,
      action="continue execution",
    )
  }
  execution.continue_execution()
}

///|
async fn DebugExecution::wait_for_response(
  self : DebugExecution,
  request_seq : Int,
  command : String,
  terminal_event_completes? : Bool = false,
) -> DapResponse? {
  errdefer self.machine.fail("DAP request failed")
  self.wait_for_response_inner(request_seq, command, terminal_event_completes~)
}

///|
/// Requests a graceful shutdown after a target has been created. A `Ready`
/// session owns only an idle adapter, so closing its transport is sufficient.
async fn DebugExecution::disconnect(self : DebugExecution) -> Unit {
  guard !(self.machine.state is Exited) else { return }
  if self.machine.state is Ready {
    self.machine.finish()
    return
  }
  let seq = self.dispatcher.send_request("disconnect", {
    "terminateDebuggee": true,
  })
  self.wait_for_response(seq, "disconnect", terminal_event_completes=true)
  |> ignore
  self.machine.finish()
}

///|
/// Closes the DAP pipes and cancels the adapter process if it is still alive.
fn DebugExecution::close(self : DebugExecution) -> Unit {
  self.dispatcher.close()
  self.machine.finish()
}

///|
/// Requests a graceful shutdown of the current execution.
pub async fn DebugSession::disconnect(self : DebugSession) -> Unit {
  guard self.execution is Some(execution) else { return }
  execution.disconnect()
  self.detached_state = execution.state()
}

///|
/// Closes the current execution and detaches all adapter-scoped resources.
pub fn DebugSession::close(self : DebugSession) -> Unit {
  match self.execution {
    Some(execution) => {
      execution.close()
      self.detached_state = execution.state()
      self.execution = None
    }
    None => ()
  }
  guard self.preparation is Some(preparation) else { return }
  let completed = preparation.try_wait() catch { _ => None }
  preparation.cancel()
  if completed is Some(execution) {
    execution.close()
    self.detached_state = execution.state()
  }
  self.preparation = None
}
