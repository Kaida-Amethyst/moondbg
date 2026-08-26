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
// The DAP id is retained for later breakpoint mutation commands.
#warnings("-unused_field")
priv struct LogicalBreakpoint {
  id : Int
  source_path : String
  requested_line : Int
  mut actual_line : Int?
  mut dap_id : Int?
  mut status : BreakpointStatus
}

///|
fn LogicalBreakpoint::new(
  id : Int,
  source_path : String,
  requested_line : Int,
) -> LogicalBreakpoint {
  {
    id,
    source_path,
    requested_line,
    actual_line: None,
    dap_id: None,
    status: Pending,
  }
}

///|
fn LogicalBreakpoint::snapshot(self : LogicalBreakpoint) -> BreakpointSnapshot {
  {
    id: self.id,
    source_path: self.source_path,
    requested_line: self.requested_line,
    actual_line: self.actual_line,
    status: self.status,
  }
}

///|
fn LogicalBreakpoint::verify(
  self : LogicalBreakpoint,
  actual_line : Int?,
  dap_id : Int?,
) -> Unit {
  self.actual_line = actual_line
  self.dap_id = dap_id
  self.status = Verified
}

///|
fn LogicalBreakpoint::reject(
  self : LogicalBreakpoint,
  message : String,
) -> Unit {
  self.actual_line = None
  self.dap_id = None
  self.status = Rejected(message)
}
