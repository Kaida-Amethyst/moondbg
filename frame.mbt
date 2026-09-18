///|
priv struct CommandFrame {
  physical_index : Int
}

///|
fn parse_frame_index(arguments : StringView) -> Int? {
  guard arguments != "" && arguments.all(character => character is ('0'..='9')) else {
    return None
  }
  Some(@string.parse_int(arguments, base=10)) catch {
    _ => None
  }
}

///|
fn parse_frame_command(
  _invoked_name : StringView,
  arguments : StringView,
) -> CommandParseResult {
  guard parse_frame_index(arguments) is Some(physical_index) else {
    return invalid_command("frame requires one non-negative frame number")
  }
  parsed_command(CommandFrame::{ physical_index, })
}

///|
fn frame_command_spec() -> CommandSpec {
  CommandSpec::new(
    "frame",
    [],
    "frame <number>",
    "Select a physical stack frame",
    parse_frame_command,
  )
}

///|
async fn execute_frame_selection(
  context : ReplContext,
  operation : async (@debugger.DebugSession) -> @debugger.StackFrameSnapshot,
) -> CommandResult {
  let frame = operation(context.session) catch {
    @debugger.OperationNotAllowed(state~, action~) =>
      return CommandResult::continuing(events=[
        OperationNotAllowedPresentation(state, action),
      ])
    @debugger.FrameNotFound(index) | @debugger.FrameNotLoaded(index) =>
      return CommandResult::continuing(events=[
        FrameSelectionFailurePresentation(FrameUnavailable(index)),
      ])
    @debugger.NoFrameSelected =>
      return CommandResult::continuing(events=[
        FrameSelectionFailurePresentation(CurrentFrameUnavailable),
      ])
    @debugger.NoVisibleCaller(index) =>
      return CommandResult::continuing(events=[
        FrameSelectionFailurePresentation(CallerBoundary(index)),
      ])
    @debugger.NoVisibleCallee(index) =>
      return CommandResult::continuing(events=[
        FrameSelectionFailurePresentation(CalleeBoundary(index)),
      ])
    @debugger.AdapterFailure(message) =>
      return CommandResult::continuing(events=[
        AdapterFailurePresentation(message),
      ])
    error => raise error
  }
  CommandResult::continuing(events=[
    FrameSelectedPresentation(frame),
    SourceViewPresentation(
      SourceView::from_frame(frame, line_count=DEFAULT_SOURCE_LINE_COUNT),
    ),
  ])
}

///|
impl ReplCommand for CommandFrame with fn execute(self, context) {
  execute_frame_selection(context, session => {
    session.select_frame(self.physical_index)
  })
}
