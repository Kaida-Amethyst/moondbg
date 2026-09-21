///|
priv suberror DapSessionError {
  InvalidMessage(Json)
  InvalidIndexedCollectionValue(String)
  InvalidIndexedElementValue(String)
  InvalidEnumValue(String)
  StackPageTooLarge(requested~ : Int, actual~ : Int)
  DuplicateStackFrameId(Int)
  DuplicatePhysicalFrameIndex(Int)
  NonContiguousStackRequest(expected~ : Int, actual~ : Int)
  OverlappingStackRequest(loaded_end~ : Int, requested_end~ : Int)
  StaleStackPage(expected_epoch~ : Int, actual_epoch~ : Int?)
  StaleVariableResult(expected_epoch~ : Int, expected_frame~ : Int)
  RequestFailed(command~ : String, message~ : String)
  UnsupportedAdapterRequest(String)
  MismatchedResponseCommand(expected~ : String, actual~ : String)
  InvalidSessionTransition(state~ : DapSessionState, action~ : String)
} derive(Debug)

///|
priv suberror LldbDapBackendError {
  OperationNotAllowed(state~ : DapSessionState, action~ : String)
  AdapterFailure(String)
} derive(Debug)

///|
fn validate_response(
  response : @dap.DapResponse,
  command : String,
) -> @dap.DapResponse raise DapSessionError {
  guard response.command() is None || response.command() == Some(command) else {
    raise MismatchedResponseCommand(
      expected=command,
      actual=response.command().unwrap(),
    )
  }
  guard response.success() else {
    raise RequestFailed(
      command~,
      message=response
        .message()
        .unwrap_or("the adapter did not provide an error message"),
    )
  }
  response
}

///|
fn validate_response_command(
  response : @dap.DapResponse,
  command : String,
) -> @dap.DapResponse raise DapSessionError {
  guard response.command() is None || response.command() == Some(command) else {
    raise MismatchedResponseCommand(
      expected=command,
      actual=response.command().unwrap(),
    )
  }
  response
}

///|
priv enum ExecutionResumeKind {
  ContinueExecution
  StepExecution(@dap.DapStepKind)
}

///|
fn ExecutionResumeKind::action(self : ExecutionResumeKind) -> String {
  match self {
    ContinueExecution => "continue execution"
    StepExecution(@dap.DapNext) => "step over"
    StepExecution(@dap.DapStepIn) => "step into"
    StepExecution(@dap.DapStepOut) => "step out"
  }
}

///|
fn ExecutionResumeKind::request(
  self : ExecutionResumeKind,
  thread_id : Int,
  capabilities : Json,
) -> @dap.DapRequest {
  match self {
    ContinueExecution =>
      @dap.DapRequest::new("continue", {
        "threadId": thread_id,
        "singleThread": false,
      })
    StepExecution(kind) =>
      @dap.stepping_request(
        kind,
        thread_id,
        supports_stepping_granularity=@dap.supports_stepping_granularity(
          capabilities,
        ),
      )
  }
}

///|
// Owns adapter-scoped resources and protocol state for one execution.
priv struct DebugExecution {
  dispatcher : @dap.DapDispatcher
  machine : DapSessionMachine
  mut capabilities : Json
  mut stop_reason : String
  mut stop_body : Json
  conditions : BreakpointConditions
  mut exit_code : Int?
  mut stack_snapshot : @debugger.StackSnapshot?
  variable_cache : StopVariableCache
  breakpoint_state : ExecutionBreakpointState
  pending_output : Array[@debugger.DebugOutput]
}

///|
fn DebugExecution::state(self : DebugExecution) -> DapSessionState {
  self.machine.state
}

///|
/// Maps the application-owned logical thread selection to the temporary DAP
/// thread id for this execution. Only the initial selection exists until the
/// application exposes thread navigation.
fn DebugExecution::selected_thread_id(
  self : DebugExecution,
  selection : @debugger.ThreadSelection,
  action : String,
) -> Int raise LldbDapBackendError {
  guard self.machine.state is Stopped &&
    selection.index() == 0 &&
    self.machine.selected_thread_id() is Some(thread_id) else {
    raise LldbDapBackendError::OperationNotAllowed(
      state=self.machine.state,
      action~,
    )
  }
  thread_id
}

