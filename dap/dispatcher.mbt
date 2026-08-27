///|
pub enum RoutedMessage {
  Matched(DapResponse)
  BufferedResponse
  SessionEvent(DapEvent)
  AdapterRequest(DapAdapterRequest)
}

///|
priv struct DapInbox {
  responses : Map[Int, DapResponse]
}

///|
fn DapInbox::new() -> DapInbox {
  { responses: {}, }
}

///|
fn DapInbox::take_response(self : DapInbox, request_seq : Int) -> DapResponse? {
  guard self.responses.get(request_seq) is Some(response) else { return None }
  self.responses.remove(request_seq)
  Some(response)
}

///|
fn DapInbox::buffer_response(
  self : DapInbox,
  response : DapResponse,
) -> Unit raise DapClientError {
  guard self.responses.get(response.request_seq) is None else {
    raise DuplicateResponse(response.request_seq)
  }
  self.responses.set(response.request_seq, response)
}

///|
fn DapInbox::route(
  self : DapInbox,
  incoming : IncomingMessage,
  request_seq : Int,
) -> RoutedMessage raise DapClientError {
  match incoming {
    Response(response) if response.request_seq == request_seq =>
      Matched(response)
    Response(response) => {
      self.buffer_response(response)
      BufferedResponse
    }
    Event(event) => SessionEvent(event)
    Request(request) => AdapterRequest(request)
  }
}

///|
pub struct DapDispatcher {
  priv transport : DapTransport
  priv inbox : DapInbox
}

///|
pub async fn[X] DapDispatcher::start(
  group : @async.TaskGroup[X],
  adapter : String,
) -> DapDispatcher {
  { transport: DapTransport::start(group, adapter), inbox: DapInbox::new(), }
}

///|
pub async fn DapDispatcher::send_request(
  self : DapDispatcher,
  command : String,
  arguments : Json,
) -> Int {
  self.transport.send_request(command, arguments)
}

///|
pub async fn DapDispatcher::next_for_request(
  self : DapDispatcher,
  request_seq : Int,
) -> RoutedMessage {
  match self.inbox.take_response(request_seq) {
    Some(response) => return Matched(response)
    None => ()
  }
  let incoming = classify_message(self.transport.receive())
  guard incoming.seq() >= 0 else { raise InvalidSequence(incoming.seq()) }
  self.inbox.route(incoming, request_seq)
}

///|
pub async fn DapDispatcher::next(self : DapDispatcher) -> RoutedMessage {
  let incoming = classify_message(self.transport.receive())
  guard incoming.seq() >= 0 else { raise InvalidSequence(incoming.seq()) }
  self.inbox.route(incoming, -1)
}

///|
pub fn DapDispatcher::close(self : DapDispatcher) -> Unit {
  self.transport.close()
}
