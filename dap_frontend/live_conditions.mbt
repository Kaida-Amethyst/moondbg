///|
priv struct ConditionJob {
  epoch : Int
  body : Json
  thread : Int
  expressions : Array[@expression.Condition]
}

///|
priv struct ConditionState {
  bindings : @lldb_dap.BreakpointConditions
  jobs : @async.Queue[ConditionJob]
  mut active : ConditionJob?
  mut updating : Bool
  mut stepping : Bool
  mut suppress_continued : Bool
}

///|
fn ConditionState::new() -> ConditionState {
  {
    bindings: @lldb_dap.BreakpointConditions::new(),
    jobs: @async.Queue(kind=Blocking(64)),
    active: None,
    updating: false,
    stepping: false,
    suppress_continued: false,
  }
}

///|
fn breakpoint_condition(point : Json) -> @expression.Condition? raise {
  match point {
    { "condition": String(text), .. } =>
      if text.trim().is_empty() {
        None
      } else {
        Some(@expression.Condition::parse(text[:]))
      }
    { "condition": _, .. } =>
      raise LiveError("Breakpoint condition must be a string.")
    _ => None
  }
}

///|
// The saved request retains conditions; the adapter receives locations only.
fn strip_conditions(arguments : Json) -> Json {
  guard arguments is { "source": source, "breakpoints": Array(points), .. } else {
    return arguments
  }
  {
    "source": source,
    "breakpoints": points.map(point => {
      match point {
        Object(fields) => {
          let copy = fields.copy()
          copy.remove("condition")
          Json(copy)
        }
        _ => point
      }
    }),
  }
}

///|
fn ConditionState::install(
  self : ConditionState,
  arguments : Json,
  body : Json,
) -> Unit raise {
  guard arguments
    is {
      "source": { "path": String(path), .. },
      "breakpoints": Array(points),
      ..
    } &&
    body is { "breakpoints": Array(installed), .. } &&
    points.length() == installed.length() else {
    raise LiveError(
      "Invalid source breakpoint replacement response; cannot safely bind conditions.",
    )
  }
  let bindings = []
  for index, point in points {
    let condition = breakpoint_condition(point)
    if installed[index] is { "id": Number(id, ..), .. } &&
      id >= 0 &&
      id <= 2147483647 &&
      id == id.to_int().to_double() {
      bindings.push((id.to_int(), condition))
    } else if condition is Some(_) &&
      installed[index] is { "verified": True, .. } {
      raise LiveError("Verified conditional breakpoint has no adapter ID.")
    }
  }
  self.bindings.replace(path, bindings)
}

///|
fn LiveSession::breakpoint_work_pending(self : LiveSession) -> Bool {
  self.functions.active is Some(_) ||
  self.panic.active is Some(_) ||
  self.conditions.updating ||
  self.conditions.active is Some(_)
}

///|
// Function families use the same target ID namespace as source breakpoints.
// Keep duplicate logical entries so an unconditional one preserves the stop.
fn ConditionState::install_functions(
  self : ConditionState,
  points : Array[Json],
  installed : Array[Json],
) -> Unit raise {
  guard points.length() == installed.length() else {
    raise LiveError("Incomplete function breakpoint replacement response.")
  }
  let bindings = []
  for index, result in installed {
    if result is { "id": Number(id, ..), .. } &&
      id >= 0 &&
      id <= 2147483647 &&
      id == id.to_int().to_double() {
      bindings.push((id.to_int(), breakpoint_condition(points[index])))
    } else if result is { "verified": True, .. } {
      raise LiveError("Verified function breakpoint has no adapter ID.")
    }
  }
  self.bindings.replace_functions(bindings)
}

///|
fn LiveSession::condition_epoch(self : LiveSession) -> Int? {
  guard self.stopped &&
    !self.exited &&
    !self.ended &&
    !self.closing &&
    self.conditions.active is Some(job) &&
    job.epoch == self.execution_revision else {
    return None
  }
  Some(job.epoch)
}

