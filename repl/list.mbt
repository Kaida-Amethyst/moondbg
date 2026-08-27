///|
priv struct CommandList {
  line_count : Int
}

///|
fn parse_list_count(arguments : StringView) -> CommandParseResult {
  guard arguments != "" else {
    return invalid_command("list count must be a positive integer")
  }
  let parsed_count = Some(@string.parse_int(arguments, base=10)) catch {
    _ => None
  }
  guard parsed_count is Some(count) && count > 0 else {
    return invalid_command("list count must be a positive integer")
  }
  parsed_command(CommandList::{ line_count: count, })
}

///|
fn parse_list_command(
  _invoked_name : StringView,
  arguments : StringView,
) -> CommandParseResult {
  guard arguments != "" else {
    return parsed_command(CommandList::{
      line_count: DEFAULT_SOURCE_LINE_COUNT,
    })
  }
  guard parse_command_invocation(arguments) is Some(option) else {
    return invalid_command("list only accepts -c <count> or --count <count>")
  }
  match option.name {
    "-c" | "--count" => parse_list_count(option.arguments)
    _ => invalid_command("list only accepts -c <count> or --count <count>")
  }
}

///|
fn list_command_spec() -> CommandSpec {
  CommandSpec::new(
    "list",
    [],
    "list [-c|--count <count>]",
    "Show source context (default: 5 lines)",
    parse_list_command,
  )
}

///|
impl ReplCommand for CommandList with fn execute(self, context) {
  guard context.session.last_stop_snapshot() is Some(snapshot) else {
    return CommandResult::continuing(events=[NoStoppedSourcePresentation])
  }
  CommandResult::continuing(events=[
    StopPresentation(snapshot),
    SourceViewPresentation(
      SourceView::from_stop(snapshot, line_count=self.line_count),
    ),
  ])
}
