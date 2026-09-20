///|
/// Shared native function breakpoint operations. The caller owns request
/// routing; no second transport reader or Python formatter is involved.
pub struct FunctionBreakpointDriver {
  priv request : async (String, Json) -> @dap.DapResponse
}

///|
pub struct InstalledFunctionBreakpoint {
  /// LLDB target breakpoint ID. LLDB-DAP uses this same target ID in its
  /// breakpoint events and stopped.hitBreakpointIds; it is not a request seq.
  id : Int
  location_count : Int
}

///|
pub fn FunctionBreakpointDriver::new(
  request : async (String, Json) -> @dap.DapResponse,
) -> FunctionBreakpointDriver {
  { request, }
}

///|
fn DebugExecution::function_driver(
  self : DebugExecution,
) -> FunctionBreakpointDriver {
  FunctionBreakpointDriver::new((command, args) => {
    self.request_allow_failure(command, args)
  })
}

///|
async fn FunctionBreakpointDriver::command(
  self : FunctionBreakpointDriver,
  command : String,
) -> String? {
  lldb_command_result(
    (self.request)("evaluate", { "expression": command, "context": "repl" }),
  )
}

///|
pub async fn FunctionBreakpointDriver::install(
  self : FunctionBreakpointDriver,
  selector : @debugger.FunctionBreakpointSelector,
) -> InstalledFunctionBreakpoint {
  let command = match selector {
    @debugger.ExactPhysicalFunction(name) => {
      // These arguments enter LLDB's command interpreter, not a shell. Still
      // restrict physical symbols before quoting; user text never goes here.
      guard !name.is_empty() &&
        name.iter().all(ch => ch is ('a'..='z' | 'A'..='Z' | '0'..='9' | '_')) else {
        raise @debugger.BreakpointSyncError::BreakpointSyncRejected(
          "Unsafe physical function name",
        )
      }
      "breakpoint set --name '\{name}'"
    }
    @debugger.MoonBitFunctionFamily(base) => {
      guard !base.is_empty() &&
        base.iter().all(ch => ch is ('a'..='z' | 'A'..='Z' | '0'..='9' | '_')) else {
        raise @debugger.BreakpointSyncError::BreakpointSyncRejected(
          "Unsafe mangled function name",
        )
      }
      function_family_breakpoint_command(base)
    }
  }
  guard self.command(command) is Some(result) &&
    LldbCreatedBreakpoint::parse(result) is Some(created) else {
    raise @debugger.BreakpointSyncError::BreakpointSyncUncertain(
      "lldb-dap did not confirm function breakpoint creation",
    )
  }
  { id: created.id, location_count: created.location_count, }
}

///|
pub async fn FunctionBreakpointDriver::remove(
  self : FunctionBreakpointDriver,
  id : Int,
) -> Unit {
  self.change(LldbBreakpointId(id), "delete")
}
