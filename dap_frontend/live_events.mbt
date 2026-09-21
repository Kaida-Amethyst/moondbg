///|
fn LiveSession::finish(self : LiveSession) -> Json? {
  guard !self.ended else { return None }
  self.ended = true
  self.stopped = false
  self.pause_revision = None
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
      if pending.panic_reply is Some(reply) {
        (reply.try_put(message) catch { _ => false }) |> ignore
        return
      }
      if pending.stop_context is Some(stop) {
        self.complete_panic_stop(writer, pending, stop, message)
        return
      }
      if pending.function_reply is Some(reply) {
        (reply.try_put(message) catch { _ => false }) |> ignore
        return
      }
      if pending.inspection_reply is Some(reply) {
        (reply.try_put(message) catch { _ => false }) |> ignore
        return
      }
      if command == "stackTrace" &&
        (
          !self.stopped ||
          self.exited ||
          self.ended ||
          self.closing ||
          pending.execution_revision != self.execution_revision
        ) {
        send_client(
          writer,
          self.client.response(
            pending.client_seq,
            command,
            error=Some("Stack request belongs to a stale stop"),
          ),
        )
        return
      }
      let body = match message {
        { "body": body, .. } => body
        _ => {}
      }
      if command == "stackTrace" && body is { "stackFrames": Array(frames), .. } {
        self.panic.present_frames(pending.arguments, frames)
        for frame in frames {
          if frame is Object(fields) && fields.get("name") is Some(String(name)) {
            let rendered = @name_mangle.demangle_top_level_function(name).source_name() catch {
              _ => name
            }
            fields.set("name", Json(rendered))
          }
        }
        self.inspection.map_frames(frames)
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
          self.capabilities = body
          self.request(launch_seq, "launch", launch_args)
        }
        return
      }
      // A delayed rejection must not roll back a newer stop, resume or exit.
      if resumes_execution(command) &&
        error is Some(_) &&
        !self.ended &&
        !self.exited &&
        !self.closing &&
        pending.execution_revision == self.execution_revision {
        self.stopped = true
      }
      if command == "pause" &&
        error is Some(_) &&
        self.pause_revision == Some(pending.execution_revision) {
        self.pause_revision = None
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
        "stopped" if !self.ended && !self.exited && !self.closing => {
          self.panic.thread = None
          self.invalidate_inspection(writer)
          self.execution_revision += 1
          self.stopped = true
          let stop = self.pause_stop_body(body)
          if self.functions.active is Some(_) || self.panic.active is Some(_) {
            // A running target can hit a newly created breakpoint before its
            // installation reply. Publish the BP IDs before its stop event.
            self.functions.stops.push(stop)
          } else {
            self.publish_stop(writer, stop)
          }
        }
        "continued" if !self.ended && !self.exited => {
          self.panic.thread = None
          self.invalidate_inspection(writer)
          self.execution_revision += 1
          self.stopped = false
          send_client(writer, self.client.event(name, body))
        }
        "terminated" => {
          self.cancel_functions(writer, "Session terminated.")
          self.invalidate_inspection(writer)
          if self.finish() is Some(event) {
            send_client(writer, event)
          }
        }
        "exited" => {
          self.panic.thread = None
          self.cancel_functions(writer, "Program exited.")
          self.invalidate_inspection(writer)
          self.execution_revision += 1
          self.exited = true
          self.pause_revision = None
          self.stopped = false
          send_client(writer, self.client.event(name, body))
        }
        "breakpoint" =>
          if self.functions.active is Some(_) || self.panic.active is Some(_) {
            self.functions.events.push(body)
          } else {
            self.function_event(writer, body)
          }
        "output" | "process" | "thread" =>
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
