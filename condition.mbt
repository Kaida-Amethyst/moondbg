///|
priv struct CommandCondition {
  id : Int
  text : String
}

///|
fn condition_command_spec() -> CommandSpec {
  CommandSpec::new(
    "condition",
    [],
    "condition <id> [expression]",
    "Set a line breakpoint condition; omit expression to clear",
    (_, arguments) => {
      let end = command_word_end(arguments)
      guard parse_breakpoint_id(arguments[:end]) is Some(id) else {
        return invalid_command("condition requires a positive breakpoint id")
      }
      let text = arguments[end:].trim().to_owned()
      if !text.is_empty() {
        (@expression.IntCondition::parse(text) |> ignore) catch {
          @expression.ConditionError(message) => return invalid_command(message)
        }
      }
      parsed_command(CommandCondition::{ id, text, })
    },
  )
}

///|
impl ReplCommand for CommandCondition with fn execute(self, context) {
  let event = try {
    context.session.set_condition(self.id, self.text)
    ConditionChangedPresentation(
      self.id,
      context.session.condition_text(self.id),
    )
  } catch {
    @debugger.BreakpointNotFound(id) =>
      BreakpointManagementFailurePresentation(BreakpointIdNotFound(id))
    @debugger.BreakpointManagementRejected(message) =>
      UserErrorPresentation(message)
    @expression.ConditionError(message) => UserErrorPresentation(message)
    @debugger.OperationNotAllowed(state~, action~) =>
      OperationNotAllowedPresentation(state, action)
    @debugger.AdapterFailure(message) => AdapterFailurePresentation(message)
    error => raise error
  }
  CommandResult::continuing(events=[event])
}

///|
test "condition command validates its id and bounded comparison grammar" {
  let registry = default_command_registry()
  for text in ["condition 1", "condition 1 i>=-7", "  condition\t2\ti != 0  "] {
    assert_true(registry.parse_line(text) is RegistryCommand(_), msg=text)
  }
  for
    text in [
      "condition", "condition 0 i > 0", "condition -1", "condition 1 i = 0", "condition 1 i > 0 && j < 0",
      "condition 1 point.x == 3",
    ] {
    assert_true(registry.parse_line(text) is RegistryInvalid(_), msg=text)
  }
}
