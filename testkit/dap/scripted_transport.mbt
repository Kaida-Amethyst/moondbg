///|
/// One deterministic receive operation for an in-memory DAP transport.
pub(all) enum ScriptedInput {
  ScriptedMessage(Json)
  ScriptedClosed
  ScriptedFailure(String)
}

///|
pub(all) suberror ScriptedTransportError {
  ScriptedTransportFailure(String)
} derive(Debug)

///|
pub extend ScriptedTransportError with @debug.Debug::{to_repr}

///|
pub struct ScriptedTransport {
  priv inputs : Array[ScriptedInput]
  priv sent : Array[Json]
  priv mut input_index : Int
  priv mut closed : Bool
}

///|
pub fn ScriptedTransport::new(
  inputs : Array[ScriptedInput],
) -> ScriptedTransport {
  { inputs, sent: [], input_index: 0, closed: false, }
}

///|
pub fn ScriptedTransport::as_transport(
  self : ScriptedTransport,
) -> &@dap_protocol.DapTransport {
  self
}

///|
pub fn ScriptedTransport::sent_messages(
  self : ScriptedTransport,
) -> Array[Json] {
  self.sent.copy()
}

///|
pub fn ScriptedTransport::remaining_inputs(self : ScriptedTransport) -> Int {
  self.inputs.length() - self.input_index
}

///|
pub fn ScriptedTransport::is_closed(self : ScriptedTransport) -> Bool {
  self.closed
}

///|
impl @dap_protocol.DapTransport for ScriptedTransport with fn send_message(
  self,
  message,
) {
  guard !self.closed else { raise @dap_protocol.AdapterClosed }
  self.sent.push(message)
}

///|
impl @dap_protocol.DapTransport for ScriptedTransport with fn receive_message(
  self,
) {
  guard !self.closed && self.input_index < self.inputs.length() else {
    raise @dap_protocol.AdapterClosed
  }
  let input = self.inputs[self.input_index]
  self.input_index = self.input_index + 1
  match input {
    ScriptedMessage(message) => message
    ScriptedClosed => raise @dap_protocol.AdapterClosed
    ScriptedFailure(message) => raise ScriptedTransportFailure(message)
  }
}

///|
impl @dap_protocol.DapTransport for ScriptedTransport with fn close(self) {
  self.closed = true
}
