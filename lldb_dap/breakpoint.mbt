///|
priv struct LogicalBreakpoint {
  id : Int
  source_path : String
  requested_line : Int
}

///|
fn LogicalBreakpoint::from_domain(
  breakpoint : @moondbg.SourceBreakpoint,
) -> LogicalBreakpoint {
  {
    id: breakpoint.id(),
    source_path: breakpoint.source_path(),
    requested_line: breakpoint.requested_line(),
  }
}

///|
fn LogicalBreakpoint::pending_snapshot(
  self : LogicalBreakpoint,
) -> @moondbg.BreakpointSnapshot {
  @moondbg.BreakpointSnapshot::pending(
    self.id,
    self.source_path,
    self.requested_line,
  )
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
  breakpoint : LogicalBreakpoint,
  actual_line : Int?,
  dap_id : Int?,
) -> Unit {
  self.outcomes.set(breakpoint.id, {
    actual_line,
    dap_id,
    status: AdapterVerified,
  })
}

///|
fn ExecutionBreakpointState::reject(
  self : ExecutionBreakpointState,
  breakpoint : LogicalBreakpoint,
  message : String,
) -> Unit {
  self.outcomes.set(breakpoint.id, {
    actual_line: None,
    dap_id: None,
    status: AdapterRejected(message),
  })
}

///|
fn ExecutionBreakpointState::snapshot(
  self : ExecutionBreakpointState,
  breakpoint : LogicalBreakpoint,
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
  let breakpoint = LogicalBreakpoint::from_domain(source_breakpoint)
  self.breakpoints.push(breakpoint)
  breakpoint.pending_snapshot()
}

///|
fn LldbDapSession::source_breakpoints(
  self : LldbDapSession,
) -> Array[@moondbg.BreakpointSnapshot] {
  match self.execution {
    Some(execution) =>
      self.breakpoints.map(breakpoint => {
        execution.breakpoint_state.snapshot(breakpoint)
      })
    None =>
      self.breakpoints.map(breakpoint => {
        match self.last_breakpoint_snapshots.get(breakpoint.id) {
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
