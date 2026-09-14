///|
priv enum LiveInput {
  Client(String?)
  Adapter(Json)
  Failed(String)
}

///|
priv struct PendingRequest {
  client_seq : Int
  command : String
  deadline : Int64
  execution_revision : Int
}

///|
/// One target, one adapter, no restart or attach. Downstream object handles
/// stay opaque and session-scoped; only request/message sequences are mapped.
/// This protocol-facing path deliberately does not use the REPL's blocking
/// RunOutcome transactions. MoonBit variable semantics will need a separate
/// inspection seam before scopes/variables can be exposed here.
priv struct LiveSession {
  client : ConnectionSession
  transport : &@dap.DapTransport
  launch_seq : Int
  mut launch_answered : Bool
  pending : Map[Int, PendingRequest]
  mut next_seq : Int
  mut configured : Bool
  mut ready : Bool
  mut stopped : Bool
  mut execution_revision : Int
  mut pause_revision : Int?
  mut exited : Bool
  mut ended : Bool
  mut closing : Bool
  mut deadline : Int64?
}

///|
priv suberror LiveError {
  LiveError(String)
} derive(Debug)

///|
async fn LiveSession::request(
  self : LiveSession,
  client_seq : Int,
  command : String,
  arguments : Json,
) -> Unit {
  let seq = self.next_seq
  self.next_seq += 1
  self.pending.set(seq, {
    client_seq,
    command,
    deadline: @async.now() + 15000,
    execution_revision: self.execution_revision,
  })
  self.transport.send_message({
    "seq": seq,
    "type": "request",
    "command": command,
    "arguments": arguments,
  })
}

///|
async fn LiveSession::cancel_launch(
  self : LiveSession,
  writer : &@io.Writer,
  message : String,
) -> Unit {
  guard !self.launch_answered else { return }
  self.launch_answered = true
  send_client(
    writer,
    self.client.response(self.launch_seq, "launch", error=Some(message)),
  )
}
