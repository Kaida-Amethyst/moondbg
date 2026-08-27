///|
const DEFAULT_SOURCE_LINE_COUNT : Int = 5

///|
priv enum LegacyStepKind {
  LegacyStepOver
  LegacyStepInto
  LegacyStepOut
}

///|
/// Temporary execution bridge for commands migrated in P6/P7. Names and
/// parser factories already live in CommandSpec; only their old side-effecting
/// execution remains behind this enum.
priv enum LegacyAction {
  LegacyRun
  LegacyBreak(String, Int)
  LegacyContinue
  LegacyStepExecution(LegacyStepKind)
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
fn parse_legacy_no_arguments(
  invoked_name : StringView,
  arguments : StringView,
  action : LegacyAction,
) -> CommandParseResult {
  guard arguments == "" else {
    return invalid_command("\{invoked_name} does not accept arguments")
  }
  parsed_legacy_action(action)
}

///|
fn parse_legacy_break(
  _invoked_name : StringView,
  arguments : StringView,
) -> CommandParseResult {
  guard arguments != "" else {
    return invalid_command("break requires <file>:<line>")
  }
  guard arguments.rev_find(":") is Some(separator) else {
    return invalid_command("breakpoint must use <file>:<line>")
  }
  let source = arguments[0:separator].trim(char_set=" \t")
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
  parsed_legacy_action(LegacyBreak(source.to_owned(), line))
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
fn legacy_break_command_spec() -> CommandSpec {
  CommandSpec::new(
    "break",
    ["b"],
    "break <file>:<line>",
    "Set a source breakpoint",
    parse_legacy_break,
  )
}

///|
fn legacy_run_command_spec() -> CommandSpec {
  CommandSpec::new("run", ["r"], "run", "Run or restart the program", (
    name,
    arguments,
  ) => parse_legacy_no_arguments(name, arguments, LegacyRun))
}

///|
fn legacy_continue_command_spec() -> CommandSpec {
  CommandSpec::new(
    "continue",
    ["c"],
    "continue",
    "Continue the stopped program",
    (name, arguments) => {
      parse_legacy_no_arguments(name, arguments, LegacyContinue)
    },
  )
}

///|
fn legacy_next_command_spec() -> CommandSpec {
  CommandSpec::new("next", ["n"], "next", "Step over the current source line", (
    name,
    arguments,
  ) => {
    parse_legacy_no_arguments(
      name,
      arguments,
      LegacyStepExecution(LegacyStepOver),
    )
  })
}

///|
fn legacy_step_command_spec() -> CommandSpec {
  CommandSpec::new("step", ["s"], "step", "Step into a called function", (
    name,
    arguments,
  ) => {
    parse_legacy_no_arguments(
      name,
      arguments,
      LegacyStepExecution(LegacyStepInto),
    )
  })
}

///|
fn legacy_finish_command_spec() -> CommandSpec {
  CommandSpec::new(
    "finish",
    ["fin"],
    "finish",
    "Step out of the current function",
    (name, arguments) => {
      parse_legacy_no_arguments(
        name,
        arguments,
        LegacyStepExecution(LegacyStepOut),
      )
    },
  )
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
