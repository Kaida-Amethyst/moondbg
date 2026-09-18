///|
priv struct CommandContinue {}

///|
fn parse_continue_command(
  invoked_name : StringView,
  arguments : StringView,
) -> CommandParseResult {
  guard arguments == "" else {
    return invalid_command("\{invoked_name} does not accept arguments")
  }
  parsed_command(CommandContinue::{ })
}

///|
fn continue_command_spec() -> CommandSpec {
  CommandSpec::new(
    "continue",
    ["c"],
    "continue",
    "Continue the stopped program",
    parse_continue_command,
  )
}

///|
impl ReplCommand for CommandContinue with fn execute(_self, context) {
  execute_session_action(context, session => session.continue_execution())
}
