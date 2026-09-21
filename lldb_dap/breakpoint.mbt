///|
priv struct LogicalSourceBreakpoint {
  id : Int
  source_path : String
  requested_line : Int
  condition : @expression.IntCondition?
} derive(Eq)

///|
fn LogicalSourceBreakpoint::from_domain(
  breakpoint : @debugger.SourceBreakpoint,
) -> LogicalSourceBreakpoint {
  {
    id: breakpoint.id(),
    source_path: breakpoint.source_path(),
    requested_line: breakpoint.requested_line(),
    condition: breakpoint.condition(),
  }
}

///|
fn LogicalSourceBreakpoint::pending_snapshot(
  self : LogicalSourceBreakpoint,
) -> @debugger.BreakpointSnapshot {
  @debugger.BreakpointSnapshot::pending(
    self.id,
    self.source_path,
    self.requested_line,
  )
}

///|
priv struct LogicalFunctionBreakpoint {
  id : Int
  display_name : String
  selector : @debugger.FunctionBreakpointSelector
} derive(Eq)

///|
fn LogicalFunctionBreakpoint::from_domain(
  breakpoint : @debugger.FunctionBreakpoint,
) -> LogicalFunctionBreakpoint {
  {
    id: breakpoint.id(),
    display_name: breakpoint.display_name(),
    selector: breakpoint.selector(),
  }
}

///|
fn LogicalFunctionBreakpoint::pending_snapshot(
  self : LogicalFunctionBreakpoint,
) -> @debugger.FunctionBreakpointSnapshot {
  @debugger.FunctionBreakpointSnapshot::pending(self.id, self.display_name)
}

///|
// The DAP id is scoped to one adapter and retained for later mutation commands.
#warnings("-unused_field")
priv struct AdapterBreakpointOutcome {
  actual_line : Int?
  dap_id : Int?
  location_count : Int?
  status : AdapterBreakpointStatus
  locations : Array[@debugger.BreakpointLocation]
}

///|
priv enum AdapterBreakpointStatus {
  AdapterVerified
  AdapterRejected(String)
}

///|
priv struct ExecutionBreakpointState {
  outcomes : Map[Int, AdapterBreakpointOutcome]
  families : Map[Int, FamilyHandle]
}

///|
fn ExecutionBreakpointState::new() -> ExecutionBreakpointState {
  { outcomes: Map([]), families: Map([]), }
}

///|
fn ExecutionBreakpointState::source_snapshot(
  self : ExecutionBreakpointState,
  breakpoint : LogicalSourceBreakpoint,
) -> @debugger.BreakpointSnapshot {
  guard self.outcomes.get(breakpoint.id) is Some(outcome) else {
    return breakpoint.pending_snapshot()
  }
  let snapshot = match outcome.status {
    AdapterVerified =>
      @debugger.BreakpointSnapshot::verified(
        breakpoint.id,
        breakpoint.source_path,
        breakpoint.requested_line,
        outcome.actual_line,
      )
    AdapterRejected(message) =>
      @debugger.BreakpointSnapshot::rejected(
        breakpoint.id,
        breakpoint.source_path,
        breakpoint.requested_line,
        message,
      )
  }
  snapshot.with_locations(outcome.locations)
}

///|
fn ExecutionBreakpointState::function_snapshot(
  self : ExecutionBreakpointState,
  breakpoint : LogicalFunctionBreakpoint,
) -> @debugger.FunctionBreakpointSnapshot {
  guard self.outcomes.get(breakpoint.id) is Some(outcome) else {
    return breakpoint.pending_snapshot()
  }
  let snapshot = match outcome.status {
    AdapterVerified =>
      @debugger.FunctionBreakpointSnapshot::verified(
        breakpoint.id,
        breakpoint.display_name,
        location_count=outcome.location_count,
      )
    AdapterRejected(message) =>
      @debugger.FunctionBreakpointSnapshot::rejected(
        breakpoint.id,
        breakpoint.display_name,
        message,
        location_count=outcome.location_count,
      )
  }
  snapshot.with_locations(outcome.locations)
}

