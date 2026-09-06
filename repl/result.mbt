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
  FunctionBreakpointPendingPresentation(Int, String)
  FunctionBreakpointUpdatePresentation(@moondbg.FunctionBreakpointSnapshot)
  BreakpointErrorPresentation(BreakpointCommandError)
  BreakpointsPresentation(Array[@moondbg.BreakpointListEntry])
  BreakpointManagedPresentation(@moondbg.BreakpointManagementResult)
  BreakpointManagementFailurePresentation(BreakpointManagementFailure)
  StopPresentation(@moondbg.StopSnapshot)
  BacktracePresentation(BacktraceView)
  FrameSelectedPresentation(@moondbg.StackFrameSnapshot)
  FrameSelectionFailurePresentation(FrameSelectionFailure)
  SourceViewPresentation(SourceView)
  VariablePresentation(@moondbg.VariableSnapshot)
  VariableLookupFailurePresentation(@moondbg.VariableLookupFailure)
  LocalsPresentation(@moondbg.LocalVariablesSnapshot)
  NoStoppedSourcePresentation
  ProcessExitPresentation(Int?)
  OperationNotAllowedPresentation(@moondbg.DebugSessionState, String)
  AdapterFailurePresentation(String)
}

///|
priv struct BacktraceView {
  frames : Array[@moondbg.StackFrameSnapshot]
  selected_frame : Int?
}

///|
fn BacktraceView::from_stack(
  stack : @moondbg.StackSnapshot,
  selected_frame : Int?,
  show_all~ : Bool,
) -> BacktraceView {
  let frames : Array[@moondbg.StackFrameSnapshot] = []
  if show_all {
    for frame in stack.frames() {
      frames.push(frame)
    }
  } else {
    for frame in stack.visible_frames() {
      frames.push(frame)
    }
  }
  if !show_all && frames is [] && stack.frames() is [first, ..] {
    frames.push(first)
  }
  { frames, selected_frame, }
}

///|
priv enum FrameSelectionFailure {
  FrameUnavailable(Int)
  CurrentFrameUnavailable
  CallerBoundary(Int)
  CalleeBoundary(Int)
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
fn SourceView::from_frame(
  frame : @moondbg.StackFrameSnapshot,
  line_count~ : Int,
) -> SourceView {
  { source_path: frame.source_path(), line: frame.line(), line_count, }
}

///|
/// Errors specific to the user-facing source breakpoint command. Keeping the
/// cases semantic lets non-human renderers distinguish invalid paths from
/// debugger-state failures without parsing terminal text.
priv enum BreakpointCommandError {
  BreakpointCurrentFrameMissing
  BreakpointCurrentFrameSourceMissing
  BreakpointSourceNotFound(String)
  BreakpointSourceNotAFile(String)
  BreakpointOperationNotAllowed(@moondbg.DebugSessionState, String)
  BreakpointFunctionContextMissing
  BreakpointUnknownPackageAlias(String)
  BreakpointUnexpectedFailure(String)
}

///|
priv enum BreakpointManagementFailure {
  BreakpointIdNotFound(Int)
  BreakpointManagementRefused(String)
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
