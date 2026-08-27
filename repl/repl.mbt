///|
async fn command_result_from_line(
  context : ReplContext,
  line : StringView,
) -> CommandResult {
  match context.registry.parse_line(line) {
    RegistryCommand(command) => command.execute(context)
    RegistryInvalid(message) =>
      CommandResult::continuing(events=[
        UserErrorPresentation("Error: \{message}"),
      ])
    RegistryUnknown =>
      CommandResult::continuing(events=[
        UserErrorPresentation("Unknown command. Type 'help' for help."),
      ])
  }
}

///|
async fn apply_command_result(
  context : ReplContext,
  result : CommandResult,
) -> ReplControlFlow {
  context.render(result.events)
  match result.legacy_action {
    Some(action) => execute_legacy_action(context, action)
    None => ()
  }
  result.control
}

///|
async fn run_repl(
  editor : @readline.LineEditor,
  history : @readline.History,
  context : ReplContext,
) -> Unit {
  for ;; {
    let input = editor.read_line(prompt="(moondbg) ") catch {
      @readline.Interrupted => {
        println("")
        continue
      }
      error => raise error
    }
    match input {
      None => break
      Some(line) => {
        if line != "" {
          history.add(line)
        }
        let result = command_result_from_line(context, line)
        guard apply_command_result(context, result) is ContinueRepl else {
          return
        }
      }
    }
  }
}
