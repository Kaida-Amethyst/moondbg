///|
priv struct CommandDelete {
  id : Int
}

///|
fn parse_delete_command(
  _invoked_name : StringView,
  arguments : StringView,
) -> CommandParseResult {
  guard parse_breakpoint_id(arguments) is Some(id) else {
    return invalid_command("delete requires one positive decimal breakpoint ID")
  }
  parsed_command(CommandDelete::{ id, })
}

///|
fn delete_command_spec() -> CommandSpec {
  CommandSpec::new(
    "delete",
    [],
    "delete <id>",
    "Delete one logical breakpoint",
    parse_delete_command,
  )
}

///|
impl ReplCommand for CommandDelete with fn execute(self, context) {
  execute_breakpoint_management(context, self.id, @moondbg.DeleteBreakpoint)
}
