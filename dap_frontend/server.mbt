///|
/// A launch selects either the connection test or one live, event-driven
/// execution. Human CLI and readline are never involved.
pub async fn serve(reader : &@io.Reader, writer : &@io.Writer) -> Unit {
  let session = ConnectionSession::new()
  for deadline = (None : Int64?); !session.closed; {
    let timeout = match deadline {
      Some(deadline) => (deadline - @async.now()).to_int()
      None => 15000
    }
    guard timeout > 0 else { break }
    let received = @async.with_timeout_opt(timeout, () => {
      @dap.read_frame(reader)
    })
    guard received is Some(body) else {
      if session.finished {
        break
      }
      raise HandshakeTimeout
    }
    guard body is Some(body) else { break }
    let (seq, command, arguments) = session.read_request(@json.parse(body))
    if command == "launch" &&
      session.initialized &&
      session.launch_seq is None &&
      !session.finished &&
      !(arguments is { "connectionTest": True, .. }) {
      serve_launch(reader, writer, session, seq, arguments)
      return
    }
    let messages = session.handle_request(seq, command, arguments)
    for message in messages {
      writer.write(@dap.frame_message(message.stringify()))
    }
    continue if session.finished && deadline is None {
        Some(@async.now() + 3000)
      } else {
        deadline
      }
  }
}
