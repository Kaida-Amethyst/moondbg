///|
async fn[X] DebugExecution::prepare(
  group : @async.TaskGroup[X],
  adapter : String,
) -> DebugExecution {
  let dispatcher = @dap.DapDispatcher::start(group, adapter)
  let execution = {
    dispatcher,
    machine: DapSessionMachine::new(),
    capabilities: null,
    stop_reason: "stopped",
    exit_code: None,
    variable_cache: StopVariableCache::new(),
    breakpoint_state: ExecutionBreakpointState::new(),
    pending_output: [],
  }
  errdefer execution.close()
  let initialize = execution.request("initialize", {
    "adapterID": "lldb",
    "clientID": "moondbg",
    "clientName": "moondbg",
    "columnsStartAt1": true,
    "linesStartAt1": true,
    "pathFormat": "path",
    "supportsRunInTerminalRequest": false,
    "supportsVariableType": true,
  })
  execution.capabilities = initialize.body()
  execution
}

///|
/// Starts preparing lldb-dap in the background without creating a target.
/// Local REPL commands can use the returned session immediately; a later
/// `run` waits for and consumes this exact preparation result.
fn[X] LldbDapSession::start(
  group : @async.TaskGroup[X],
  adapter : String,
  preparation_timeout_ms? : Int = 10000,
) -> LldbDapSession {
  let spawn_preparation = () => {
    group.spawn(allow_failure=true, () => {
      DebugExecution::prepare(group, adapter)
    })
  }
  {
    breakpoints: [],
    spawn_preparation,
    preparation: Some(spawn_preparation()),
    preparation_timeout_ms,
    execution: None,
    detached_state: Ready,
    last_breakpoint_snapshots: Map([]),
    pending_output: [],
  }
}

///|
async fn DebugExecution::wait_for_initialized(
  self : DebugExecution,
  launch_seq : Int,
) -> @dap.DapResponse? {
  let mut launch_response : @dap.DapResponse? = None
  while self.machine.state is Preparing {
    match self.dispatcher.next_for_request(launch_seq) {
      @dap.Matched(response) =>
        launch_response = Some(validate_response(response, "launch"))
      @dap.BufferedResponse => continue
      @dap.SessionEvent(event) => self.accept_event(event)
      @dap.AdapterRequest(request) =>
        raise UnsupportedAdapterRequest(request.command())
    }
  }
  launch_response
}

///|
async fn DebugExecution::run_transaction(
  self : DebugExecution,
  executable : String,
  breakpoints : Array[LogicalBreakpoint],
) -> @moondbg.RunOutcome {
  errdefer self.machine.fail("run transaction failed")
  self.machine.begin_execution()
  let launch_seq = self.dispatcher.send_request("launch", {
    "program": executable,
    "stopOnEntry": false,
  })
  let mut launch_response = self.wait_for_initialized(launch_seq)
  if self.machine.state is Exited {
    return @moondbg.RunOutcome::exited(self.exit_code)
  }
  self.configure_breakpoints(breakpoints)
  self.machine.mark_running()
  self.request("configurationDone", {}) |> ignore
  if launch_response is None {
    launch_response = self.wait_for_response(launch_seq, "launch")
  }
  if launch_response is Some(response) {
    validate_response(response, "launch") |> ignore
  }
  self.complete_execution()
}

///|
async fn DebugExecution::run(
  self : DebugExecution,
  executable : String,
  breakpoints : Array[LogicalBreakpoint],
) -> @moondbg.RunOutcome {
  guard self.machine.state is Ready else {
    raise LldbDapBackendError::OperationNotAllowed(
      state=self.machine.state,
      action="run the program",
    )
  }
  self.run_transaction(executable, breakpoints) catch {
    error => raise LldbDapBackendError::AdapterFailure(@debug.to_string(error))
  }
}
