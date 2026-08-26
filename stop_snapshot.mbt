///|
pub struct StopSnapshot {
  reason : String
  thread_id : Int
  frame_id : Int
  function_name : String
  source_path : String?
  line : Int?
  column : Int?
}

///|
fn StopSnapshot::new(
  reason : String,
  thread_id : Int,
  frame_id : Int,
  function_name : String,
  source_path : String?,
  line : Int?,
  column : Int?,
) -> StopSnapshot {
  { reason, thread_id, frame_id, function_name, source_path, line, column, }
}

///|
pub fn StopSnapshot::reason(self : StopSnapshot) -> String {
  self.reason
}

///|
pub fn StopSnapshot::thread_id(self : StopSnapshot) -> Int {
  self.thread_id
}

///|
pub fn StopSnapshot::frame_id(self : StopSnapshot) -> Int {
  self.frame_id
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
