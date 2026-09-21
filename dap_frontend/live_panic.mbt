///|
priv struct PanicState {
  jobs : @async.Queue[Bool]
  mut active : Int?
  mut configured : Bool
  mut breakpoint : @lldb_dap.InstalledFunctionBreakpoint?
  owned : Map[Int, Bool]
  project_sources : Map[String, Bool]
  mut thread : Int?
}

///|
fn PanicState::new(sources : Array[String]) -> PanicState {
  let project_sources : Map[String, Bool] = Map([])
  for path in sources {
    project_sources.set(path, true)
  }
  {
    jobs: @async.Queue(kind=Blocking(1)),
    active: None,
    configured: false,
    breakpoint: None,
    owned: {},
    project_sources,
    thread: None,
  }
}

///|
fn panic_filter(arguments : Json) -> Bool raise {
  guard arguments is { "filters": Array(filters), .. } else {
    raise LiveError("Expected an exception filters array.")
  }
  for filter in filters {
    guard filter == Json("moonbit-panic") else {
      raise LiveError("Only the moonbit-panic exception filter is supported.")
    }
  }
  for key in ["filterOptions", "exceptionOptions"] {
    if arguments is Object(fields) &&
      fields.get(key) is Some(value) &&
      !(value is Array([])) {
      raise LiveError(
        "Exception breakpoint conditions/options are not supported.",
      )
    }
  }
  !filters.is_empty()
}

///|
async fn LiveSession::panic_worker(
  self : LiveSession,
  inbox : @async.Queue[LiveInput],
) -> Unit {
  let driver = @lldb_dap.FunctionBreakpointDriver::new((command, args) => {
    let reply : @async.Queue[Json] = @async.Queue(kind=Blocking(1))
    defer reply.close()
    inbox.put(PanicRead(command, args, reply))
    guard @dap.classify_message(reply.get()) is @dap.Response(response) else {
      raise LiveError("Invalid panic breakpoint response")
    }
    response
  })
  for installed = (None : @lldb_dap.InstalledFunctionBreakpoint?) {
    let enabled = self.panic.jobs.get()
    let result = try {
      let next = if enabled {
        match installed {
          Some(value) => Some(value)
          None => Some(driver.install_panic())
        }
      } else {
        if installed is Some(value) {
          driver.remove(value.id)
        }
        None
      }
      Ok(next)
    } catch {
      error => {
        if @async.is_cancellation_error(error) {
          raise error
        }
        Err(function_error(error))
      }
    }
    inbox.put(PanicDone(result))
    continue match result {
        Ok(value) => value
        Err(_) => installed
      }
  }
}

///|
async fn LiveSession::complete_panic(
  self : LiveSession,
  writer : &@io.Writer,
  result : Result[@lldb_dap.InstalledFunctionBreakpoint?, String],
) -> Unit {
  guard self.panic.active is Some(seq) else { return }
  let installed = match result {
    Ok(value) => value
    // As with user function breakpoints, never resume after an uncertain edit.
    Err(message) => raise LiveError(message)
  }
  self.panic.active = None
  self.panic.configured = true
  self.panic.breakpoint = installed
  if installed is Some(value) {
    self.panic.owned.set(value.id, true)
  }
  if seq > 0 {
    let points : Array[Json] = match installed {
      Some(value) =>
        [
          {
            "verified": value.location_count > 0,
            "message": if value.location_count > 0 {
              "Stop at MoonBit panic before process exit."
            } else {
              "moonbit_panic is not present in this target; breakpoint remains pending."
            },
          },
        ]
      None => []
    }
    send_client(
      writer,
      self.client.response(seq, "setExceptionBreakpoints", body={
        "breakpoints": points,
      }),
    )
  }
  self.drain_breakpoint_updates(writer)
}

///|
async fn LiveSession::drain_breakpoint_updates(
  self : LiveSession,
  writer : &@io.Writer,
) -> Unit {
  for event in self.functions.events {
    self.function_event(writer, event)
  }
  self.functions.events.clear()
  for stop in self.functions.stops {
    self.publish_stop(writer, stop)
  }
  self.functions.stops.clear()
  while self.functions.active is None &&
        self.panic.active is None &&
        self.functions.deferred.length() > 0 {
    let (seq, command, arguments) = self.functions.deferred.remove(0)
    self.handle_live_request(writer, seq, command, arguments)
  }
}

