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
  self.handle_live_request(writer, seq, command, arguments)
}

///|
async fn LiveSession::handle_live_request(
  self : LiveSession,
  writer : &@io.Writer,
  seq : Int,
  command : String,
  arguments : Json,
) -> Unit {
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
    self.cancel_functions(writer, "Session disconnected.")
    self.invalidate_inspection(writer)
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
  // Preserve client order around asynchronous breakpoint replacement. Stop
  // and inspection remain responsive; execution cannot outrun installation.
  if self.functions.active is Some(_) &&
    (
      command == "setFunctionBreakpoints" ||
      command == "configurationDone" ||
      resumes_execution(command)
    ) {
    guard self.functions.deferred.length() < 64 else {
      send_client(
        writer,
        self.client.response(
          seq,
          command,
          error=Some(
            "Too many requests pending function breakpoint installation.",
          ),
        ),
      )
      return
    }
    self.functions.deferred.push((seq, command, arguments))
    return
  }
  match command {
    "setFunctionBreakpoints" if self.ready && !self.ended => {
      let points = function_points(arguments) catch {
        error => {
          send_client(
            writer,
            self.client.response(
              seq,
              command,
              error=Some(launch_error_message(error)),
            ),
          )
          return
        }
      }
      self.functions.active = Some(seq)
      self.functions.jobs.put(points)
    }
    "threads" if self.ended =>
      send_client(
        writer,
        self.client.response(seq, command, body={ "threads": [] }),
      )
    "threads" if self.ready => self.request(seq, command, {})
    "setBreakpoints" if self.ready && !self.ended => {
      let checked = canonical_line_breakpoint_arguments(arguments) catch {
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
    "scopes" | "variables" | "evaluate" =>
      self.inspect_client(writer, seq, command, arguments)
    "continue" | "next" | "stepIn" | "stepOut" | "pause" =>
      self.control(writer, seq, command, arguments)
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

///|
async fn canonical_line_breakpoint_arguments(arguments : Json) -> Json {
  let checked = line_breakpoint_arguments(arguments)
  guard checked
    is { "source": { "path": String(path), .. }, "breakpoints": points, .. } else {
    raise LiveError("Invalid checked source breakpoint")
  }
  // Package builds canonicalize directories. Match DWARF paths even when the
  // editor opened a symlink (notably /tmp -> /private/tmp on macOS). Missing
  // files still reach LLDB and get its usual unverified breakpoint response.
  let canonical = if @fs.exists(path) { @fs.realpath(path) } else { path }
  { "source": { "path": canonical }, "breakpoints": points }
}
