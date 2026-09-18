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
  operation : @debugger.BreakpointOperation,
) -> CommandResult {
  let event = BreakpointManagedPresentation(
    context.session.manage_breakpoint(id, operation),
  ) catch {
    @debugger.BreakpointNotFound(id) =>
      BreakpointManagementFailurePresentation(BreakpointIdNotFound(id))
    @debugger.BreakpointManagementRejected(message) =>
      BreakpointManagementFailurePresentation(
        BreakpointManagementRefused(message),
      )
    @debugger.OperationNotAllowed(state~, action~) =>
      OperationNotAllowedPresentation(state, action)
    @debugger.AdapterFailure(message) => AdapterFailurePresentation(message)
    error => raise error
  }
  CommandResult::continuing(events=[event])
}
