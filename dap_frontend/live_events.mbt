///|
fn LiveSession::finish(self : LiveSession) -> Json? {
  guard !self.ended else { return None }
  self.ended = true
  self.stopped = false
  self.deadline = Some(@async.now() + 3000)
  Some(self.client.event("terminated", {}))
}

///|
async fn LiveSession::on_adapter(
  self : LiveSession,
  writer : &@io.Writer,
  message : Json,
  launch_seq : Int,
  launch_args : Json,
) -> Unit {
  match message {
    {
      "type": String("response"),
      "request_seq": Number(raw, ..),
      "command": String(command),
      "success": success,
      ..
    } => {
      guard raw >= 1 &&
        raw <= 2147483647 &&
        raw == raw.to_int().to_double() &&
        self.pending.get(raw.to_int()) is Some(pending) &&
        pending.command == command else {
        raise LiveError("Unexpected lldb-dap response.")
      }
      self.pending.remove(raw.to_int())
      let body = match message {
        { "body": body, .. } => body
        _ => {}
      }
      if command == "stackTrace" && body is { "stackFrames": Array(frames), .. } {
        for frame in frames {
          if frame is Object(fields) && fields.get("name") is Some(String(name)) {
            let rendered = @name_mangle.demangle_top_level_function(name).source_name() catch {
              _ => name
            }
            fields.set("name", Json(rendered))
          }
        }
      }
      let error = match success {
        True => None
        False =>
          Some(
            match message {
              { "message": String(text), .. } => text
              _ => "lldb-dap rejected the request."
            },
          )
        _ => raise LiveError("Invalid lldb-dap response success field.")
      }
      if command == "initialize" {
        if error is Some(error) {
          raise LiveError(error)
        }
        if !self.closing {
          self.request(launch_seq, "launch", launch_args)
        }
        return
      }
      if command == "continue" && error is Some(_) && !self.ended {
        self.stopped = true
      }
      if command != "launch" || !self.launch_answered {
        send_client(
          writer,
          self.client.response(pending.client_seq, command, body~, error~),
        )
      }
      if command == "launch" {
        self.launch_answered = true
      }
      if (command == "launch" || command == "configurationDone") &&
        error is Some(_) {
        if self.finish() is Some(event) {
          send_client(writer, event)
        }
      }
      if command == "disconnect" {
        if error is Some(error) {
          raise LiveError(error)
        }
        // A disconnect response may overtake outstanding inspection requests.
        // Complete them explicitly before the client tears down this adapter.
        for request in self.pending.values() {
          if request.client_seq > 0 && request.command != "launch" {
            send_client(
              writer,
              self.client.response(
                request.client_seq,
                request.command,
                error=Some("Session disconnected."),
              ),
            )
          }
        }
        self.pending.clear()
        if self.finish() is Some(event) {
          send_client(writer, event)
        }
        self.client.closed = true
      }
    }
    { "type": String("event"), "event": String(name), .. } => {
      let body = match message {
        { "body": body, .. } => body
        _ => {}
      }
      match name {
        "initialized" => {
          self.ready = true
          send_client(writer, self.client.event(name, body))
        }
        "stopped" if !self.ended && !self.closing => {
          self.stopped = true
          send_client(writer, self.client.event(name, body))
        }
        "continued" if !self.ended => {
          self.stopped = false
          send_client(writer, self.client.event(name, body))
        }
        "terminated" =>
          if self.finish() is Some(event) {
            send_client(writer, event)
          }
        "exited" => {
          self.stopped = false
          send_client(writer, self.client.event(name, body))
        }
        "output" | "process" | "thread" | "breakpoint" =>
          send_client(writer, self.client.event(name, body))
        // Never forward capabilities that this frontend has not implemented.
        _ => ()
      }
    }
    { "type": String("request"), "seq": seq, "command": command, .. } => {
      let outgoing = self.next_seq
      self.next_seq += 1
      self.transport.send_message({
        "type": "response",
        "seq": outgoing,
        "request_seq": seq,
        "command": command,
        "success": false,
        "message": "moondbg does not support reverse requests or external terminals.",
      })
    }
    _ => raise LiveError("Invalid lldb-dap message.")
  }
}
