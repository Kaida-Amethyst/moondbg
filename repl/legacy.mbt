///|
/// Temporary P7 bridge. Command names and parser factories already live in
/// CommandSpec; only print/list's old side-effecting presentation remains.
priv enum LegacyAction {
  LegacyPrintVariable(String)
  LegacyList(Int)
}

///|
priv struct CommandLegacy {
  action : LegacyAction
}

///|
impl ReplCommand for CommandLegacy with fn execute(self, _context) {
  CommandResult::legacy(self.action)
}

///|
fn parsed_legacy_action(action : LegacyAction) -> CommandParseResult {
  parsed_command(CommandLegacy::{ action, })
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
fn parse_legacy_variable(
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
  parsed_legacy_action(LegacyPrintVariable(arguments.to_owned()))
}

///|
fn parse_legacy_list_count(arguments : StringView) -> CommandParseResult {
  guard arguments != "" else {
    return invalid_command("list count must be a positive integer")
  }
  let parsed_count = Some(@string.parse_int(arguments, base=10)) catch {
    _ => None
  }
  guard parsed_count is Some(count) && count > 0 else {
    return invalid_command("list count must be a positive integer")
  }
  parsed_legacy_action(LegacyList(count))
}

///|
fn parse_legacy_list(
  _invoked_name : StringView,
  arguments : StringView,
) -> CommandParseResult {
  guard arguments != "" else {
    return parsed_legacy_action(LegacyList(DEFAULT_SOURCE_LINE_COUNT))
  }
  guard parse_command_invocation(arguments) is Some(option) else {
    return invalid_command("list only accepts -c <count> or --count <count>")
  }
  match option.name {
    "-c" | "--count" => parse_legacy_list_count(option.arguments)
    _ => invalid_command("list only accepts -c <count> or --count <count>")
  }
}

///|
fn legacy_print_command_spec() -> CommandSpec {
  CommandSpec::new(
    "print",
    ["p"],
    "print <name>",
    "Show a simple variable",
    parse_legacy_variable,
  )
}

///|
fn legacy_list_command_spec() -> CommandSpec {
  CommandSpec::new(
    "list",
    [],
    "list [-c|--count <count>]",
    "Show source context (default: 5 lines)",
    parse_legacy_list,
  )
}

///|
async fn inspect_legacy_variable(context : ReplContext, name : String) -> Unit {
  let result = context.session.find_variable(name) catch {
    @moondbg.OperationNotAllowed(state~, action~) => {
      render_presentation_event(OperationNotAllowedPresentation(state, action))
      return
    }
    @moondbg.AdapterFailure(message) => {
      render_debuggee_outputs(context.session.take_output())
      render_presentation_event(AdapterFailurePresentation(message))
      return
    }
    error => raise error
  }
  render_debuggee_outputs(context.session.take_output())
  match result {
    @moondbg.VariableFound(variable) =>
      match variable.type_name() {
        Some(type_name) =>
          println("\{variable.name()}: \{type_name} = \{variable.value()}")
        None => println("\{variable.name()} = \{variable.value()}")
      }
    @moondbg.VariableNotFound(variable_name) =>
      println("Variable '\{variable_name}' was not found in the current frame.")
  }
}

///|
/// Temporary P7 side-effect bridge for the two observation commands which
/// have not yet gained structured presentation events.
async fn execute_legacy_action(
  context : ReplContext,
  action : LegacyAction,
) -> Unit {
  match action {
    LegacyPrintVariable(name) => inspect_legacy_variable(context, name)
    LegacyList(line_count) =>
      match context.session.last_stop_snapshot() {
        Some(snapshot) => render_stop_snapshot(snapshot, line_count~)
        None => println("No stopped source location is available.")
      }
  }
}
