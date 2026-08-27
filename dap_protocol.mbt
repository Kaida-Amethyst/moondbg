///|
priv struct DapRequest {
  command : String
  arguments : Json
}

///|
priv enum DapStepKind {
  DapNext
  DapStepIn
  DapStepOut
}

///|
fn DapStepKind::command(self : DapStepKind) -> String {
  match self {
    DapNext => "next"
    DapStepIn => "stepIn"
    DapStepOut => "stepOut"
  }
}

///|
fn stepping_request(
  kind : DapStepKind,
  thread_id : Int,
  supports_stepping_granularity~ : Bool,
) -> DapRequest {
  let arguments : Json = if supports_stepping_granularity {
    { "threadId": thread_id, "granularity": "line" }
  } else {
    { "threadId": thread_id }
  }
  { command: kind.command(), arguments, }
}

///|
fn supports_stepping_granularity(capabilities : Json) -> Bool {
  capabilities is { "supportsSteppingGranularity": True, .. }
}

///|
fn request_message(seq : Int, request : DapRequest) -> Json {
  {
    "seq": seq,
    "type": "request",
    "command": request.command,
    "arguments": request.arguments,
  }
}

///|
priv struct DapEvent {
  seq : Int
  name : String
  body : Json
}

///|
// The response body is consumed by commands added in P4 and P5.
#warnings("-unused_field")
priv struct DapResponse {
  seq : Int
  request_seq : Int
  command : String?
  success : Bool
  message : String?
  body : Json
}

///|
// Adapter request arguments are retained for future runInTerminal support.
#warnings("-unused_field")
priv struct DapAdapterRequest {
  seq : Int
  command : String
  arguments : Json
}

///|
priv enum IncomingMessage {
  Event(DapEvent)
  Response(DapResponse)
  Request(DapAdapterRequest)
}

///|
fn IncomingMessage::seq(self : IncomingMessage) -> Int {
  match self {
    Event(event) => event.seq
    Response(response) => response.seq
    Request(request) => request.seq
  }
}

///|
fn message_body(message : Json) -> Json {
  match message {
    { "body": body, .. } => body
    _ => null
  }
}

///|
fn message_arguments(message : Json) -> Json {
  match message {
    { "arguments": arguments, .. } => arguments
    _ => null
  }
}

///|
fn response_command(message : Json) -> String? {
  match message {
    { "command": String(command), .. } => Some(command)
    _ => None
  }
}

///|
fn response_message(message : Json) -> String? {
  match message {
    { "message": String(detail), .. } => Some(detail)
    _ => None
  }
}

///|
fn classify_message(message : Json) -> IncomingMessage raise DapSessionError {
  match message {
    {
      "seq": Number(seq, ..),
      "type": String("event"),
      "event": String(name),
      ..
    } => Event({ seq: seq.to_int(), name, body: message_body(message), })
    {
      "seq": Number(seq, ..),
      "type": String("response"),
      "request_seq": Number(request_seq, ..),
      "success": True
      | False as success,
      ..
    } =>
      Response({
        seq: seq.to_int(),
        request_seq: request_seq.to_int(),
        command: response_command(message),
        success: success is True,
        message: response_message(message),
        body: message_body(message),
      })
    {
      "seq": Number(seq, ..),
      "type": String("request"),
      "command": String(command),
      ..
    } =>
      Request({
        seq: seq.to_int(),
        command,
        arguments: message_arguments(message),
      })
    _ => raise InvalidMessage(message)
  }
}
