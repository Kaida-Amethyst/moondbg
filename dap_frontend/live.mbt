///|
priv enum LiveInput {
  Client(String?)
  Prepared(Result[Json, String])
  BuildOutput(String, String)
  Adapter(Json)
  Failed(String)
  InspectRead(Int, String, Json, @async.Queue[Json])
  InspectDone(Int, Result[Array[@lldb_dap.VariableNode], String])
}

///|
priv struct PendingRequest {
  client_seq : Int
  command : String
  deadline : Int64
  execution_revision : Int
  inspection_reply : @async.Queue[Json]?
}

///|
/// One target, one adapter, no restart or attach. The main loop owns all
/// transport IO and lifecycle state. Inspection jobs use the shared MoonBit
/// value service through that loop, never through a competing adapter reader.
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
  inspection : InspectionState
  mut capabilities : Json
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
  inspection_reply? : @async.Queue[Json]? = None,
) -> Unit {
  let seq = self.next_seq
  self.next_seq += 1
  self.pending.set(seq, {
    client_seq,
    command,
    deadline: @async.now() + 15000,
    execution_revision: self.execution_revision,
    inspection_reply,
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
