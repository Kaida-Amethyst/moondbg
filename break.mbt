///|
priv suberror BreakpointSourceError {
  BreakpointSourceMissing(String)
  BreakpointSourceIsNotAFile(String)
} derive(Debug)

///|
priv struct CommandBreak {
  target : BreakCommandTarget
  condition : @expression.Condition?
}

///|
priv enum BreakCommandTarget {
  SourceBreakTarget(String, Int)
  CurrentSourceBreakTarget(Int)
  FunctionBreakTarget(@debugger.FunctionBreakpointRequest)
}

///|
fn parse_break_target(
  arguments : StringView,
) -> Result[BreakCommandTarget, String] {
  guard arguments != "" else {
    return Err("break requires <line>, <file>:<line>, or <function>")
  }
  guard arguments.rev_find(":") is Some(separator) else {
    if arguments is ['0'..='9' | '+' | '-', ..] {
      guard arguments.all(character => character is ('0'..='9')) else {
        return Err("breakpoint line must be a positive decimal integer")
      }
      let line = Some(@string.parse_int(arguments, base=10)) catch { _ => None }
      guard line is Some(line) && line > 0 else {
        return Err("breakpoint line must be a positive decimal integer")
      }
      return Ok(CurrentSourceBreakTarget(line))
    }
    let request = @debugger.FunctionBreakpointRequest::parse(arguments) catch {
      @debugger.FunctionNameError(message) => return Err(message)
      error => return Err(@debug.to_string(error))
    }
    return Ok(FunctionBreakTarget(request))
  }
  let source = arguments[:separator].trim(char_set=" \t")
  let line_text = arguments[separator + 1:].trim(char_set=" \t")
  guard source != "" else { return Err("breakpoint file cannot be empty") }
  guard line_text != "" else { return Err("breakpoint line cannot be empty") }
  let parsed_line = Some(@string.parse_int(line_text, base=10)) catch {
    _ => None
  }
  guard parsed_line is Some(line) && line > 0 else {
    return Err("breakpoint line must be a positive integer")
  }
  Ok(SourceBreakTarget(source.to_owned(), line))
}

///|
fn CommandBreak::parse(arguments : StringView) -> Result[CommandBreak, String] {
  // Keep existing file paths (including spaces and the word "if") intact.
  // A valid whole location is never treated as a conditional suffix.
  let original_error = match parse_break_target(arguments) {
    Ok(target) => return Ok({ target, condition: None, })
    Err(message) => message
  }
  let separators : Array[Int] = []
  for offset, _ in arguments.iter2() {
    guard arguments[offset:] is ['i', 'f', .. expression] &&
      (
        offset == 0 ||
        arguments[:offset].has_suffix(" ") ||
        arguments[:offset].has_suffix("\t")
      ) &&
      (expression.is_empty() || expression is [' ' | '\t', ..]) else {
      continue
    }
    separators.push(offset)
  }
  // The suffix follows the location; preceding "if" words may be in its path.
  guard separators.last() is Some(offset) else { return Err(original_error) }
  let target = match
    parse_break_target(arguments[:offset].trim(char_set=" \t")) {
    Ok(target) => target
    Err(message) => return Err(message)
  }
  let condition = @expression.Condition::parse(arguments[offset + 2:].trim()) catch {
    @expression.ConditionError(message) => return Err(message)
  }
  Ok({ target, condition: Some(condition), })
}

///|
fn parse_break_command(
  _invoked_name : StringView,
  arguments : StringView,
) -> CommandParseResult {
  match CommandBreak::parse(arguments) {
    Ok(command) => parsed_command(command)
    Err(message) => invalid_command(message)
  }
}

///|
fn break_command_spec() -> CommandSpec {
  CommandSpec::new(
    "break",
    ["b"],
    "break <location> [if <condition>]",
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
  condition~ : @expression.Condition?,
) -> PresentationEvent {
  let canonical_source = resolve_breakpoint_source(source)
  let breakpoint = session.add_source_breakpoint(
    canonical_source,
    line,
    display_path=source,
    condition~,
  )
  source_breakpoint_presentation(breakpoint, source)
}

///|
impl ReplCommand for CommandBreak with fn execute(self, context) {
  let event = try {
    match self.target {
      SourceBreakTarget(source, line) =>
        set_source_breakpoint(
          context.session,
          source,
          line,
          condition=self.condition,
        )
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
        set_source_breakpoint(
          context.session,
          source,
          line,
          condition=self.condition,
        )
      }
      FunctionBreakTarget(request) => {
        let breakpoint = context.session.add_function_breakpoint(
          request,
          condition=self.condition,
        )
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
  let events = [event]
  let id = match event {
    BreakpointPendingPresentation(id, _, _) => Some(id)
    BreakpointUpdatePresentation(point) => Some(point.id())
    FunctionBreakpointPendingPresentation(id, _) => Some(id)
    FunctionBreakpointUpdatePresentation(point) => Some(point.id())
    _ => None
  }
  if id is Some(id) && self.condition is Some(condition) {
    events.push(ConditionChangedPresentation(id, Some(condition.text)))
  }
  CommandResult::continuing(events~)
}

///|
test "break if parses a conditional source location without splitting file names" {
  for
    (input, path, line, expression) in [
      ("main.mbt:4 if i == 7", "main.mbt", 4, "i == 7"),
      (
        "dir with spaces/main.mbt:12\tif\ti>=-2", "dir with spaces/main.mbt", 12,
        "i >= -2",
      ),
      (
        "dir if other/main.mbt:4 if i != 0", "dir if other/main.mbt", 4, "i != 0",
      ),
    ] {
    assert_true(
      CommandBreak::parse(input)
      is Ok(
        {
          target: SourceBreakTarget(actual_path, actual_line),
          condition: Some(condition),
        }
      ) &&
      actual_path == path &&
      actual_line == line &&
      condition.text == expression,
      msg=input,
    )
  }
  assert_true(
    CommandBreak::parse("4 if i < 7")
    is Ok({ target: CurrentSourceBreakTarget(4), condition: Some(condition), }) &&
    condition.text == "i < 7",
  )
  assert_true(
    CommandBreak::parse("dir if other/main.mbt:4")
    is Ok(
      {
        target: SourceBreakTarget("dir if other/main.mbt", 4),
        condition: None,
      }
    ),
  )
  assert_true(
    CommandBreak::parse("gift")
    is Ok({ target: FunctionBreakTarget(_), condition: None, }),
  )
  for
    input in [
      "", "if i == 7", "0 if i == 7", "4 if", "4 if   ", "4 if i = 7", "4 if i > other()",
      "4 if i > 0 & j < 1", "4 ifi == 7", "4 if point.x + 1 == 7", "main if i ==",
      "@pkg.foo if i ==",
    ] {
    assert_true(CommandBreak::parse(input) is Err(_), msg=input)
  }
  for
    input in [
      "b main.mbt:4 if i == 7", "break 4 if i != 7", "b foo if i >= 3 && i < 8",
      "b @pkg.foo if !(i == 0)",
    ] {
    assert_true(
      default_command_registry().parse_line(input) is RegistryCommand(_),
      msg=input,
    )
  }
}
