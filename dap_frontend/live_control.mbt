///|
fn resumes_execution(command : String) -> Bool {
  command is ("continue" | "next" | "stepIn" | "stepOut")
}

///|
fn execution_arguments(command : String, arguments : Json) -> Json raise {
  guard arguments is { "threadId": Number(thread, ..), .. } &&
    thread > 0 &&
    thread <= 2147483647 &&
    thread == thread.to_int().to_double() else {
    raise LiveError("\{command} requires a valid threadId.")
  }
  // Only ordinary source stepping, resuming all threads, is exposed. Do not
  // silently turn instruction stepping or a targeted step-in into another op.
  if arguments is Object(fields) {
    if fields.get("singleThread") is Some(value) && value != Json(false) {
      raise LiveError("Single-thread execution is not supported.")
    }
    if fields.get("granularity") is Some(value) &&
      (command is ("continue" | "pause") || value != Json("statement")) {
      raise LiveError("Only default source stepping is supported.")
    }
    if fields.contains("targetId") {
      raise LiveError("Targeted step-in is not supported.")
    }
  }
  if command == "pause" {
    { "threadId": thread }
  } else {
    { "threadId": thread, "singleThread": false }
  }
}

///|
async fn LiveSession::control(
  self : LiveSession,
  writer : &@io.Writer,
  seq : Int,
  command : String,
  arguments : Json,
) -> Unit {
  let checked = try {
    guard self.ready &&
      self.configured &&
      self.launch_answered &&
      !self.exited &&
      !self.ended else {
      raise LiveError("\{command} requires an active debug session.")
    }
    if command == "pause" {
      guard !self.stopped || self.conditions.active is Some(_) else {
        raise LiveError("The program is already stopped.")
      }
      guard self.pause_revision is None else {
        raise LiveError("Pause already in progress.")
      }
    } else {
      guard self.stopped else {
        raise LiveError("\{command} requires a stopped program.")
      }
    }
    execution_arguments(command, arguments)
  } catch {
    error => {
      send_client(
        writer,
        self.client.response(seq, command, error=Some(@debug.to_string(error))),
      )
      return
    }
  }
  if command == "pause" && self.conditions.active is Some(job) {
    self.conditions.active = None
    self.execution_revision += 1
    send_client(writer, self.client.response(seq, command))
    let body = match job.body {
      Object(fields) => {
        let copy = fields.copy()
        copy.set("reason", Json("pause"))
        copy.set("description", Json("Paused by user request"))
        copy.remove("hitBreakpointIds")
        Json(copy)
      }
      _ => job.body
    }
    send_client(writer, self.client.event("stopped", body))
    self.drain_breakpoint_updates(writer)
    return
  }
  if resumes_execution(command) {
    self.conditions.stepping = command != "continue"
    self.invalidate_inspection(writer)
    self.execution_revision += 1
    self.stopped = false
  } else {
    self.pause_revision = Some(self.execution_revision)
  }
  // A pause acknowledgement is not a stop. Inspection becomes available only
  // on the adapter's stopped event, and the input loop keeps receiving requests.
  self.request(seq, command, checked)
}

///|
fn LiveSession::pause_stop_body(self : LiveSession, body : Json) -> Json {
  // Apple LLDB reports a successful SBProcess::Stop as SIGSTOP/exception.
  // Normalize only that known signal while our explicit pause is outstanding;
  // real breakpoints, other signals and unsolicited SIGSTOP retain their reason.
  if self.pause_revision is Some(_) &&
    body is Object(fields) &&
    fields.get("reason") == Some(Json("exception")) &&
    fields.get("description") == Some(Json("signal SIGSTOP")) {
    fields.set("reason", Json("pause"))
    fields.set("description", Json("Paused by user request"))
  }
  self.pause_revision = None
  body
}
