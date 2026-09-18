///|
fn append_debuggee_output(
  events : Array[PresentationEvent],
  session : @debugger.DebugSession,
) -> Unit {
  let output = session.take_output()
  guard output is [_, ..] else { return }
  events.push(DebuggeeOutputPresentation(output))
}

///|
fn append_breakpoint_updates(
  events : Array[PresentationEvent],
  session : @debugger.DebugSession,
) -> Unit {
  let enabled : Map[Int, Bool] = Map([])
  let configuration = session.breakpoint_configuration()
  for breakpoint in configuration.sources() {
    enabled.set(breakpoint.id(), breakpoint.enabled())
  }
  for breakpoint in configuration.functions() {
    enabled.set(breakpoint.id(), breakpoint.enabled())
  }
  for breakpoint in session.source_breakpoints() {
    if enabled.get(breakpoint.id()) is Some(true) {
      events.push(BreakpointUpdatePresentation(breakpoint))
    }
  }
  for breakpoint in session.function_breakpoints() {
    if enabled.get(breakpoint.id()) is Some(true) {
      events.push(FunctionBreakpointUpdatePresentation(breakpoint))
    }
  }
}

///|
fn append_execution_outcome(
  events : Array[PresentationEvent],
  outcome : @debugger.RunOutcome,
) -> Unit {
  match outcome {
    @debugger.Stopped(snapshot) => {
      events.push(StopPresentation(snapshot))
      events.push(
        SourceViewPresentation(
          SourceView::from_stop(snapshot, line_count=DEFAULT_SOURCE_LINE_COUNT),
        ),
      )
    }
    @debugger.Exited(exit_code) =>
      events.push(ProcessExitPresentation(exit_code))
  }
}

///|
/// Runs one DebugSession action and converts its domain result to ordered
/// frontend events. The helper knows no concrete command type and contains no
/// adapter or protocol concepts.
async fn execute_session_action(
  context : ReplContext,
  operation : async (@debugger.DebugSession) -> @debugger.RunOutcome,
  restarting? : Bool = false,
  report_breakpoints? : Bool = false,
) -> CommandResult {
  let events : Array[PresentationEvent] = []
  if restarting {
    events.push(ProgramRestartingPresentation)
  }
  let outcome = operation(context.session) catch {
    @debugger.OperationNotAllowed(state~, action~) => {
      events.push(OperationNotAllowedPresentation(state, action))
      return CommandResult::continuing(events~)
    }
    @debugger.AdapterFailure(message) => {
      append_debuggee_output(events, context.session)
      events.push(AdapterFailurePresentation(message))
      return CommandResult::continuing(events~)
    }
    error => raise error
  }
  append_debuggee_output(events, context.session)
  if report_breakpoints {
    append_breakpoint_updates(events, context.session)
  }
  append_execution_outcome(events, outcome)
  CommandResult::continuing(events~)
}
