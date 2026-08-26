///|
priv suberror DapSessionError {
  InvalidMessage(Json)
  RequestFailed(command~ : String, message~ : String)
  UnsupportedAdapterRequest(String)
  DuplicateResponse(Int)
  InvalidSequence(Int)
  MismatchedResponseCommand(expected~ : String, actual~ : String)
  InvalidSessionTransition(state~ : DebugSessionState, action~ : String)
} derive(Debug)

///|
fn validate_response(
  response : DapResponse,
  command : String,
) -> DapResponse raise DapSessionError {
  guard response.command is None || response.command == Some(command) else {
    raise MismatchedResponseCommand(
      expected=command,
      actual=response.command.unwrap(),
    )
  }
  guard response.success else {
    raise RequestFailed(
      command~,
      message=response.message.unwrap_or(
        "the adapter did not provide an error message",
      ),
    )
  }
  response
}

///|
/// Owns the lldb-dap process, protocol dispatcher, and debugger state for one
/// moondbg REPL session.
#warnings("-unused_field")
pub struct DebugSession {
  priv dispatcher : DapDispatcher
  priv machine : DebugSessionMachine
  priv executable : String
  priv events : Array[DapEvent]
}

///|
/// Starts lldb-dap without creating a target. The returned session is in
/// `Ready`; a later `run` command will begin the only execution epoch.
pub async fn[X] DebugSession::start(
  group : @async.TaskGroup[X],
  adapter : String,
  executable : String,
) -> DebugSession {
  let dispatcher = DapDispatcher::start(group, adapter)
  { dispatcher, machine: DebugSessionMachine::new(), executable, events: [], }
}

///|
/// Returns the current stable or transitional debugger state.
pub fn DebugSession::state(self : DebugSession) -> DebugSessionState {
  self.machine.state
}

///|
fn DebugSession::accept_event(
  self : DebugSession,
  event : DapEvent,
) -> Unit raise DapSessionError {
  self.machine.accept_event(event)
  self.events.push(event)
}

///|
async fn DebugSession::wait_for_response_inner(
  self : DebugSession,
  request_seq : Int,
  command : String,
  terminal_event_completes? : Bool = false,
) -> DapResponse? {
  for ;; {
    let routed = self.dispatcher.next_for_request(request_seq) catch {
      AdapterClosed => {
        if terminal_event_completes {
          self.machine.finish()
          return None
        }
        raise AdapterClosed
      }
      error => raise error
    }
    match routed {
      Matched(response) => return Some(validate_response(response, command))
      BufferedResponse => continue
      SessionEvent(event) => {
        self.accept_event(event)
        if terminal_event_completes &&
          (event.name == "exited" || event.name == "terminated") {
          return None
        }
      }
      AdapterRequest(request) =>
        raise UnsupportedAdapterRequest(request.command)
    }
  }
}

///|
async fn DebugSession::wait_for_response(
  self : DebugSession,
  request_seq : Int,
  command : String,
  terminal_event_completes? : Bool = false,
) -> DapResponse? {
  errdefer self.machine.fail("DAP request failed")
  self.wait_for_response_inner(request_seq, command, terminal_event_completes~)
}

///|
/// Requests a graceful shutdown after a target has been created. A `Ready`
/// session owns only an idle adapter, so closing its transport is sufficient.
pub async fn DebugSession::disconnect(self : DebugSession) -> Unit {
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
pub fn DebugSession::close(self : DebugSession) -> Unit {
  self.dispatcher.close()
  self.machine.finish()
}
