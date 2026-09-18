///|
priv struct CommandDown {}

///|
fn parse_down_command(
  _invoked_name : StringView,
  arguments : StringView,
) -> CommandParseResult {
  guard arguments == "" else {
    return invalid_command("down does not accept arguments")
  }
  parsed_command(CommandDown::{ })
}

///|
fn down_command_spec() -> CommandSpec {
  CommandSpec::new(
    "down",
    [],
    "down",
    "Select the visible callee frame",
    parse_down_command,
  )
}

///|
impl ReplCommand for CommandDown with fn execute(_self, context) {
  execute_frame_selection(context, session => {
    session.select_visible_callee_frame()
  })
}
