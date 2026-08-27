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