///|
async fn LiveSession::publish_condition_stop(
  self : LiveSession,
  writer : &@io.Writer,
  body : Json,
) -> Unit {
  if !self.conditions.stepping &&
    self.conditions.bindings.for_stop(body) is Some(expressions) &&
    body is { "threadId": Number(thread, ..), .. } &&
    thread > 0 &&
    thread <= 2147483647 &&
    thread == thread.to_int().to_double() {
    let job = {
      epoch: self.execution_revision,
      body,
      thread: thread.to_int(),
      expressions,
    }
    self.conditions.active = Some(job)
    self.conditions.jobs.put(job)
  } else {
    send_client(
      writer,
      self.client.event("stopped", self.function_stop_body(body)),
    )
  }
}

///|
async fn LiveSession::condition_worker(
  self : LiveSession,
  inbox : @async.Queue[LiveInput],
) -> Unit {
  for ;; {
    let job = self.conditions.jobs.get()
    let result = @async.with_timeout(12000, () => {
      let request : async (String, Json) -> @dap.DapResponse = (command, args) => {
        let reply : @async.Queue[Json] = @async.Queue(kind=Blocking(1))
        defer reply.close()
        inbox.put(ConditionRead(job.epoch, command, args, reply))
        let message = reply.get()
        guard self.condition_epoch() == Some(job.epoch) else {
          raise LiveError("Stale condition reply")
        }
        guard @dap.classify_message(message) is @dap.Response(response) else {
          raise LiveError("Invalid condition response")
        }
        response
      }
      let stack = request("stackTrace", {
        "threadId": job.thread,
        "startFrame": 0,
        "levels": 1,
      })
      guard stack.success() &&
        stack.body()
        is { "stackFrames": [{ "id": Number(frame, ..), .. }, ..], .. } &&
        frame >= 0 &&
        frame <= 2147483647 &&
        frame == frame.to_int().to_double() else {
        raise LiveError("Cannot read the top frame for breakpoint condition.")
      }
      let inspector = @lldb_dap.VariableInspector::new(
        request,
        () => self.condition_epoch(),
        self.capabilities,
      )
      inspector.test_conditions(frame.to_int(), job.expressions)
    }) catch {
      error => {
        if @async.is_cancellation_error(error) {
          raise error
        }
        Err(inspection_error_message(error))
      }
    }
    inbox.put(ConditionDone(job.epoch, result))
  }
}

///|
async fn LiveSession::condition_failure(
  self : LiveSession,
  writer : &@io.Writer,
  body : Json,
  message : String,
) -> Unit {
  send_client(
    writer,
    self.client.event("output", {
      "category": "console",
      "output": "Breakpoint condition error: \{message}\n",
    }),
  )
  let stopped = match body {
    Object(fields) => {
      let copy = fields.copy()
      copy.set("description", Json("Breakpoint condition error: \{message}"))
      copy.set("text", Json(message))
      Json(copy)
    }
    _ => body
  }
  send_client(
    writer,
    self.client.event("stopped", self.function_stop_body(stopped)),
  )
}

///|
async fn LiveSession::complete_condition(
  self : LiveSession,
  writer : &@io.Writer,
  epoch : Int,
  result : Result[Bool, String],
) -> Unit {
  guard self.condition_epoch() == Some(epoch) &&
    self.conditions.active is Some(job) else {
    return
  }
  self.conditions.active = None
  match result {
    Ok(true) =>
      send_client(
        writer,
        self.client.event("stopped", self.function_stop_body(job.body)),
      )
    Err(message) => self.condition_failure(writer, job.body, message)
    Ok(false) => {
      self.invalidate_inspection(writer)
      self.execution_revision += 1
      self.stopped = false
      self.conditions.suppress_continued = true
      self.request(
        0,
        "continue",
        { "threadId": job.thread, "singleThread": false },
        condition_continue=Some(job.body),
      )
    }
  }
  self.drain_breakpoint_updates(writer)
}
