///|
fn line_breakpoint_arguments(arguments : Json) -> Json raise {
  guard arguments is { "source": { "path": String(path), .. }, .. } &&
    path.has_prefix("/") else {
    raise LiveError("setBreakpoints requires an absolute source.path.")
  }
  let points = match arguments {
    { "breakpoints": Array(points), .. } => points
    { "breakpoints": _, .. } => raise LiveError("Expected a breakpoints array.")
    _ => []
  }
  for point in points {
    guard point is { "line": Number(line, ..), .. } &&
      line >= 1 &&
      line <= 2147483647 &&
      line == line.to_int().to_double() else {
      raise LiveError("Breakpoint lines must be positive integers.")
    }
    for key in ["condition", "hitCondition", "logMessage", "column"] {
      if point is Object(fields) && fields.contains(key) {
        raise LiveError("Only unconditional line breakpoints are supported.")
      }
    }
  }
  // DAP is authoritative per file: [] clears only this file's breakpoints.
  { "source": { "path": path }, "breakpoints": points }
}

///|
async fn LiveSession::on_client(
  self : LiveSession,
  writer : &@io.Writer,
  message : Json,
) -> Unit {
  let (seq, command, arguments) = self.client.read_request(message)
  if command == "disconnect" {
    guard !self.closing else {
      send_client(
        writer,
        self.client.response(
          seq,
          command,
          error=Some("Disconnect already in progress."),
        ),
      )
      return
    }
    self.closing = true
    self.deadline = Some(@async.now() + 3000)
    self.cancel_launch(writer, "Launch cancelled by client.")
    self.request(seq, command, { "terminateDebuggee": true })
    return
  }
  if self.closing {
    send_client(
      writer,
      self.client.response(
        seq,
        command,
        error=Some("Session is disconnecting."),
      ),
    )
    return
  }
  match command {
    "threads" if self.ended =>
      send_client(
        writer,
        self.client.response(seq, command, body={ "threads": [] }),
      )
    "threads" if self.ready => self.request(seq, command, {})
    "setBreakpoints" if self.ready && !self.ended => {
      let checked = line_breakpoint_arguments(arguments) catch {
        error => {
          send_client(
            writer,
            self.client.response(
              seq,
              command,
              error=Some(@debug.to_string(error)),
            ),
          )
          return
        }
      }
      self.request(seq, command, checked)
    }
    "setExceptionBreakpoints" if self.ready && !self.ended =>
      if arguments is { "filters": Array([]), .. } {
        send_client(
          writer,
          self.client.response(seq, command, body={ "breakpoints": [] }),
        )
      } else {
        send_client(
          writer,
          self.client.response(
            seq,
            command,
            error=Some("Exception breakpoints are not supported."),
          ),
        )
      }
    "configurationDone" if self.ready && !self.configured && !self.ended => {
      self.configured = true
      self.deadline = None
      self.request(seq, command, {})
    }
    "stackTrace" if self.stopped && !self.ended =>
      self.request(seq, command, arguments)
    "scopes" if self.stopped && !self.ended =>
      send_client(
        writer,
        self.client.response(seq, command, body={ "scopes": [] }),
      )
    "continue" if self.stopped && !self.ended => {
      guard arguments is { "threadId": Number(thread, ..), .. } &&
        thread > 0 &&
        thread <= 2147483647 &&
        thread == thread.to_int().to_double() else {
        send_client(
          writer,
          self.client.response(
            seq,
            command,
            error=Some("continue requires a valid threadId."),
          ),
        )
        return
      }
      self.stopped = false
      self.request(seq, command, { "threadId": thread, "singleThread": false })
    }
    _ =>
      send_client(
        writer,
        self.client.response(
          seq,
          command,
          error=Some(
            "Request is unsupported or unavailable in the current state: \{command}",
          ),
        ),
      )
  }
}
