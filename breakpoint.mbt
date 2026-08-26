///|
pub enum BreakpointStatus {
  Pending
  Verified
  Rejected(String)
} derive(Debug, Eq)

///|
pub extend BreakpointStatus with @debug.Debug::{to_repr}

///|
pub extend BreakpointStatus with Eq::{equal, not_equal}

///|
pub struct BreakpointSnapshot {
  id : Int
  source_path : String
  requested_line : Int
  actual_line : Int?
  status : BreakpointStatus
}

///|
pub fn BreakpointSnapshot::id(self : BreakpointSnapshot) -> Int {
  self.id
}

///|
pub fn BreakpointSnapshot::source_path(self : BreakpointSnapshot) -> String {
  self.source_path
}

///|
pub fn BreakpointSnapshot::requested_line(self : BreakpointSnapshot) -> Int {
  self.requested_line
}

///|
pub fn BreakpointSnapshot::actual_line(self : BreakpointSnapshot) -> Int? {
  self.actual_line
}

///|
pub fn BreakpointSnapshot::status(
  self : BreakpointSnapshot,
) -> BreakpointStatus {
  self.status
}

///|
priv struct LogicalBreakpoint {
  id : Int
  source_path : String
  requested_line : Int
}

///|
fn LogicalBreakpoint::new(
  id : Int,
  source_path : String,
  requested_line : Int,
) -> LogicalBreakpoint {
  { id, source_path, requested_line, }
}

///|
fn LogicalBreakpoint::pending_snapshot(
  self : LogicalBreakpoint,
) -> BreakpointSnapshot {
  {
    id: self.id,
    source_path: self.source_path,
    requested_line: self.requested_line,
    actual_line: None,
    status: Pending,
  }
}

///|
// The DAP id is scoped to one adapter and retained for later mutation commands.
#warnings("-unused_field")
priv struct AdapterBreakpointOutcome {
  actual_line : Int?
  dap_id : Int?
  status : BreakpointStatus
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
  self.outcomes.set(breakpoint.id, { actual_line, dap_id, status: Verified, })
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
    status: Rejected(message),
  })
}

///|
fn ExecutionBreakpointState::snapshot(
  self : ExecutionBreakpointState,
  breakpoint : LogicalBreakpoint,
) -> BreakpointSnapshot {
  guard self.outcomes.get(breakpoint.id) is Some(outcome) else {
    return breakpoint.pending_snapshot()
  }
  {
    id: breakpoint.id,
    source_path: breakpoint.source_path,
    requested_line: breakpoint.requested_line,
    actual_line: outcome.actual_line,
    status: outcome.status,
  }
}
