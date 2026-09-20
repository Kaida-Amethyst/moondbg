///|
priv suberror BreakpointSourceError {
  BreakpointSourceMissing(String)
  BreakpointSourceIsNotAFile(String)
} derive(Debug)

///|
priv struct CommandBreak {
  target : BreakCommandTarget
}

///|
priv enum BreakCommandTarget {
  SourceBreakTarget(String, Int)
  CurrentSourceBreakTarget(Int)
  FunctionBreakTarget(@debugger.FunctionBreakpointRequest)
}

///|
fn parse_function_break_target(arguments : StringView) -> CommandParseResult {
  let request = @debugger.FunctionBreakpointRequest::parse(arguments) catch {
    @debugger.FunctionNameError(message) => return invalid_command(message)
    error => return invalid_command(@debug.to_string(error))
  }
  parsed_command(CommandBreak::{ target: FunctionBreakTarget(request), })
}

///|
fn parse_break_command(
  _invoked_name : StringView,
  arguments : StringView,
) -> CommandParseResult {
  guard arguments != "" else {
    return invalid_command(
      "break requires <line>, <file>:<line>, or <function>",
    )
  }
  guard arguments.rev_find(":") is Some(separator) else {
    if arguments is ['0'..='9' | '+' | '-', ..] {
      guard arguments.all(character => character is ('0'..='9')) else {
        return invalid_command(
          "breakpoint line must be a positive decimal integer",
        )
      }
      let line = Some(@string.parse_int(arguments, base=10)) catch { _ => None }
      guard line is Some(line) && line > 0 else {
        return invalid_command(
          "breakpoint line must be a positive decimal integer",
        )
      }
      return parsed_command(CommandBreak::{
        target: CurrentSourceBreakTarget(line),
      })
    }
    return parse_function_break_target(arguments)
  }
  let source = arguments[:separator].trim(char_set=" \t")
  let line_text = arguments[separator + 1:].trim(char_set=" \t")
  guard source != "" else {
    return invalid_command("breakpoint file cannot be empty")
  }
  guard line_text != "" else {
    return invalid_command("breakpoint line cannot be empty")
  }
  let parsed_line = Some(@string.parse_int(line_text, base=10)) catch {
    _ => None
  }
  guard parsed_line is Some(line) && line > 0 else {
    return invalid_command("breakpoint line must be a positive integer")
  }
  parsed_command(CommandBreak::{
    target: SourceBreakTarget(source.to_owned(), line),
  })
}

///|
fn break_command_spec() -> CommandSpec {
  CommandSpec::new(
    "break",
    ["b"],
    "break <location>",
    "Set a breakpoint at line (selected frame), file:line, function, or @alias.function",
    parse_break_command,
  )
}

///|
fn source_breakpoint_presentation(
  breakpoint : @debugger.BreakpointSnapshot,
  requested_source : String,
) -> PresentationEvent {
  match breakpoint.status() {
    @debugger.Pending =>
      BreakpointPendingPresentation(
        breakpoint.id(),
        requested_source,
        breakpoint.requested_line(),
      )
    @debugger.Verified | @debugger.Rejected(_) =>
      BreakpointUpdatePresentation(breakpoint)
  }
}

///|
fn function_breakpoint_presentation(
  breakpoint : @debugger.FunctionBreakpointSnapshot,
) -> PresentationEvent {
  match breakpoint.status() {
    @debugger.Pending =>
      FunctionBreakpointPendingPresentation(
        breakpoint.id(),
        breakpoint.display_name(),
      )
    @debugger.Verified | @debugger.Rejected(_) =>
      FunctionBreakpointUpdatePresentation(breakpoint)
  }
}

///|
async fn resolve_breakpoint_source(path : String) -> String {
  guard @fs.exists(path) else { raise BreakpointSourceMissing(path) }
  guard @fs.kind(path) is Regular else {
    raise BreakpointSourceIsNotAFile(path)
  }
  @fs.realpath(path)
}

///|
async fn set_source_breakpoint(
  session : @debugger.DebugSession,
  source : String,
  line : Int,
) -> PresentationEvent {
  let canonical_source = resolve_breakpoint_source(source)
  let breakpoint = session.add_source_breakpoint(
    canonical_source,
    line,
    display_path=source,
  )
  source_breakpoint_presentation(breakpoint, source)
}

///|
impl ReplCommand for CommandBreak with fn execute(self, context) {
  let event = try {
    match self.target {
      SourceBreakTarget(source, line) =>
        set_source_breakpoint(context.session, source, line)
      CurrentSourceBreakTarget(line) => {
        guard context.session.selected_frame_snapshot() is Some(frame) else {
          return CommandResult::continuing(events=[
            BreakpointErrorPresentation(BreakpointCurrentFrameMissing),
          ])
        }
        guard frame.source_path() is Some(source) && source != "" else {
          return CommandResult::continuing(events=[
            BreakpointErrorPresentation(BreakpointCurrentFrameSourceMissing),
          ])
        }
        set_source_breakpoint(context.session, source, line)
      }
      FunctionBreakTarget(request) => {
        let breakpoint = context.session.add_function_breakpoint(request)
        function_breakpoint_presentation(breakpoint)
      }
    }
  } catch {
    BreakpointSourceMissing(path) =>
      BreakpointErrorPresentation(BreakpointSourceNotFound(path))
    BreakpointSourceIsNotAFile(path) =>
      BreakpointErrorPresentation(BreakpointSourceNotAFile(path))
    @debugger.OperationNotAllowed(state~, action~) =>
      BreakpointErrorPresentation(BreakpointOperationNotAllowed(state, action))
    @debugger.MissingCurrentPackage =>
      BreakpointErrorPresentation(BreakpointFunctionContextMissing)
    @debugger.UnknownPackageAlias(package_alias) =>
      BreakpointErrorPresentation(BreakpointUnknownPackageAlias(package_alias))
    @debugger.AdapterFailure(message) => AdapterFailurePresentation(message)
    error =>
      BreakpointErrorPresentation(
        BreakpointUnexpectedFailure(@debug.to_string(error)),
      )
  }
  CommandResult::continuing(events=[event])
}
