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
  FunctionBreakTarget(@moondbg.FunctionBreakpointRequest)
}

///|
fn parse_function_break_target(arguments : StringView) -> CommandParseResult {
  guard !arguments.contains(" ") && !arguments.contains("\t") else {
    return invalid_command("function breakpoint must be one function name")
  }
  if arguments.has_prefix("@") {
    guard arguments[1:].split_once(".") is Some((package_alias, function_name)) &&
      package_alias != "" &&
      function_name != "" &&
      !function_name.contains(".") &&
      !function_name.contains("@") else {
      return invalid_command(
        "cross-package function must use @<alias>.<function>",
      )
    }
    return parsed_command(CommandBreak::{
      target: FunctionBreakTarget(
        @moondbg.FunctionBreakpointRequest::imported(
          package_alias.to_owned(),
          function_name.to_owned(),
        ),
      ),
    })
  }
  guard !arguments.contains(".") && !arguments.contains("@") else {
    return invalid_command(
      "function breakpoint must use <function> or @<alias>.<function>",
    )
  }
  parsed_command(CommandBreak::{
    target: FunctionBreakTarget(
      @moondbg.FunctionBreakpointRequest::current(arguments.to_owned()),
    ),
  })
}

///|
fn parse_break_command(
  _invoked_name : StringView,
  arguments : StringView,
) -> CommandParseResult {
  guard arguments != "" else {
    return invalid_command("break requires <file>:<line> or <function>")
  }
  guard arguments.rev_find(":") is Some(separator) else {
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
    "Set a breakpoint at file:line, function, or @alias.function",
    parse_break_command,
  )
}

///|
fn source_breakpoint_presentation(
  breakpoint : @moondbg.BreakpointSnapshot,
  requested_source : String,
) -> PresentationEvent {
  match breakpoint.status() {
    @moondbg.Pending =>
      BreakpointPendingPresentation(
        breakpoint.id(),
        requested_source,
        breakpoint.requested_line(),
      )
    @moondbg.Verified | @moondbg.Rejected(_) =>
      BreakpointUpdatePresentation(breakpoint)
  }
}

///|
fn function_breakpoint_presentation(
  breakpoint : @moondbg.FunctionBreakpointSnapshot,
) -> PresentationEvent {
  match breakpoint.status() {
    @moondbg.Pending =>
      FunctionBreakpointPendingPresentation(
        breakpoint.id(),
        breakpoint.display_name(),
      )
    @moondbg.Verified | @moondbg.Rejected(_) =>
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
impl ReplCommand for CommandBreak with fn execute(self, context) {
  let event = try {
    match self.target {
      SourceBreakTarget(source, line) => {
        let canonical_source = resolve_breakpoint_source(source)
        let breakpoint = context.session.add_source_breakpoint(
          canonical_source,
          line,
          display_path=source,
        )
        source_breakpoint_presentation(breakpoint, source)
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
    @moondbg.OperationNotAllowed(state~, action~) =>
      BreakpointErrorPresentation(BreakpointOperationNotAllowed(state, action))
    @moondbg.MissingCurrentPackage =>
      BreakpointErrorPresentation(BreakpointFunctionContextMissing)
    @moondbg.UnknownPackageAlias(package_alias) =>
      BreakpointErrorPresentation(BreakpointUnknownPackageAlias(package_alias))
    @moondbg.AdapterFailure(message) => AdapterFailurePresentation(message)
    error =>
      BreakpointErrorPresentation(
        BreakpointUnexpectedFailure(@debug.to_string(error)),
      )
  }
  CommandResult::continuing(events=[event])
}
