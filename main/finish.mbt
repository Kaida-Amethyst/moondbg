///|
priv struct CommandFinish {}

///|
fn parse_finish_command(
  invoked_name : StringView,
  arguments : StringView,
) -> CommandParseResult {
  guard arguments == "" else {
    return invalid_command("\{invoked_name} does not accept arguments")
  }
  parsed_command(CommandFinish::{ })
}

///|
fn finish_command_spec() -> CommandSpec {
  CommandSpec::new(
    "finish",
    ["fin"],
    "finish",
    "Step out of the current function",
    parse_finish_command,
  )
}

///|
impl ReplCommand for CommandFinish with fn execute(_self, context) {
  execute_session_action(context, session => session.finish())
}