///|
/// Maps the application-owned logical frame selection to the current
/// execution's temporary DAP frame id.
fn DebugExecution::selected_frame_id(
  self : DebugExecution,
  thread : @debugger.ThreadSelection,
  frame : @debugger.FrameSelection,
  action : String,
) -> Int raise LldbDapBackendError {
  self.selected_thread_id(thread, action) |> ignore
  guard self.machine.frame_id(frame.index()) is Some(frame_id) else {
    raise LldbDapBackendError::OperationNotAllowed(
      state=self.machine.state,
      action~,
    )
  }
  frame_id
}

///|
fn DebugExecution::accept_event(
  self : DebugExecution,
  event : @dap.DapEvent,
) -> Unit raise DapSessionError {
  if output_from_event(event) is Some(output) {
    self.pending_output.push(output)
  }
  match event.name() {
    "stopped" => {
      self.stop_body = event.body()
      self.stop_reason = match event.body() {
        // LLDB descriptions contain physical ids such as "breakpoint 3.1".
        // They must not look like the stable logical ids used by REPL commands.
        { "reason": String("breakpoint"), .. } => "breakpoint"
        { "description": String(description), .. } => description
        { "reason": String(reason), .. } => reason
        _ => "stopped"
      }
      self.stack_snapshot = None
    }
    "exited" => {
      self.exit_code = match event.body() {
        { "exitCode": Number(code, ..), .. } => Some(code.to_int())
        _ => None
      }
      self.stack_snapshot = None
    }
    "terminated" => self.stack_snapshot = None
    _ => ()
  }
  self.machine.accept_event(event)
  match event.name() {
    "stopped" =>
      if self.machine.current_stop_epoch() is Some(epoch) {
        self.variable_cache.reset(epoch)
      }
    "exited" | "terminated" => self.variable_cache.reset(0)
    _ => ()
  }
}

///|
async fn DebugExecution::wait_for_response_inner(
  self : DebugExecution,
  request_seq : Int,
  command : String,
  terminal_event_completes? : Bool = false,
) -> @dap.DapResponse? {
  for ;; {
    let routed = self.dispatcher.next_for_request(request_seq) catch {
      @dap.AdapterClosed => {
        if terminal_event_completes {
          self.machine.finish()
          return None
        }
        raise @dap.AdapterClosed
      }
      error => raise error
    }
    match routed {
      @dap.Matched(response) =>
        return Some(validate_response_command(response, command))
      @dap.BufferedResponse => continue
      @dap.SessionEvent(event) => {
        self.accept_event(event)
        if terminal_event_completes &&
          (event.name() == "exited" || event.name() == "terminated") {
          return None
        }
      }
      @dap.AdapterRequest(request) =>
        raise UnsupportedAdapterRequest(request.command())
    }
  }
}

///|
async fn DebugExecution::request(
  self : DebugExecution,
  command : String,
  arguments : Json,
) -> @dap.DapResponse {
  let seq = self.dispatcher.send_request(command, arguments)
  guard self.wait_for_response(seq, command) is Some(response) else {
    raise RequestFailed(command~, message="adapter exited before responding")
  }
  validate_response(response, command)
}

///|
/// Sends a request whose unsuccessful DAP response has domain meaning to the
/// caller. Transport loss and a mismatched response remain protocol errors.
async fn DebugExecution::request_allow_failure(
  self : DebugExecution,
  command : String,
  arguments : Json,
) -> @dap.DapResponse {
  let seq = self.dispatcher.send_request(command, arguments)
  guard self.wait_for_response(seq, command) is Some(response) else {
    raise RequestFailed(command~, message="adapter exited before responding")
  }
  validate_response_command(response, command)
}

///|
async fn DebugExecution::wait_until_stable(self : DebugExecution) -> Unit {
  while self.machine.state is Running {
    let routed = self.dispatcher.next() catch {
      @dap.AdapterClosed => {
        if self.machine.state is Exited {
          return
        }
        raise @dap.AdapterClosed
      }
      error => raise error
    }
    match routed {
      @dap.Matched(_) => continue
      @dap.BufferedResponse => continue
      @dap.SessionEvent(event) => self.accept_event(event)
      @dap.AdapterRequest(request) =>
        raise UnsupportedAdapterRequest(request.command())
    }
  }
}

