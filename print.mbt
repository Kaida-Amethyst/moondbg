///|
priv struct CommandPrint {
  path : @debugger.VariablePath
}

///|
fn parse_variable_path(arguments : StringView) -> @debugger.VariablePath? {
  @debugger.VariablePath::parse(arguments)
}

///|
fn parse_print_command(
  _invoked_name : StringView,
  arguments : StringView,
) -> CommandParseResult {
  guard arguments != "" else {
    return invalid_command("print requires a variable path")
  }
  guard parse_variable_path(arguments) is Some(path) else {
    return invalid_command(
      "print only accepts variable paths with fields, non-negative indices, or a terminal [start:end] content range",
    )
  }
  parsed_command(CommandPrint::{ path, })
}

///|
fn print_command_spec() -> CommandSpec {
  CommandSpec::new(
    "print",
    ["p"],
    "print <path>",
    "Show a variable path or String/Bytes [start:end] range",
    parse_print_command,
  )
}

///|
impl ReplCommand for CommandPrint with fn execute(self, context) {
  let events : Array[PresentationEvent] = []
  let result = context.session.find_variable(self.path) catch {
    @debugger.NoFrameSelected =>
      return CommandResult::continuing(events=[
        FrameSelectionFailurePresentation(CurrentFrameUnavailable),
      ])
    @debugger.OperationNotAllowed(state~, action~) => {
      events.push(OperationNotAllowedPresentation(state, action))
      return CommandResult::continuing(events~)
    }
    @debugger.AdapterFailure(message) => {
      append_debuggee_output(events, context.session)
      events.push(AdapterFailurePresentation(message))
      return CommandResult::continuing(events~)
    }
    error => raise error
  }
  append_debuggee_output(events, context.session)
  match result {
    @debugger.VariableFound(variable) =>
      events.push(VariablePresentation(variable))
    @debugger.VariableLookupFailed(failure) =>
      events.push(VariableLookupFailurePresentation(failure))
  }
  CommandResult::continuing(events~)
}