///|
async fn LiveSession::publish_stop(
  self : LiveSession,
  writer : &@io.Writer,
  body : Json,
) -> Unit {
  if self.panic.breakpoint is Some(point) &&
    body
    is { "reason": String("breakpoint"), "threadId": Number(thread, ..), .. } &&
    thread > 0 &&
    thread <= 2147483647 &&
    thread == thread.to_int().to_double() {
    let candidate = match body {
      { "hitBreakpointIds": Array(ids), .. } => ids.contains(Json(point.id))
      _ => true
    }
    if candidate {
      // The event loop remains responsive while inspecting the raw top frame.
      // Do not classify a signal by searching for panic in its caller frames.
      self.request(
        0,
        "stackTrace",
        { "threadId": thread, "startFrame": 0, "levels": 0 },
        stop_context=Some(body),
      )
      return
    }
  }
  send_client(
    writer,
    self.client.event("stopped", self.function_stop_body(body)),
  )
}

///|
fn PanicState::owns_frame(self : PanicState, frame : Json) -> Bool {
  frame
  is { "source": { "path": String(path), .. }, "line": Number(line, ..), .. } &&
  line > 0 &&
  self.project_sources.contains(path)
}

///|
async fn LiveSession::complete_panic_stop(
  self : LiveSession,
  writer : &@io.Writer,
  pending : PendingRequest,
  body : Json,
  message : Json,
) -> Unit {
  guard self.stopped &&
    !self.exited &&
    !self.ended &&
    !self.closing &&
    pending.execution_revision == self.execution_revision else {
    return
  }
  let frames = match message {
    { "success": True, "body": { "stackFrames": Array(frames), .. }, .. } =>
      frames
    _ => []
  }
  let name = match frames {
    [{ "name": String(name), .. }, ..] => Some(name)
    _ => None
  }
  if @lldb_dap.panic_stop_reason("breakpoint", name) == "MoonBit panic" &&
    body is Object(fields) &&
    fields.get("threadId") is Some(Number(thread, ..)) {
    self.panic.thread = Some(thread.to_int())
    let copy = fields.copy()
    copy.set("reason", Json("exception"))
    copy.set("description", Json("MoonBit panic"))
    copy.set(
      "text",
      Json("MoonBit panic (runtime supplied no additional details)"),
    )
    copy.remove("hitBreakpointIds")
    if !frames.any(frame => self.panic.owns_frame(frame)) {
      let notice = if self.panic.project_sources.is_empty() {
        "MoonBit panic: project source context is unavailable; select a frame in CALL STACK to inspect manually."
      } else {
        "MoonBit panic: no project source frame with a valid location was found; select a frame in CALL STACK to inspect manually."
      }
      copy.set("description", Json(notice))
      send_client(
        writer,
        self.client.event("output", {
          "category": "console",
          "output": "\{notice}\n",
        }),
      )
    }
    send_client(writer, self.client.event("stopped", Json(copy)))
  } else {
    if frames.is_empty() {
      send_client(
        writer,
        self.client.event("output", {
          "category": "console",
          "output": "moondbg: could not inspect the stop frame; retaining LLDB's original stop reason.\n",
        }),
      )
    }
    send_client(
      writer,
      self.client.event("stopped", self.function_stop_body(body)),
    )
  }
}

///|
fn PanicState::present_frames(
  self : PanicState,
  arguments : Json,
  frames : Array[Json],
) -> Unit {
  guard self.thread is Some(thread) &&
    arguments is { "threadId": Number(requested, ..), .. } &&
    requested == thread.to_double() else {
    return
  }
  // Keep physical order and all frames. For exception stops VS Code focuses
  // the first non-subtle frame with source; frame IDs still name real frames.
  for frame in frames {
    if frame is Object(fields) {
      fields.set(
        "presentationHint",
        Json(if self.owns_frame(frame) { "normal" } else { "subtle" }),
      )
    }
  }
}
