///|
priv struct CommandLocals {}

///|
fn parse_locals_command(
  _invoked_name : StringView,
  arguments : StringView,
) -> CommandParseResult {
  guard arguments == "" else {
    return invalid_command("locals does not accept arguments")
  }
  parsed_command(CommandLocals::{ })
}

///|
fn locals_command_spec() -> CommandSpec {
  CommandSpec::new(
    "locals",
    [],
    "locals",
    "Show local variables in the selected frame",
    parse_locals_command,
  )
}

///|
impl ReplCommand for CommandLocals with fn execute(_self, context) {
  let snapshot = context.session.local_variables() catch {
    @moondbg.OperationNotAllowed(state~, action~) =>
      return CommandResult::continuing(events=[
        OperationNotAllowedPresentation(state, action),
      ])
    @moondbg.AdapterFailure(message) =>
      return CommandResult::continuing(events=[
        AdapterFailurePresentation(message),
      ])
    error => raise error
  }
  CommandResult::continuing(events=[LocalsPresentation(snapshot)])
}
