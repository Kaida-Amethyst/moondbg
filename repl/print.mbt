///|
priv struct CommandPrint {
  path : @moondbg.VariablePath
}

///|
fn is_variable_name_char(character : Char, first~ : Bool) -> Bool {
  if character.is_ascii() {
    character.is_ascii_alphabetic() ||
    character == '_' ||
    (!first && character.is_ascii_digit())
  } else {
    character.is_printable() &&
    !character.is_whitespace() &&
    !character.is_control()
  }
}

///|
fn is_variable_path_segment(segment : StringView) -> Bool {
  guard segment is [first, .. rest] && is_variable_name_char(first, first=true) else {
    return false
  }
  rest.all(character => is_variable_name_char(character, first=false))
}

///|
fn parse_variable_path(arguments : StringView) -> @moondbg.VariablePath? {
  let segments : Array[String] = arguments
    .to_owned()
    .split(".")
    .map(segment => segment.to_owned())
    .collect()
  guard segments.length() > 0 else { return None }
  for segment in segments {
    guard is_variable_path_segment(segment) else { return None }
  }
  let fields : Array[String] = []
  for index in 1..<segments.length() {
    fields.push(segments[index])
  }
  Some(@moondbg.VariablePath::with_fields(segments[0], fields))
}

///|
fn parse_print_command(
  _invoked_name : StringView,
  arguments : StringView,
) -> CommandParseResult {
  guard arguments != "" else {
    return invalid_command("print requires a variable path")
  }
  guard parse_variable_path(arguments) is Some(path) else {
    return invalid_command("print only accepts a variable or struct field path")
  }
  parsed_command(CommandPrint::{ path, })
}

///|
fn print_command_spec() -> CommandSpec {
  CommandSpec::new(
    "print",
    ["p"],
    "print <path>",
    "Show a variable or struct field path",
    parse_print_command,
  )
}

///|
impl ReplCommand for CommandPrint with fn execute(self, context) {
  let events : Array[PresentationEvent] = []
  let result = context.session.find_variable(self.path) catch {
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
  match result {
    @moondbg.VariableFound(variable) =>
      events.push(VariablePresentation(variable))
    @moondbg.VariableLookupFailed(failure) =>
      events.push(VariableLookupFailurePresentation(failure))
  }
  CommandResult::continuing(events~)
}
