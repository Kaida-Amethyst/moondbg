///|
priv suberror BreakpointSourceError {
  BreakpointSourceMissing(String)
  BreakpointSourceIsNotAFile(String)
} derive(Debug)

///|
priv struct CommandBreak {
  source : String
  line : Int
}

///|
fn parse_break_command(
  _invoked_name : StringView,
  arguments : StringView,
) -> CommandParseResult {
  guard arguments != "" else {
    return invalid_command("break requires <file>:<line>")
  }
  guard arguments.rev_find(":") is Some(separator) else {
    return invalid_command("breakpoint must use <file>:<line>")
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
  parsed_command(CommandBreak::{ source: source.to_owned(), line, })
}

///|
fn break_command_spec() -> CommandSpec {
  CommandSpec::new(
    "break",
    ["b"],
    "break <file>:<line>",
    "Set a source breakpoint",
    parse_break_command,
  )
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
impl ReplCommand for CommandBreak with fn execute(self, context) {
  let event = try {
    let canonical_source = resolve_breakpoint_source(self.source)
    let breakpoint = context.session.add_source_breakpoint(
      canonical_source,
      self.line,
    )
    BreakpointPendingPresentation(breakpoint.id(), self.source, self.line)
  } catch {
    BreakpointSourceMissing(path) =>
      BreakpointErrorPresentation(BreakpointSourceNotFound(path))
    BreakpointSourceIsNotAFile(path) =>
      BreakpointErrorPresentation(BreakpointSourceNotAFile(path))
    @moondbg.OperationNotAllowed(state~, action~) =>
      BreakpointErrorPresentation(BreakpointOperationNotAllowed(state, action))
    error =>
      BreakpointErrorPresentation(
        BreakpointUnexpectedFailure(@debug.to_string(error)),
      )
  }
  CommandResult::continuing(events=[event])
}
