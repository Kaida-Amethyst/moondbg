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
    Some(@expression.IntCondition::parse(text))
  }
  guard self.source_breakpoints.iter().find_first(point => point.id() == id)
    is Some(_) else {
    if self.function_breakpoints.any(point => point.id() == id) {
      raise BreakpointManagementRejected(
        "Conditions currently support only line breakpoints",
      )
    }
    raise BreakpointNotFound(id)
  }
  let sources = self.source_breakpoints.map(point => {
    if point.id() == id {
      { ..point, condition, }
    } else {
      point
    }
  })
  if self.state() is Stopped {
    self.synchronize_breakpoints(
      BreakpointConfiguration::new(sources, self.function_breakpoints),
    )
    |> ignore
  }
  self.source_breakpoints = sources
}

///|
pub fn DebugSession::condition_text(self : DebugSession, id : Int) -> String? {
  guard self.source_breakpoints.iter().find_first(point => point.id() == id)
    is Some(point) else {
    return None
  }
  point.condition().map(condition => condition.text)
}
