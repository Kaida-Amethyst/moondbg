///|
pub struct DebugOutput {
  category : String?
  text : String
}

///|
fn DebugOutput::new(category : String?, text : String) -> DebugOutput {
  { category, text, }
}

///|
pub fn DebugOutput::category(self : DebugOutput) -> String? {
  self.category
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
  Some(DebugOutput::new(category, text))
}
