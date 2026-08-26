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
/// Owns the lldb-dap process, protocol dispatcher, and debugger state for one
/// moondbg REPL session.
#warnings("-unused_field")
pub struct DebugSession {
  priv dispatcher : DapDispatcher
  priv machine : DebugSessionMachine
  priv executable : String
  priv events : Array[DapEvent]
  priv breakpoints : Array[LogicalBreakpoint]
  priv mut next_breakpoint_id : Int
  priv mut capabilities : Json
  priv mut stop_reason : String
  priv mut exit_code : Int?
  priv mut last_snapshot : StopSnapshot?
}

///|
/// Starts lldb-dap without creating a target. The returned session is in
/// `Ready`; a later `run` command will begin the only execution epoch.
pub async fn[X] DebugSession::start(
  group : @async.TaskGroup[X],
  adapter : String,
  executable : String,
) -> DebugSession {
  let dispatcher = DapDispatcher::start(group, adapter)
  {
    dispatcher,
    machine: DebugSessionMachine::new(),
    executable,
    events: [],
    breakpoints: [],
    next_breakpoint_id: 1,
    capabilities: null,
    stop_reason: "stopped",
    exit_code: None,
    last_snapshot: None,
  }
}

///|
/// Returns the current stable or transitional debugger state.
pub fn DebugSession::state(self : DebugSession) -> DebugSessionState {
  self.machine.state
}

///|
fn DebugSession::accept_event(
  self : DebugSession,
  event : DapEvent,
) -> Unit raise DapSessionError {
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
  self.events.push(event)
}

///|
async fn DebugSession::wait_for_response_inner(
  self : DebugSession,
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
async fn DebugSession::request(
  self : DebugSession,
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
  guard self.machine.state is Ready else {
    raise DebugSessionError::OperationNotAllowed(
      state=self.machine.state,
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
  breakpoint.snapshot()
}

///|
pub fn DebugSession::source_breakpoints(
  self : DebugSession,
) -> Array[BreakpointSnapshot] {
  self.breakpoints.map(breakpoint => breakpoint.snapshot())
}

///|
pub fn DebugSession::last_stop_snapshot(self : DebugSession) -> StopSnapshot? {
  self.last_snapshot
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
  breakpoint : LogicalBreakpoint,
  result : Json,
) -> Unit {
  match result {
    { "verified": True, .. } =>
      breakpoint.verify(
        breakpoint_result_line(result),
        breakpoint_result_id(result),
      )
    _ => breakpoint.reject(breakpoint_result_message(result))
  }
}

///|
fn reject_breakpoints(
  breakpoints : Array[LogicalBreakpoint],
  message : String,
) -> Unit {
  for breakpoint in breakpoints {
    breakpoint.reject(message)
  }
}

///|
fn apply_breakpoint_response(
  breakpoints : Array[LogicalBreakpoint],
  response : DapResponse,
) -> Unit {
  guard response.success else {
    reject_breakpoints(breakpoints, breakpoint_response_message(response))
    return
  }
  guard response.body is { "breakpoints": Array(results), .. } else {
    reject_breakpoints(breakpoints, "lldb-dap returned no breakpoint results")
    return
  }
  for index, breakpoint in breakpoints {
    match results.get(index) {
      Some(result) => update_breakpoint_from_result(breakpoint, result)
      None => breakpoint.reject("lldb-dap omitted this breakpoint result")
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
async fn DebugSession::configure_breakpoints(self : DebugSession) -> Unit {
  let configured : Map[String, Bool] = Map([])
  for breakpoint in self.breakpoints {
    guard configured.get(breakpoint.source_path) is None else { continue }
    configured.set(breakpoint.source_path, true)
    let source_breakpoints = breakpoints_for_source(
      self.breakpoints,
      breakpoint.source_path,
    )
    let arguments = set_breakpoints_arguments(
      breakpoint.source_path,
      source_breakpoints,
    )
    let seq = self.dispatcher.send_request("setBreakpoints", arguments)
    guard self.wait_for_response(seq, "setBreakpoints") is Some(response) else {
      reject_breakpoints(
        source_breakpoints, "lldb-dap exited before verifying the breakpoints",
      )
      continue
    }
    apply_breakpoint_response(source_breakpoints, response)
  }
}

///|
async fn DebugSession::wait_for_initialized(
  self : DebugSession,
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
async fn DebugSession::wait_until_stable(self : DebugSession) -> Unit {
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
async fn DebugSession::resolve_stopped_thread(self : DebugSession) -> Int {
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
async fn DebugSession::build_stop_snapshot(self : DebugSession) -> StopSnapshot {
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
pub async fn DebugSession::run(self : DebugSession) -> RunOutcome {
  errdefer self.machine.fail("run transaction failed")
  self.machine.begin_execution()
  let initialize = self.request("initialize", {
    "adapterID": "lldb",
    "clientID": "moondbg",
    "clientName": "moondbg",
    "columnsStartAt1": true,
    "linesStartAt1": true,
    "pathFormat": "path",
    "supportsRunInTerminalRequest": false,
    "supportsVariableType": true,
  })
  self.capabilities = initialize.body
  let launch_seq = self.dispatcher.send_request("launch", {
    "program": self.executable,
    "stopOnEntry": false,
  })
  let mut launch_response = self.wait_for_initialized(launch_seq)
  if self.machine.state is Exited {
    return Exited(self.exit_code)
  }
  self.configure_breakpoints()
  self.machine.mark_running()
  self.request("configurationDone", {}) |> ignore
  if launch_response is None {
    launch_response = self.wait_for_response(launch_seq, "launch")
  }
  if launch_response is Some(response) {
    validate_response(response, "launch") |> ignore
  }
  self.wait_until_stable()
  match self.machine.state {
    Stopped => {
      let snapshot = self.build_stop_snapshot()
      self.last_snapshot = Some(snapshot)
      Stopped(snapshot)
    }
    Exited => Exited(self.exit_code)
    state =>
      raise InvalidSessionTransition(state~, action="complete run transaction")
  }
}

///|
async fn DebugSession::wait_for_response(
  self : DebugSession,
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
pub async fn DebugSession::disconnect(self : DebugSession) -> Unit {
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
pub fn DebugSession::close(self : DebugSession) -> Unit {
  self.dispatcher.close()
  self.machine.finish()
}
