///|
fn append_debuggee_output(
  events : Array[PresentationEvent],
  session : @moondbg.DebugSession,
) -> Unit {
  let output = session.take_output()
  guard output is [_, ..] else { return }
  events.push(DebuggeeOutputPresentation(output))
}

///|
fn append_breakpoint_updates(
  events : Array[PresentationEvent],
  session : @moondbg.DebugSession,
) -> Unit {
  for breakpoint in session.source_breakpoints() {
    events.push(BreakpointUpdatePresentation(breakpoint))
  }
}

///|
fn append_execution_outcome(
  events : Array[PresentationEvent],
  outcome : @moondbg.RunOutcome,
) -> Unit {
  match outcome {
    @moondbg.Stopped(snapshot) => events.push(StopPresentation(snapshot))
    @moondbg.Exited(exit_code) =>
      events.push(ProcessExitPresentation(exit_code))
  }
}

///|
/// Runs one DebugSession action and converts its domain result to ordered
/// frontend events. The helper knows no concrete command type and contains no
/// adapter or protocol concepts.
async fn execute_session_action(
  context : ReplContext,
  operation : async (@moondbg.DebugSession) -> @moondbg.RunOutcome,
  restarting? : Bool = false,
  report_breakpoints? : Bool = false,
) -> CommandResult {
  let events : Array[PresentationEvent] = []
  if restarting {
    events.push(ProgramRestartingPresentation)
  }
  let outcome = operation(context.session) catch {
    @moondbg.OperationNotAllowed(state~, action~) => {
      events.push(OperationNotAllowedPresentation(state, action))
      return CommandResult::continuing(events~)
    }
    @moondbg.AdapterFailure(message) => {
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
