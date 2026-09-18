///|
priv struct CommandEnable {
  id : Int
}

///|
fn parse_enable_command(
  _invoked_name : StringView,
  arguments : StringView,
) -> CommandParseResult {
  guard parse_breakpoint_id(arguments) is Some(id) else {
    return invalid_command("enable requires one positive decimal breakpoint ID")
  }
  parsed_command(CommandEnable::{ id, })
}

///|
fn enable_command_spec() -> CommandSpec {
  CommandSpec::new(
    "enable",
    [],
    "enable <id>",
    "Enable one logical breakpoint",
    parse_enable_command,
  )
}

///|
impl ReplCommand for CommandEnable with fn execute(self, context) {
  execute_breakpoint_management(context, self.id, @debugger.EnableBreakpoint)
}
