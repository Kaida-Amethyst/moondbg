///|
priv struct CommandHelp {}

///|
fn parse_help_command(
  _invoked_name : StringView,
  arguments : StringView,
) -> CommandParseResult {
  guard arguments == "" else {
    return invalid_command("help does not accept arguments")
  }
  parsed_command(CommandHelp::{ })
}

///|
fn help_command_spec() -> CommandSpec {
  CommandSpec::new("help", [], "help", "Show this help", parse_help_command)
}

///|
impl ReplCommand for CommandHelp with fn execute(_self, context) {
  CommandResult::continuing(events=[
    HelpPresentation(context.registry.help_entries()),
  ])
}
