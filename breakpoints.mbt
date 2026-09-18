///|
priv struct CommandBreakpoints {}

///|
fn parse_breakpoints_command(
  _invoked_name : StringView,
  arguments : StringView,
) -> CommandParseResult {
  guard arguments == "" else {
    return invalid_command("breakpoints does not accept arguments")
  }
  parsed_command(CommandBreakpoints::{ })
}

///|
fn breakpoints_command_spec() -> CommandSpec {
  CommandSpec::new(
    "breakpoints",
    [],
    "breakpoints",
    "List logical breakpoints and installation status",
    parse_breakpoints_command,
  )
}

///|
impl ReplCommand for CommandBreakpoints with fn execute(_self, context) {
  CommandResult::continuing(events=[
    BreakpointsPresentation(context.session.breakpoints()),
  ])
}
