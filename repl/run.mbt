///|
priv struct CommandRun {}

///|
fn parse_run_command(
  invoked_name : StringView,
  arguments : StringView,
) -> CommandParseResult {
  guard arguments == "" else {
    return invalid_command("\{invoked_name} does not accept arguments")
  }
  parsed_command(CommandRun::{ })
}

///|
fn run_command_spec() -> CommandSpec {
  CommandSpec::new(
    "run",
    ["r"],
    "run",
    "Run or restart the program",
    parse_run_command,
  )
}

///|
impl ReplCommand for CommandRun with fn execute(_self, context) {
  execute_session_action(
    context,
    session => session.run(),
    restarting=context.session.state() is @moondbg.Stopped,
    report_breakpoints=true,
  )
}