///|
fn LldbDapSession::source_breakpoints(
  self : LldbDapSession,
) -> Array[@debugger.BreakpointSnapshot] {
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
fn LldbDapSession::function_breakpoints(
  self : LldbDapSession,
) -> Array[@debugger.FunctionBreakpointSnapshot] {
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
fn apply_breakpoint_response(
  breakpoint_state : ExecutionBreakpointState,
  breakpoints : Array[LogicalSourceBreakpoint],
  response : @dap.DapResponse,
) -> Unit raise {
  let outcomes = parse_breakpoint_replacement(response, breakpoints.length())
  for index, breakpoint in breakpoints {
    breakpoint_state.outcomes.set(breakpoint.id, outcomes[index])
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
    self.configure_source_breakpoints(breakpoints, breakpoint.source_path)
  }
}

///|
async fn DebugExecution::configure_source_breakpoints(
  self : DebugExecution,
  breakpoints : Array[LogicalSourceBreakpoint],
  source_path : String,
) -> Unit {
  let source_breakpoints = breakpoints_for_source(breakpoints, source_path)
  let arguments = set_breakpoints_arguments(source_path, source_breakpoints)
  let seq = self.dispatcher.send_request("setBreakpoints", arguments)
  guard self.wait_for_response(seq, "setBreakpoints") is Some(response) else {
    raise @debugger.BreakpointSyncError::BreakpointSyncUncertain(
      "lldb-dap exited before confirming the source replacement",
    )
  }
  apply_breakpoint_response(self.breakpoint_state, source_breakpoints, response)
  let bindings : Array[(Int, @expression.IntCondition?)] = []
  for point in source_breakpoints {
    if self.breakpoint_state.outcomes.get(point.id)
      is Some({ dap_id: Some(id), .. }) {
      bindings.push((id, point.condition))
    }
  }
  self.conditions.replace(source_path, bindings)
}

///|
fn set_function_breakpoints_arguments(
  breakpoints : Array[LogicalFunctionBreakpoint],
) -> Json {
  let dap_breakpoints : Array[Json] = []
  for breakpoint in breakpoints {
    guard breakpoint.selector is @debugger.ExactPhysicalFunction(name) else {
      continue
    }
    dap_breakpoints.push({ "name": name })
  }
  { "breakpoints": dap_breakpoints }
}

///|
fn exact_function_breakpoints(
  breakpoints : Array[LogicalFunctionBreakpoint],
) -> Array[LogicalFunctionBreakpoint] {
  breakpoints.filter(breakpoint => {
    breakpoint.selector is @debugger.ExactPhysicalFunction(_)
  })
}

///|
fn family_function_breakpoints(
  breakpoints : Array[LogicalFunctionBreakpoint],
) -> Array[LogicalFunctionBreakpoint] {
  breakpoints.filter(breakpoint => {
    breakpoint.selector is @debugger.MoonBitFunctionFamily(_)
  })
}

///|
fn apply_function_breakpoint_response(
  breakpoint_state : ExecutionBreakpointState,
  breakpoints : Array[LogicalFunctionBreakpoint],
  response : @dap.DapResponse,
) -> Unit raise {
  let outcomes = parse_breakpoint_replacement(response, breakpoints.length())
  for index, breakpoint in breakpoints {
    breakpoint_state.outcomes.set(breakpoint.id, outcomes[index])
  }
}

///|
async fn DebugExecution::configure_exact_function_breakpoints(
  self : DebugExecution,
  breakpoints : Array[LogicalFunctionBreakpoint],
) -> Unit {
  let seq = self.dispatcher.send_request(
    "setFunctionBreakpoints",
    set_function_breakpoints_arguments(breakpoints),
  )
  guard self.wait_for_response(seq, "setFunctionBreakpoints") is Some(response) else {
    raise @debugger.BreakpointSyncError::BreakpointSyncUncertain(
      "lldb-dap exited before confirming the function replacement",
    )
  }
  apply_function_breakpoint_response(
    self.breakpoint_state,
    breakpoints,
    response,
  )
}

///|
fn function_family_regex(base : StringView) -> String {
  "^\{base}($|G|H)"
}

///|
fn function_family_breakpoint_command(base : StringView) -> String {
  "breakpoint set --func-regex '\{function_family_regex(base)}'"
}

///|
priv struct LldbCreatedBreakpoint {
  id : Int
  location_count : Int
}

///|
fn LldbCreatedBreakpoint::parse(result : StringView) -> LldbCreatedBreakpoint? {
  guard result.trim().strip_prefix("Breakpoint ") is Some(description) &&
    description.split_once(":") is Some((id_text, detail)) else {
    return None
  }
  let id = Some(@string.parse_int(id_text, base=10)) catch { _ => None }
  guard id is Some(id) && id > 0 else { return None }
  guard detail.trim().split("\n").next() is Some(detail) else { return None }
  if detail == "no locations (pending)." {
    return Some({ id, location_count: 0, })
  }
  let location_count = match detail.strip_suffix(" locations.") {
    Some(count_text) =>
      Some(@string.parse_int(count_text, base=10)) catch {
        _ => None
      }
    None =>
      if detail.has_prefix("where = ") &&
        detail.split_once(", address = ") is Some((_, address)) &&
        family_address_value(address) is Some(_) {
        Some(1)
      } else {
        None
      }
  }
  guard location_count is Some(location_count) && location_count > 0 else {
    return None
  }
  Some({ id, location_count, })
}

///|
fn lldb_command_result(response : @dap.DapResponse) -> String? {
  guard response.success() &&
    response.body() is { "result": String(result), .. } else {
    return None
  }
  Some(result)
}

///|
async fn DebugExecution::configure_family_function_breakpoint(
  self : DebugExecution,
  breakpoint : LogicalFunctionBreakpoint,
) -> Unit {
  guard breakpoint.selector is @debugger.MoonBitFunctionFamily(_) else {
    return
  }
  let created = self.function_driver().install(breakpoint.selector)
  let handle = FamilyHandle::{
    id: LldbBreakpointId(created.id),
    enabled: true,
  }
  self.breakpoint_state.families.set(breakpoint.id, handle)
  self.refresh_family_details(
    breakpoint.id,
    handle.id,
    created_count=Some(created.location_count),
  )
}

///|
async fn DebugExecution::configure_function_breakpoints(
  self : DebugExecution,
  breakpoints : Array[LogicalFunctionBreakpoint],
) -> Unit {
  let exact = exact_function_breakpoints(breakpoints)
  if !exact.is_empty() {
    self.configure_exact_function_breakpoints(exact)
  }
  for breakpoint in family_function_breakpoints(breakpoints) {
    self.configure_family_function_breakpoint(breakpoint)
  }
}
