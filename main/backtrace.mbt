///|
priv struct CommandBacktrace {
  show_all : Bool
}

///|
fn parse_backtrace_command(
  _invoked_name : StringView,
  arguments : StringView,
) -> CommandParseResult {
  match arguments {
    "" => parsed_command(CommandBacktrace::{ show_all: false, })
    "--all" => parsed_command(CommandBacktrace::{ show_all: true, })
    _ => invalid_command("backtrace only accepts --all")
  }
}

///|
fn backtrace_command_spec() -> CommandSpec {
  CommandSpec::new(
    "backtrace",
    ["bt"],
    "backtrace [--all]",
    "Show the current thread stack",
    parse_backtrace_command,
  )
}

///|
impl ReplCommand for CommandBacktrace with fn execute(self, context) {
  let stack = context.session.complete_stack_snapshot() catch {
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
  CommandResult::continuing(events=[
    BacktracePresentation(
      BacktraceView::from_stack(
        stack,
        context.session.selected_frame().map(frame => frame.index()),
        show_all=self.show_all,
      ),
    ),
  ])
}
