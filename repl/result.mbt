///|
priv enum ReplControlFlow {
  ContinueRepl
  ExitRepl
}

///|
priv struct CommandHelpEntry {
  name : String
  aliases : Array[String]
  usage : String
  summary : String
}

///|
fn CommandHelpEntry::alias_usage(self : CommandHelpEntry) -> String {
  guard self.aliases is [_, ..] else { return "" }
  let suffix = match self.usage.strip_prefix(self.name) {
    Some(suffix) => suffix
    None => ""
  }
  let alias_usage = self.aliases
    .map(command_alias => "\{command_alias}\{suffix}")
    .join(", ")
  alias_usage
}

///|
priv enum PresentationEvent {
  HelpPresentation(Array[CommandHelpEntry])
  UserErrorPresentation(String)
  DebuggeeOutputPresentation(Array[@moondbg.DebugOutput])
  ProgramRestartingPresentation
  BreakpointPendingPresentation(Int, String, Int)
  BreakpointUpdatePresentation(@moondbg.BreakpointSnapshot)
  BreakpointErrorPresentation(BreakpointCommandError)
  StopPresentation(@moondbg.StopSnapshot)
  ProcessExitPresentation(Int?)
  OperationNotAllowedPresentation(@moondbg.DebugSessionState, String)
  AdapterFailurePresentation(String)
}

///|
/// Errors specific to the user-facing source breakpoint command. Keeping the
/// cases semantic lets non-human renderers distinguish invalid paths from
/// debugger-state failures without parsing terminal text.
priv enum BreakpointCommandError {
  BreakpointSourceNotFound(String)
  BreakpointSourceNotAFile(String)
  BreakpointOperationNotAllowed(@moondbg.DebugSessionState, String)
  BreakpointUnexpectedFailure(String)
}

///|
/// Result returned by every command. LegacyAction is a temporary bridge which
/// P6/P7 remove as commands gain their own structured events.
priv struct CommandResult {
  control : ReplControlFlow
  events : Array[PresentationEvent]
  legacy_action : LegacyAction?
}

///|
fn CommandResult::continuing(
  events? : Array[PresentationEvent] = [],
) -> CommandResult {
  { control: ContinueRepl, events, legacy_action: None, }
}

///|
fn CommandResult::exiting() -> CommandResult {
  { control: ExitRepl, events: [], legacy_action: None, }
}

///|
fn CommandResult::legacy(action : LegacyAction) -> CommandResult {
  { control: ContinueRepl, events: [], legacy_action: Some(action), }
}

///|
priv trait PresentationRenderer {
  async fn render(Self, events : Array[PresentationEvent]) -> Unit
}
