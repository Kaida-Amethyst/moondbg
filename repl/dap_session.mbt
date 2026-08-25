///|
priv suberror DapSessionError {
  InvalidMessage(Json)
  RequestFailed(command~ : String, message~ : String)
  UnsupportedAdapterRequest(String)
  AdapterTerminated
  BootstrapTimedOut
} derive(Debug)

///|
priv enum IncomingMessage {
  Event(String)
  Response(request_seq~ : Int, success~ : Bool, message~ : String?)
  Request(command~ : String)
}

///|
fn classify_message(message : Json) -> IncomingMessage raise DapSessionError {
  match message {
    { "type": String("event"), "event": String(name), .. } => Event(name)
    {
      "type": String("response"),
      "request_seq": Number(request_seq, ..),
      "success": True
      | False as success,
      ..
    } => {
      let detail = match message {
        { "message": String(detail), .. } => Some(detail)
        _ => None
      }
      Response(
        request_seq=request_seq.to_int(),
        success=success is True,
        message=detail,
      )
    }
    { "type": String("request"), "command": String(command), .. } =>
      Request(command~)
    _ => raise InvalidMessage(message)
  }
}

///|
fn check_response(
  response : IncomingMessage,
  request_seq : Int,
  command : String,
) -> Bool raise DapSessionError {
  match response {
    Response(request_seq=actual, success=true, ..) if actual == request_seq =>
      true
    Response(request_seq=actual, success=false, message~) if actual ==
      request_seq =>
      raise RequestFailed(
        command~,
        message=message.unwrap_or(
          "the adapter did not provide an error message",
        ),
      )
    _ => false
  }
}

///|
async fn wait_for_response(
  transport : DapTransport,
  request_seq : Int,
  command : String,
) -> Unit {
  for ;; {
    let incoming = classify_message(transport.receive())
    if check_response(incoming, request_seq, command) {
      return
    }
    match incoming {
      Event("terminated" | "exited") => raise AdapterTerminated
      Request(command~) => raise UnsupportedAdapterRequest(command)
      _ => ()
    }
  }
}

///|
async fn bootstrap_session(
  transport : DapTransport,
  executable : String,
) -> Unit {
  let initialize_seq = transport.send_request("initialize", {
    "clientID": "moondbg",
    "clientName": "moondbg",
    "adapterID": "lldb-dap",
    "pathFormat": "path",
    "linesStartAt1": true,
    "columnsStartAt1": true,
  })
  wait_for_response(transport, initialize_seq, "initialize")
  let launch_seq = transport.send_request("launch", {
    "program": executable,
    "stopOnEntry": true,
  })
  let mut launch_completed = false
  let mut configuration_seq : Int? = None
  let mut configuration_completed = false
  let mut stopped = false
  while !(launch_completed && configuration_completed && stopped) {
    let incoming = classify_message(transport.receive())
    match incoming {
      Event("initialized") if configuration_seq is None =>
        configuration_seq = Some(
          transport.send_request("configurationDone", {}),
        )
      Event("stopped") => stopped = true
      Event("terminated" | "exited") => raise AdapterTerminated
      Request(command~) => raise UnsupportedAdapterRequest(command)
      _ => ()
    }
    if check_response(incoming, launch_seq, "launch") {
      launch_completed = true
    }
    if configuration_seq is Some(seq) &&
      check_response(incoming, seq, "configurationDone") {
      configuration_completed = true
    }
  }
}

///|
async fn disconnect_session(transport : DapTransport) -> Unit {
  let seq = transport.send_request("disconnect", { "terminateDebuggee": true })
  for ;; {
    let incoming = transport.receive() catch {
      AdapterClosed => return
      error => raise error
    }
    let incoming = classify_message(incoming)
    if check_response(incoming, seq, "disconnect") {
      return
    }
    match incoming {
      Event("terminated" | "exited") => return
      Request(command~) => raise UnsupportedAdapterRequest(command)
      _ => ()
    }
  }
}
