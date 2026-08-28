///|
priv enum ReplControlFlow {
  ContinueRepl
  ExitRepl
}

///|
const DEFAULT_SOURCE_LINE_COUNT : Int = 10

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
  SourceViewPresentation(SourceView)
  VariablePresentation(@moondbg.VariableSnapshot)
  VariableNotFoundPresentation(String)
  NoStoppedSourcePresentation
  ProcessExitPresentation(Int?)
  OperationNotAllowedPresentation(@moondbg.DebugSessionState, String)
  AdapterFailurePresentation(String)
}

///|
/// A renderer-independent request for source context around one line. Source
/// loading and MoonBit highlighting remain presentation responsibilities.
priv struct SourceView {
  source_path : String?
  line : Int?
  line_count : Int
}

///|
fn SourceView::from_stop(
  snapshot : @moondbg.StopSnapshot,
  line_count~ : Int,
) -> SourceView {
  { source_path: snapshot.source_path(), line: snapshot.line(), line_count, }
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
/// Result returned by every command.
priv struct CommandResult {
  control : ReplControlFlow
  events : Array[PresentationEvent]
}

///|
fn CommandResult::continuing(
  events? : Array[PresentationEvent] = [],
) -> CommandResult {
  { control: ContinueRepl, events, }
}

///|
fn CommandResult::exiting() -> CommandResult {
  { control: ExitRepl, events: [], }
}

///|
priv trait PresentationRenderer {
  async fn render(Self, events : Array[PresentationEvent]) -> Unit
}
