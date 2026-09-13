///|
priv struct CommandStep {}

///|
fn parse_step_command(
  invoked_name : StringView,
  arguments : StringView,
) -> CommandParseResult {
  guard arguments == "" else {
    return invalid_command("\{invoked_name} does not accept arguments")
  }
  parsed_command(CommandStep::{ })
}

///|
fn step_command_spec() -> CommandSpec {
  CommandSpec::new(
    "step",
    ["s"],
    "step",
    "Step into a called function",
    parse_step_command,
  )
}

///|
impl ReplCommand for CommandStep with fn execute(_self, context) {
  execute_session_action(context, session => session.step())
}
