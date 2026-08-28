///|
priv struct LogicalSourceBreakpoint {
  id : Int
  source_path : String
  requested_line : Int
}

///|
fn LogicalSourceBreakpoint::from_domain(
  breakpoint : @moondbg.SourceBreakpoint,
) -> LogicalSourceBreakpoint {
  {
    id: breakpoint.id(),
    source_path: breakpoint.source_path(),
    requested_line: breakpoint.requested_line(),
  }
}

///|
fn LogicalSourceBreakpoint::pending_snapshot(
  self : LogicalSourceBreakpoint,
) -> @moondbg.BreakpointSnapshot {
  @moondbg.BreakpointSnapshot::pending(
    self.id,
    self.source_path,
    self.requested_line,
  )
}

///|
priv struct LogicalFunctionBreakpoint {
  id : Int
  display_name : String
  physical_name : String
}

///|
fn LogicalFunctionBreakpoint::from_domain(
  breakpoint : @moondbg.FunctionBreakpoint,
) -> LogicalFunctionBreakpoint {
  {
    id: breakpoint.id(),
    display_name: breakpoint.display_name(),
    physical_name: breakpoint.physical_name(),
  }
}

///|
fn LogicalFunctionBreakpoint::pending_snapshot(
  self : LogicalFunctionBreakpoint,
) -> @moondbg.FunctionBreakpointSnapshot {
  @moondbg.FunctionBreakpointSnapshot::pending(self.id, self.display_name)
}

///|
// The DAP id is scoped to one adapter and retained for later mutation commands.
#warnings("-unused_field")
priv struct AdapterBreakpointOutcome {
  actual_line : Int?
  dap_id : Int?
  status : AdapterBreakpointStatus
}

///|
priv enum AdapterBreakpointStatus {
  AdapterVerified
  AdapterRejected(String)
}

///|
priv struct ExecutionBreakpointState {
  outcomes : Map[Int, AdapterBreakpointOutcome]
}

///|
fn ExecutionBreakpointState::new() -> ExecutionBreakpointState {
  { outcomes: Map([]), }
}

///|
fn ExecutionBreakpointState::verify(
  self : ExecutionBreakpointState,
  breakpoint_id : Int,
  actual_line : Int?,
  dap_id : Int?,
) -> Unit {
  self.outcomes.set(breakpoint_id, {
    actual_line,
    dap_id,
    status: AdapterVerified,
  })
}

///|
fn ExecutionBreakpointState::reject(
  self : ExecutionBreakpointState,
  breakpoint_id : Int,
  message : String,
) -> Unit {
  self.outcomes.set(breakpoint_id, {
    actual_line: None,
    dap_id: None,
    status: AdapterRejected(message),
  })
}

///|
fn ExecutionBreakpointState::source_snapshot(
  self : ExecutionBreakpointState,
  breakpoint : LogicalSourceBreakpoint,
) -> @moondbg.BreakpointSnapshot {
  guard self.outcomes.get(breakpoint.id) is Some(outcome) else {
    return breakpoint.pending_snapshot()
  }
  match outcome.status {
    AdapterVerified =>
      @moondbg.BreakpointSnapshot::verified(
        breakpoint.id,
        breakpoint.source_path,
        breakpoint.requested_line,
        outcome.actual_line,
      )
    AdapterRejected(message) =>
      @moondbg.BreakpointSnapshot::rejected(
        breakpoint.id,
        breakpoint.source_path,
        breakpoint.requested_line,
        message,
      )
  }
}

///|
fn ExecutionBreakpointState::function_snapshot(
  self : ExecutionBreakpointState,
  breakpoint : LogicalFunctionBreakpoint,
) -> @moondbg.FunctionBreakpointSnapshot {
  guard self.outcomes.get(breakpoint.id) is Some(outcome) else {
    return breakpoint.pending_snapshot()
  }
  match outcome.status {
    AdapterVerified =>
      @moondbg.FunctionBreakpointSnapshot::verified(
        breakpoint.id,
        breakpoint.display_name,
      )
    AdapterRejected(message) =>
      @moondbg.FunctionBreakpointSnapshot::rejected(
        breakpoint.id,
        breakpoint.display_name,
        message,
      )
  }
}

///|
fn LldbDapSession::add_source_breakpoint(
  self : LldbDapSession,
  source_breakpoint : @moondbg.SourceBreakpoint,
) -> @moondbg.BreakpointSnapshot raise LldbDapBackendError {
  let state = self.state()
  guard state is Ready else {
    raise LldbDapBackendError::OperationNotAllowed(
      state~,
      action="add source breakpoint",
    )
  }
  let breakpoint = LogicalSourceBreakpoint::from_domain(source_breakpoint)
  self.source_breakpoints.push(breakpoint)
  breakpoint.pending_snapshot()
}

///|
fn LldbDapSession::source_breakpoints(
  self : LldbDapSession,
) -> Array[@moondbg.BreakpointSnapshot] {
  match self.execution {
    Some(execution) =>
      self.source_breakpoints.map(breakpoint => {
        execution.breakpoint_state.source_snapshot(breakpoint)
      })
    None =>
      self.source_breakpoints.map(breakpoint => {
        match self.last_source_breakpoint_snapshots.get(breakpoint.id) {
          Some(snapshot) => snapshot
          None => breakpoint.pending_snapshot()
        }
      })
  }
}