///|
async fn DebugExecution::complete_execution(
  self : DebugExecution,
  filter_conditions? : Bool = true,
) -> @debugger.RunOutcome {
  for ;; {
    self.wait_until_stable()
    match self.machine.state {
      Stopped => {
        let snapshot = self.build_stop_snapshot()
        if filter_conditions &&
          snapshot.reason() != "MoonBit panic" &&
          self.conditions.for_stop(self.stop_body) is Some(conditions) &&
          self.machine.frame_id(0) is Some(frame) {
          let result = @async.with_timeout(12000, () => {
            self.variable_inspector().test_conditions(frame, conditions)
          }) catch {
            error => {
              if @async.is_cancellation_error(error) {
                raise error
              }
              Err(
                "Could not evaluate breakpoint condition: \{@debug.to_string(error)}",
              )
            }
          }
          match result {
            Ok(false) => {
              let thread = self.resolve_stopped_thread()
              self.machine.mark_resumed()
              self.stack_snapshot = None
              self.variable_cache.reset(0)
              self.request("continue", {
                "threadId": thread,
                "singleThread": false,
              })
              |> ignore
              continue
            }
            Err(message) =>
              return @debugger.RunOutcome::stopped(
                @debugger.StopSnapshot::new(
                  "breakpoint condition error",
                  snapshot.function_name(),
                  snapshot.source_path(),
                  snapshot.line(),
                  snapshot.column(),
                  notice=Some(message),
                ),
              )
            Ok(true) => ()
          }
        }
        return @debugger.RunOutcome::stopped(snapshot)
      }
      Exited => return @debugger.RunOutcome::exited(self.exit_code)
      state =>
        raise InvalidSessionTransition(
          state~,
          action="complete execution transaction",
        )
    }
  }
}

///|
async fn DebugExecution::resume_transaction(
  self : DebugExecution,
  request : @dap.DapRequest,
  filter_conditions? : Bool = true,
) -> @debugger.RunOutcome {
  errdefer self.machine.fail("\{request.command()} transaction failed")
  self.machine.mark_resumed()
  self.stack_snapshot = None
  self.variable_cache.reset(0)
  self.request(request.command(), request.arguments()) |> ignore
  self.complete_execution(filter_conditions~)
}

///|
async fn DebugExecution::resume_execution(
  self : DebugExecution,
  kind : ExecutionResumeKind,
  thread : @debugger.ThreadSelection,
) -> @debugger.RunOutcome {
  let thread_id = self.selected_thread_id(thread, kind.action())
  let request = kind.request(thread_id, self.capabilities)
  self.resume_transaction(request, filter_conditions=kind is ContinueExecution) catch {
    error => raise LldbDapBackendError::AdapterFailure(@debug.to_string(error))
  }
}

///|
async fn DebugExecution::wait_for_response(
  self : DebugExecution,
  request_seq : Int,
  command : String,
  terminal_event_completes? : Bool = false,
) -> @dap.DapResponse? {
  errdefer self.machine.fail("DAP request failed")
  self.wait_for_response_inner(request_seq, command, terminal_event_completes~)
}

///|
/// Requests a graceful shutdown after a target has been created. A `Ready`
/// session owns only an idle adapter, so closing its transport is sufficient.
async fn DebugExecution::disconnect(self : DebugExecution) -> Unit {
  guard !(self.machine.state is Exited) else { return }
  if self.machine.state is Ready {
    self.machine.finish()
    return
  }
  let seq = self.dispatcher.send_request("disconnect", {
    "terminateDebuggee": true,
  })
  self.wait_for_response(seq, "disconnect", terminal_event_completes=true)
  |> ignore
  self.machine.finish()
}

///|
/// Closes the DAP pipes and cancels the adapter process if it is still alive.
fn DebugExecution::close(self : DebugExecution) -> Unit {
  self.dispatcher.close()
  self.machine.finish()
}
