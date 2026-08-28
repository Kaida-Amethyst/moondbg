///|
priv struct CommandPrint {
  name : String
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
fn parse_print_command(
  _invoked_name : StringView,
  arguments : StringView,
) -> CommandParseResult {
  guard arguments is [first, .. rest] else {
    return invalid_command("print requires a simple variable name")
  }
  guard is_variable_name_char(first, first=true) else {
    return invalid_command("print only accepts a simple variable name")
  }
  for character in rest {
    guard is_variable_name_char(character, first=false) else {
      return invalid_command("print only accepts a simple variable name")
    }
  }
  parsed_command(CommandPrint::{ name: arguments.to_owned(), })
}

///|
fn print_command_spec() -> CommandSpec {
  CommandSpec::new(
    "print",
    ["p"],
    "print <name>",
    "Show a simple variable",
    parse_print_command,
  )
}

///|
impl ReplCommand for CommandPrint with fn execute(self, context) {
  let events : Array[PresentationEvent] = []
  let result = context.session.find_variable(
    @moondbg.VariablePath::root(self.name),
  ) catch {
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
      events.push(VariableNotFoundPresentation(failure.requested_path()))
  }
  CommandResult::continuing(events~)
}
