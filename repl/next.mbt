///|
priv struct CommandNext {}

///|
fn parse_next_command(
  invoked_name : StringView,
  arguments : StringView,
) -> CommandParseResult {
  guard arguments == "" else {
    return invalid_command("\{invoked_name} does not accept arguments")
  }
  parsed_command(CommandNext::{ })
}

///|
fn next_command_spec() -> CommandSpec {
  CommandSpec::new(
    "next",
    ["n"],
    "next",
    "Step over the current source line",
    parse_next_command,
  )
}

///|
impl ReplCommand for CommandNext with fn execute(_self, context) {
  execute_session_action(context, session => session.next())
}
