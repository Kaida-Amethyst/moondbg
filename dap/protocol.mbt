///|
pub struct DapRequest {
  priv command : String
  priv arguments : Json
}

///|
pub fn DapRequest::new(command : String, arguments : Json) -> DapRequest {
  { command, arguments, }
}

///|
pub fn DapRequest::command(self : DapRequest) -> String {
  self.command
}

///|
pub fn DapRequest::arguments(self : DapRequest) -> Json {
  self.arguments
}

///|
pub(all) enum DapStepKind {
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
pub fn stepping_request(
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
pub fn supports_stepping_granularity(capabilities : Json) -> Bool {
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
pub struct DapEvent {
  priv seq : Int
  priv name : String
  priv body : Json
}

///|
pub fn DapEvent::name(self : DapEvent) -> String {
  self.name
}

///|
pub fn DapEvent::body(self : DapEvent) -> Json {
  self.body
}

///|
// The raw response body is interpreted by the adapter layer.
#warnings("-unused_field")
pub struct DapResponse {
  priv seq : Int
  priv request_seq : Int
  priv command : String?
  priv success : Bool
  priv message : String?
  priv body : Json
}

///|
pub fn DapResponse::command(self : DapResponse) -> String? {
  self.command
}

///|
pub fn DapResponse::success(self : DapResponse) -> Bool {
  self.success
}

///|
pub fn DapResponse::message(self : DapResponse) -> String? {
  self.message
}

///|
pub fn DapResponse::body(self : DapResponse) -> Json {
  self.body
}

///|
// Adapter request arguments are retained for future runInTerminal support.
#warnings("-unused_field")
pub struct DapAdapterRequest {
  priv seq : Int
  priv command : String
  priv arguments : Json
}

///|
pub fn DapAdapterRequest::command(self : DapAdapterRequest) -> String {
  self.command
}

///|
pub enum IncomingMessage {
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
pub fn classify_message(message : Json) -> IncomingMessage raise DapClientError {
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
