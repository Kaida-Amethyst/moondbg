///|
priv struct FunctionState {
  context : @debugger.DebugContext
  jobs : @async.Queue[Array[Json]]
  mut active : Int?
  deferred : Array[(Int, String, Json)]
  events : Array[Json]
  stops : Array[Json]
  published : Map[Int, Json]
  owned : Map[Int, Bool]
}

///|
fn FunctionState::new(context : @debugger.DebugContext) -> FunctionState {
  {
    context,
    jobs: @async.Queue(kind=Blocking(1)),
    active: None,
    deferred: [],
    events: [],
    stops: [],
    published: {},
    owned: {},
  }
}

///|
fn function_points(arguments : Json) -> Array[Json] raise {
  guard arguments is { "breakpoints": Array(points), .. } else {
    raise LiveError("Expected a breakpoints array.")
  }
  points
}

///|
fn resolve_function_point(
  context : @debugger.DebugContext,
  point : Json,
) -> (String, @debugger.FunctionBreakpointSelector) raise {
  guard point is Object(fields) && fields.get("name") is Some(String(text)) else {
    raise LiveError("Function breakpoint requires a name.")
  }
  for key in ["condition", "hitCondition"] {
    if fields.contains(key) {
      raise LiveError("Only unconditional function breakpoints are supported.")
    }
  }
  let request = @debugger.FunctionBreakpointRequest::parse(text.trim())
  if request.display_name() != "main" {
    context.current_package() |> ignore
  }
  (request.display_name(), context.resolve_function(request))
}

///|
fn function_error(error : Error) -> String {
  match error {
    @debugger.FunctionNameError(message) | LiveError(message) => message
    @debugger.MissingCurrentPackage =>
      "Function names require launch.package; launch.program only supports main."
    @debugger.UnknownPackageAlias(package_alias) =>
      "Unknown package alias @\{package_alias} in the launch package."
    _ => @debug.to_string(error)
  }
}

///|
fn installed_function_json(
  value : @lldb_dap.InstalledFunctionBreakpoint,
) -> Json {
  {
    "id": value.id,
    "verified": value.location_count > 0,
    "message": if value.location_count == 0 {
      "No matching function instances in this executable."
    } else {
      "Matched \{value.location_count} function location(s)."
    },
  }
}

///|
async fn replace_functions(
  driver : @lldb_dap.FunctionBreakpointDriver,
  context : @debugger.DebugContext,
  installed : Map[String, @lldb_dap.InstalledFunctionBreakpoint],
  points : Array[Json],
) -> Array[Json] {
  let desired = points.map(point => {
    Ok(resolve_function_point(context, point)) catch {
      error => Err(function_error(error))
    }
  })
  let names : Map[String, Bool] = Map([])
  for item in desired {
    if item is Ok((name, _)) {
      names.set(name, true)
    }
  }
  // A full replacement contains only enabled entries. Unchecking in VS Code
  // removes an entry here; reenabling installs it again with a fresh target ID.
  for name in installed.keys().collect() {
    if !names.contains(name) && installed.get(name) is Some(value) {
      driver.remove(value.id)
      installed.remove(name)
    }
  }
  let results : Array[Json] = []
  for item in desired {
    match item {
      Err(message) => results.push({ "verified": false, "message": message })
      Ok((name, selector)) => {
        let value = match installed.get(name) {
          Some(value) => value
          None => {
            let value = driver.install(selector)
            installed.set(name, value)
            value
          }
        }
        results.push(installed_function_json(value))
      }
    }
  }
  results
}

