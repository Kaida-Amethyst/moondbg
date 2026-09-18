///|
priv struct CommandDisable {
  id : Int
}

///|
fn parse_disable_command(
  _invoked_name : StringView,
  arguments : StringView,
) -> CommandParseResult {
  guard parse_breakpoint_id(arguments) is Some(id) else {
    return invalid_command(
      "disable requires one positive decimal breakpoint ID",
    )
  }
  parsed_command(CommandDisable::{ id, })
}

///|
fn disable_command_spec() -> CommandSpec {
  CommandSpec::new(
    "disable",
    [],
    "disable <id>",
    "Disable one logical breakpoint",
    parse_disable_command,
  )
}

///|
impl ReplCommand for CommandDisable with fn execute(self, context) {
  execute_breakpoint_management(context, self.id, @debugger.DisableBreakpoint)
}