///|
fn LldbDapSession::add_function_breakpoint(
  self : LldbDapSession,
  function_breakpoint : @moondbg.FunctionBreakpoint,
) -> @moondbg.FunctionBreakpointSnapshot raise LldbDapBackendError {
  let state = self.state()
  guard state is Ready else {
    raise LldbDapBackendError::OperationNotAllowed(
      state~,
      action="add function breakpoint",
    )
  }
  let breakpoint = LogicalFunctionBreakpoint::from_domain(function_breakpoint)
  self.function_breakpoints.push(breakpoint)
  breakpoint.pending_snapshot()
}

///|
fn LldbDapSession::function_breakpoints(
  self : LldbDapSession,
) -> Array[@moondbg.FunctionBreakpointSnapshot] {
  match self.execution {
    Some(execution) =>
      self.function_breakpoints.map(breakpoint => {
        execution.breakpoint_state.function_snapshot(breakpoint)
      })
    None =>
      self.function_breakpoints.map(breakpoint => {
        match self.last_function_breakpoint_snapshots.get(breakpoint.id) {
          Some(snapshot) => snapshot
          None => breakpoint.pending_snapshot()
        }
      })
  }
}

///|
fn breakpoint_response_message(response : @dap.DapResponse) -> String {
  response.message().unwrap_or("lldb-dap rejected the source breakpoints")
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
  breakpoint : LogicalSourceBreakpoint,
  result : Json,
) -> Unit {
  match result {
    { "verified": True, .. } =>
      breakpoint_state.verify(
        breakpoint.id,
        breakpoint_result_line(result),
        breakpoint_result_id(result),
      )
    _ =>
      breakpoint_state.reject(breakpoint.id, breakpoint_result_message(result))
  }
}

///|
fn reject_breakpoints(
  breakpoint_state : ExecutionBreakpointState,
  breakpoints : Array[LogicalSourceBreakpoint],
  message : String,
) -> Unit {
  for breakpoint in breakpoints {
    breakpoint_state.reject(breakpoint.id, message)
  }
}

///|
fn apply_breakpoint_response(
  breakpoint_state : ExecutionBreakpointState,
  breakpoints : Array[LogicalSourceBreakpoint],
  response : @dap.DapResponse,
) -> Unit {
  guard response.success() else {
    reject_breakpoints(
      breakpoint_state,
      breakpoints,
      breakpoint_response_message(response),
    )
    return
  }
  guard response.body() is { "breakpoints": Array(results), .. } else {
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
          breakpoint.id,
          "lldb-dap omitted this breakpoint result",
        )
    }
  }
}

///|
fn breakpoints_for_source(
  breakpoints : Array[LogicalSourceBreakpoint],
  source_path : String,
) -> Array[LogicalSourceBreakpoint] {
  let selected : Array[LogicalSourceBreakpoint] = []
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
  breakpoints : Array[LogicalSourceBreakpoint],
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
  breakpoints : Array[LogicalSourceBreakpoint],
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
fn set_function_breakpoints_arguments(
  breakpoints : Array[LogicalFunctionBreakpoint],
) -> Json {
  let dap_breakpoints : Array[Json] = []
  for breakpoint in breakpoints {
    dap_breakpoints.push({ "name": breakpoint.physical_name })
  }
  { "breakpoints": dap_breakpoints }
}

///|
fn reject_function_breakpoints(
  breakpoint_state : ExecutionBreakpointState,
  breakpoints : Array[LogicalFunctionBreakpoint],
  message : String,
) -> Unit {
  for breakpoint in breakpoints {
    breakpoint_state.reject(breakpoint.id, message)
  }
}

///|
fn apply_function_breakpoint_response(
  breakpoint_state : ExecutionBreakpointState,
  breakpoints : Array[LogicalFunctionBreakpoint],
  response : @dap.DapResponse,
) -> Unit {
  guard response.success() else {
    reject_function_breakpoints(
      breakpoint_state,
      breakpoints,
      response.message().unwrap_or("lldb-dap rejected the function breakpoints"),
    )
    return
  }
  guard response.body() is { "breakpoints": Array(results), .. } else {
    reject_function_breakpoints(
      breakpoint_state, breakpoints, "lldb-dap returned no function breakpoint results",
    )
    return
  }
  for index, breakpoint in breakpoints {
    match results.get(index) {
      Some({ "verified": True, .. } as result) =>
        breakpoint_state.verify(
          breakpoint.id,
          breakpoint_result_line(result),
          breakpoint_result_id(result),
        )
      Some(result) =>
        breakpoint_state.reject(
          breakpoint.id,
          breakpoint_result_message(result),
        )
      None =>
        breakpoint_state.reject(
          breakpoint.id,
          "lldb-dap omitted this function breakpoint result",
        )
    }
  }
}

///|
async fn DebugExecution::configure_function_breakpoints(
  self : DebugExecution,
  breakpoints : Array[LogicalFunctionBreakpoint],
) -> Unit {
  guard breakpoints is [_, ..] else { return }
  let seq = self.dispatcher.send_request(
    "setFunctionBreakpoints",
    set_function_breakpoints_arguments(breakpoints),
  )
  guard self.wait_for_response(seq, "setFunctionBreakpoints") is Some(response) else {
    reject_function_breakpoints(
      self.breakpoint_state,
      breakpoints,
      "lldb-dap exited before verifying the function breakpoints",
    )
    return
  }
  apply_function_breakpoint_response(
    self.breakpoint_state,
    breakpoints,
    response,
  )
}
