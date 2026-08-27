///|
pub enum DebugOutputKind {
  StandardOutput
  StandardError
  OtherOutput
} derive(Debug, Eq)

///|
pub extend DebugOutputKind with @debug.Debug::{to_repr}

///|
pub extend DebugOutputKind with Eq::{equal, not_equal}

///|
pub struct DebugOutput {
  kind : DebugOutputKind
  text : String
}

///|
fn DebugOutput::new(kind : DebugOutputKind, text : String) -> DebugOutput {
  { kind, text, }
}

///|
pub fn DebugOutput::kind(self : DebugOutput) -> DebugOutputKind {
  self.kind
}

///|
pub fn DebugOutput::text(self : DebugOutput) -> String {
  self.text
}

///|
fn output_from_event(event : DapEvent) -> DebugOutput? {
  guard event.name == "output" &&
    event.body is { "output": String(text), .. } &&
    text != "" else {
    return None
  }
  let category = match event.body {
    { "category": String(category), .. } => Some(category)
    _ => None
  }
  guard category != Some("telemetry") && category != Some("console") else {
    return None
  }
  let kind = match category {
    Some("stdout") => StandardOutput
    Some("stderr") => StandardError
    _ => OtherOutput
  }
  Some(DebugOutput::new(kind, text))
}
