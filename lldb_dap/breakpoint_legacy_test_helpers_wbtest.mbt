///|
// Test-only convenience for older add-operation scenarios. Product callers
// always supply a complete configuration through the domain synchronization port.
async fn LldbDapSession::install_source_breakpoint(
  self : LldbDapSession,
  breakpoint : LogicalSourceBreakpoint,
) -> @debugger.BreakpointSnapshot {
  let sources = self.source_breakpoints.copy()
  let functions = self.function_breakpoints.copy()
  sources.push(breakpoint)
  let result = self.synchronize_breakpoints(sources, functions) catch {
    error => {
      if self.execution is Some(execution) {
        self.recover_failed_execution(execution, try_disconnect=true) catch {
          _ => ()
        }
      }
      raise LldbDapBackendError::AdapterFailure(@debug.to_string(error))
    }
  }
  result
  .sources()
  .iter()
  .find_first(item => item.id() == breakpoint.id)
  .unwrap_or(breakpoint.pending_snapshot())
}

///|
// Test-only convenience for older add-operation scenarios. Product callers
// always supply a complete configuration through the domain synchronization port.
async fn LldbDapSession::install_function_breakpoint(
  self : LldbDapSession,
  breakpoint : LogicalFunctionBreakpoint,
) -> @debugger.FunctionBreakpointSnapshot {
  let sources = self.source_breakpoints.copy()
  let functions = self.function_breakpoints.copy()
  functions.push(breakpoint)
  let result = self.synchronize_breakpoints(sources, functions) catch {
    error => {
      if self.execution is Some(execution) {
        self.recover_failed_execution(execution, try_disconnect=true) catch {
          _ => ()
        }
      }
      raise LldbDapBackendError::AdapterFailure(@debug.to_string(error))
    }
  }
  result
  .functions()
  .iter()
  .find_first(item => item.id() == breakpoint.id)
  .unwrap_or(breakpoint.pending_snapshot())
}

///|
fn ExecutionBreakpointState::verify(
  self : ExecutionBreakpointState,
  breakpoint_id : Int,
  actual_line : Int?,
  dap_id : Int?,
  location_count? : Int? = None,
) -> Unit {
  self.outcomes.set(breakpoint_id, {
    actual_line,
    dap_id,
    location_count,
    status: AdapterVerified,
    locations: [],
  })
}
