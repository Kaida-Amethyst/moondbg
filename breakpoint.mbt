///|
/// A source breakpoint configured by the application layer.
///
/// Its id is stable for the lifetime of a DebugSession. Backend-specific
/// breakpoint identifiers must not be stored in this value.
pub struct SourceBreakpoint {
  priv id : Int
  priv source_path : String
  priv requested_line : Int
  priv display_path : String
  priv enabled : Bool
}

///|
fn SourceBreakpoint::new(
  id : Int,
  source_path : String,
  requested_line : Int,
  display_path? : String = source_path,
) -> SourceBreakpoint {
  { id, source_path, requested_line, display_path, enabled: true, }
}

///|
pub fn SourceBreakpoint::enabled(self : SourceBreakpoint) -> Bool {
  self.enabled
}

///|
pub fn SourceBreakpoint::display_path(self : SourceBreakpoint) -> String {
  self.display_path
}

///|
fn SourceBreakpoint::with_enabled(
  self : SourceBreakpoint,
  enabled : Bool,
) -> SourceBreakpoint {
  { ..self, enabled, }
}

///|
pub fn SourceBreakpoint::id(self : SourceBreakpoint) -> Int {
  self.id
}

///|
pub fn SourceBreakpoint::source_path(self : SourceBreakpoint) -> String {
  self.source_path
}

///|
pub fn SourceBreakpoint::requested_line(self : SourceBreakpoint) -> Int {
  self.requested_line
}

///|
fn SourceBreakpoint::pending_snapshot(
  self : SourceBreakpoint,
) -> BreakpointSnapshot {
  BreakpointSnapshot::pending(self.id, self.source_path, self.requested_line)
}

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
  priv id : Int
  priv source_path : String
  priv requested_line : Int
  priv actual_line : Int?
  priv status : BreakpointStatus
}

///|
/// Creates a pending application-level breakpoint result.
pub fn BreakpointSnapshot::pending(
  id : Int,
  source_path : String,
  requested_line : Int,
) -> BreakpointSnapshot {
  { id, source_path, requested_line, actual_line: None, status: Pending, }
}

///|
/// Creates a verified application-level breakpoint result.
pub fn BreakpointSnapshot::verified(
  id : Int,
  source_path : String,
  requested_line : Int,
  actual_line : Int?,
) -> BreakpointSnapshot {
  { id, source_path, requested_line, actual_line, status: Verified, }
}

///|
/// Creates a rejected application-level breakpoint result.
pub fn BreakpointSnapshot::rejected(
  id : Int,
  source_path : String,
  requested_line : Int,
  message : String,
) -> BreakpointSnapshot {
  {
    id,
    source_path,
    requested_line,
    actual_line: None,
    status: Rejected(message),
  }
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
