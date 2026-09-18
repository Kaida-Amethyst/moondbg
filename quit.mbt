///|
/// A concrete immutable command for terminating the REPL.
priv struct CommandQuit {}

///|
fn parse_quit_command(
  invoked_name : StringView,
  arguments : StringView,
) -> CommandParseResult {
  guard invoked_name != "q" || arguments == "" else {
    return invalid_command("q does not accept arguments")
  }
  parsed_command(CommandQuit::{ })
}

///|
fn quit_command_spec() -> CommandSpec {
  CommandSpec::new(
    "quit",
    ["q", "exit"],
    "quit",
    "Exit moondbg",
    parse_quit_command,
  )
}

///|
impl ReplCommand for CommandQuit with fn execute(_self, _context) {
  CommandResult::exiting()
}
