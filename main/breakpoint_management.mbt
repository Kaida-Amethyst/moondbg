///|
fn parse_breakpoint_id(arguments : StringView) -> Int? {
  guard arguments != "" && arguments.all(character => character is ('0'..='9')) else {
    return None
  }
  let id = Some(@string.parse_int(arguments, base=10)) catch { _ => None }
  match id {
    Some(id) if id > 0 => Some(id)
    _ => None
  }
}

///|
async fn execute_breakpoint_management(
  context : ReplContext,
  id : Int,
  operation : @moondbg.BreakpointOperation,
) -> CommandResult {
  let event = BreakpointManagedPresentation(
    context.session.manage_breakpoint(id, operation),
  ) catch {
    @moondbg.BreakpointNotFound(id) =>
      BreakpointManagementFailurePresentation(BreakpointIdNotFound(id))
    @moondbg.BreakpointManagementRejected(message) =>
      BreakpointManagementFailurePresentation(
        BreakpointManagementRefused(message),
      )
    @moondbg.OperationNotAllowed(state~, action~) =>
      OperationNotAllowedPresentation(state, action)
    @moondbg.AdapterFailure(message) => AdapterFailurePresentation(message)
    error => raise error
  }
  CommandResult::continuing(events=[event])
}
