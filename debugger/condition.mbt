///|
pub async fn DebugSession::set_condition(
  self : DebugSession,
  id : Int,
  text : String,
) -> Unit {
  guard self.state() is (Ready | Stopped) else {
    raise OperationNotAllowed(
      state=self.state(),
      action="set breakpoint condition",
    )
  }
  let condition = if text.trim().is_empty() {
    None
  } else {
    Some(@expression.Condition::parse(text))
  }
  guard self.source_breakpoints.any(point => point.id() == id) ||
    self.function_breakpoints.any(point => point.id() == id) else {
    raise BreakpointNotFound(id)
  }
  let sources = self.source_breakpoints.map(point => {
    if point.id() == id {
      { ..point, condition, }
    } else {
      point
    }
  })
  let functions = self.function_breakpoints.map(point => {
    if point.id() == id {
      { ..point, condition, }
    } else {
      point
    }
  })
  if self.state() is Stopped {
    self.synchronize_breakpoints(
      BreakpointConfiguration::new(sources, functions),
    )
    |> ignore
  }
  self.source_breakpoints = sources
  self.function_breakpoints = functions
}

///|
pub fn DebugSession::condition_text(self : DebugSession, id : Int) -> String? {
  guard self.source_breakpoints.iter().find_first(point => point.id() == id)
    is Some(point) else {
    return match
      self.function_breakpoints.iter().find_first(point => point.id() == id) {
      Some(point) => point.condition().map(condition => condition.text)
      None => None
    }
  }
  point.condition().map(condition => condition.text)
}
