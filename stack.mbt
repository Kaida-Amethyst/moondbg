///|
/// A zero-based logical thread selection inside the current stable stop.
/// Backend-specific thread identifiers never appear in this value.
pub struct ThreadSelection {
  priv index : Int
} derive(Debug, Eq)

///|
pub extend ThreadSelection with @debug.Debug::{to_repr}

///|
pub extend ThreadSelection with Eq::{equal, not_equal}

///|
fn ThreadSelection::initial() -> ThreadSelection {
  { index: 0, }
}

///|
pub fn ThreadSelection::index(self : ThreadSelection) -> Int {
  self.index
}

///|
/// A zero-based logical user-frame selection inside the selected thread.
/// Backend-specific stack-frame identifiers never appear in this value.
pub struct FrameSelection {
  priv index : Int
} derive(Debug, Eq)

///|
pub extend FrameSelection with @debug.Debug::{to_repr}

///|
pub extend FrameSelection with Eq::{equal, not_equal}

///|
fn FrameSelection::initial() -> FrameSelection {
  { index: 0, }
}

///|
pub fn FrameSelection::index(self : FrameSelection) -> Int {
  self.index
}

///|
pub struct StopSnapshot {
  priv reason : String
  priv function_name : String
  priv source_path : String?
  priv line : Int?
  priv column : Int?
}

///|
/// Creates an application-level stopped-location snapshot.
pub fn StopSnapshot::new(
  reason : String,
  function_name : String,
  source_path : String?,
  line : Int?,
  column : Int?,
) -> StopSnapshot {
  { reason, function_name, source_path, line, column, }
}

///|
pub fn StopSnapshot::reason(self : StopSnapshot) -> String {
  self.reason
}

///|
pub fn StopSnapshot::function_name(self : StopSnapshot) -> String {
  self.function_name
}

///|
pub fn StopSnapshot::source_path(self : StopSnapshot) -> String? {
  self.source_path
}

///|
pub fn StopSnapshot::line(self : StopSnapshot) -> Int? {
  self.line
}

///|
pub fn StopSnapshot::column(self : StopSnapshot) -> Int? {
  self.column
}

///|
pub enum RunOutcome {
  Stopped(StopSnapshot)
  Exited(Int?)
}

///|
pub fn RunOutcome::stopped(snapshot : StopSnapshot) -> RunOutcome {
  Stopped(snapshot)
}

///|
pub fn RunOutcome::exited(exit_code : Int?) -> RunOutcome {
  Exited(exit_code)
}
