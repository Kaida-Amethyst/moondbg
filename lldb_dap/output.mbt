///|
fn output_from_event(event : @dap.DapEvent) -> @moondbg.DebugOutput? {
  guard event.name() == "output" &&
    event.body() is { "output": String(text), .. } &&
    text != "" else {
    return None
  }
  let category = match event.body() {
    { "category": String(category), .. } => Some(category)
    _ => None
  }
  guard category != Some("telemetry") && category != Some("console") else {
    return None
  }
  Some(
    match category {
      Some("stdout") => @moondbg.DebugOutput::standard_output(text)
      Some("stderr") => @moondbg.DebugOutput::standard_error(text)
      _ => @moondbg.DebugOutput::other(text)
    },
  )
}

///|
fn LldbDapSession::take_output(
  self : LldbDapSession,
) -> Array[@moondbg.DebugOutput] {
  let output = self.pending_output.copy()
  self.pending_output.clear()
  if self.execution is Some(execution) {
    for item in execution.take_output() {
      output.push(item)
    }
  }
  output
}

///|
fn DebugExecution::take_output(
  self : DebugExecution,
) -> Array[@moondbg.DebugOutput] {
  let output = self.pending_output.copy()
  self.pending_output.clear()
  output
}