///|
async fn LiveSession::function_worker(
  self : LiveSession,
  inbox : @async.Queue[LiveInput],
) -> Unit {
  let installed : Map[String, @lldb_dap.InstalledFunctionBreakpoint] = Map([])
  let driver = @lldb_dap.FunctionBreakpointDriver::new((command, args) => {
    let reply : @async.Queue[Json] = @async.Queue(kind=Blocking(1))
    defer reply.close()
    inbox.put(FunctionRead(command, args, reply))
    guard @dap.classify_message(reply.get()) is @dap.Response(response) else {
      raise LiveError("Invalid function breakpoint response")
    }
    response
  })
  for ;; {
    let points = self.functions.jobs.get()
    let result = Ok(
      replace_functions(driver, self.functions.context, installed, points),
    ) catch {
      error => {
        if @async.is_cancellation_error(error) {
          raise error
        }
        Err(function_error(error))
      }
    }
    inbox.put(FunctionDone(result))
  }
}

///|
async fn LiveSession::complete_functions(
  self : LiveSession,
  writer : &@io.Writer,
  result : Result[Array[Json], String],
) -> Unit {
  guard self.functions.active is Some(seq) else { return }
  let points = match result {
    Ok(points) => points
    // Never continue with an unknown, partially installed breakpoint set.
    // Session error handling fails the request and terminates the target.
    Err(message) => raise LiveError(message)
  }
  self.functions.active = None
  self.functions.published.clear()
  for point in points {
    if point is { "id": Number(id, ..), .. } {
      self.functions.published.set(id.to_int(), point)
      self.functions.owned.set(id.to_int(), true)
    }
  }
  send_client(
    writer,
    self.client.response(seq, "setFunctionBreakpoints", body={
      "breakpoints": points,
    }),
  )
  for event in self.functions.events {
    self.function_event(writer, event)
  }
  self.functions.events.clear()
  for stop in self.functions.stops {
    send_client(
      writer,
      self.client.event("stopped", self.function_stop_body(stop)),
    )
  }
  self.functions.stops.clear()
  while self.functions.active is None && self.functions.deferred.length() > 0 {
    let (seq, command, arguments) = self.functions.deferred.remove(0)
    self.handle_live_request(writer, seq, command, arguments)
  }
}

///|
async fn LiveSession::cancel_functions(
  self : LiveSession,
  writer : &@io.Writer,
  message : String,
) -> Unit {
  if self.functions.active is Some(seq) {
    self.functions.active = None
    send_client(
      writer,
      self.client.response(seq, "setFunctionBreakpoints", error=Some(message)),
    )
  }
  for (seq, command, _) in self.functions.deferred {
    send_client(writer, self.client.response(seq, command, error=Some(message)))
  }
  self.functions.deferred.clear()
  self.functions.events.clear()
  self.functions.stops.clear()
  for request in self.pending.values() {
    if request.function_reply is Some(reply) {
      reply.close(error=LiveError(message))
    }
  }
}

///|
async fn LiveSession::function_event(
  self : LiveSession,
  writer : &@io.Writer,
  body : Json,
) -> Unit {
  if body is { "breakpoint": { "id": Number(id, ..), .. }, .. } &&
    self.functions.owned.contains(id.to_int()) {
    // Do not recreate removed UI entries or expose LLDB's single-location
    // view as a second breakpoint for a generic function family.
    if self.functions.published.get(id.to_int()) is Some(point) {
      send_client(
        writer,
        self.client.event("breakpoint", {
          "reason": "changed",
          "breakpoint": point,
        }),
      )
    }
    return
  }
  send_client(writer, self.client.event("breakpoint", body))
}

///|
fn LiveSession::function_stop_body(self : LiveSession, body : Json) -> Json {
  guard body is Object(fields) &&
    fields.get("hitBreakpointIds") is Some(Array(ids)) else {
    return body
  }
  // LLDB-DAP exposes SBTarget breakpoint IDs for both source and CLI-created
  // breakpoints. Preserve that common namespace; do not use frontend seq IDs.
  if ids.any(id => {
      id is Number(id, ..) && self.functions.published.contains(id.to_int())
    }) {
    let copy = fields.copy()
    copy.set("reason", Json("function breakpoint"))
    Json(copy)
  } else {
    body
  }
}
