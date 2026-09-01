///|
priv struct CommandUp {}

///|
fn parse_up_command(
  _invoked_name : StringView,
  arguments : StringView,
) -> CommandParseResult {
  guard arguments == "" else {
    return invalid_command("up does not accept arguments")
  }
  parsed_command(CommandUp::{ })
}

///|
fn up_command_spec() -> CommandSpec {
  CommandSpec::new(
    "up",
    [],
    "up",
    "Select the visible caller frame",
    parse_up_command,
  )
}

///|
impl ReplCommand for CommandUp with fn execute(_self, context) {
  execute_frame_selection(context, session => {
    session.select_visible_caller_frame()
  })
}
