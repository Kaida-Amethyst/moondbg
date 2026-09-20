///|
async fn LivePeer::set_functions(
  self : LivePeer,
  names : Array[String],
) -> Array[Json] {
  let response = self.response(
    self.send("setFunctionBreakpoints", arguments={
      "breakpoints": names.map(name => Json({ "name": name })),
    }),
  )
  guard response is { "breakpoints": Array(points), .. } else {
    fail(response.stringify())
  }
  assert_eq(points.length(), names.length())
  points
}

///|
fn function_id(point : Json) -> Int raise {
  guard point is { "id": Number(id, ..), "verified": True, .. } else {
    fail(point.stringify())
  }
  id.to_int()
}

///|
async fn LivePeer::function_stop(
  self : LivePeer,
  id : Int,
  name : String,
) -> Int {
  let stop = self.event("stopped")
  assert_true(
    stop
    is {
      "reason": String("function breakpoint"),
      "hitBreakpointIds": Array(ids),
      ..
    } &&
    ids.contains(Json(id)),
    msg=stop.stringify(),
  )
  let thread = dap_thread_id(stop)
  let frame = self.top_frame(thread)
  assert_true(
    frame is { "name": String(actual), .. } && actual.contains(name),
    msg=frame.stringify(),
  )
  thread
}

///|
async test "DAP function breakpoints resolve package aliases and all generic instances with live replacement" {
  guard toolchain_acceptance_enabled() else { return }
  toolchain_acceptance_mutex.acquire()
  defer toolchain_acceptance_mutex.release()
  let fixture = "\{@fs.realpath(".")}/testdata/dwarf_probe"
  let source = "\{fixture}/dap_functions/main.mbt"
  let checkpoint = unique_source_line(
    source, "println(\"first: \\{integer}, \\{double}\") // MOONDBG_FUNCTION_CHECKPOINT",
  )
  @async.with_task_group(group => {
    let peer = LivePeer::start(group)
    defer peer.close()
    let launch = peer.initialize_package("\{fixture}/dap_functions")
    peer.event("initialized") |> ignore
    // Pipeline configurationDone: the event loop must wait for installation,
    // without blocking its adapter reader or disconnect processing.
    let setting = peer.send("setFunctionBreakpoints", arguments={
      "breakpoints": [{ "name": "main" }],
    })
    let done = peer.send("configurationDone")
    let response = peer.response(setting)
    guard response is { "breakpoints": [entry], .. } else {
      fail(response.stringify())
    }
    let entry_id = function_id(entry)
    peer.response(done) |> ignore
    peer.response(launch) |> ignore
    let thread = peer.function_stop(entry_id, "moonbit_main")
    let points = peer.set_functions([
      "foo", "@util.foo", "identity", "missing", "@unknown.foo",
    ])
    let local_id = function_id(points[0])
    let imported_id = function_id(points[1])
    let generic_id = function_id(points[2])
    assert_true(
      points[2] is { "message": String(message), .. } &&
      message.contains("2 function"),
      msg=points[2].stringify(),
    )
    assert_true(points[3] is { "verified": False, .. })
    assert_true(
      points[4] is { "verified": False, "message": String(message), .. } &&
      message.contains("Unknown package alias"),
    )
    let kept = peer.set_functions(["foo", "@util.foo", "identity"])
    assert_eq(function_id(kept[0]), local_id)
    assert_eq(function_id(kept[1]), imported_id)
    assert_eq(function_id(kept[2]), generic_id)
    let line_points = peer.response(
      peer.send("setBreakpoints", arguments={
        "source": { "path": source },
        "breakpoints": [{ "line": checkpoint }],
      }),
    )
    guard line_points is { "breakpoints": [line_point], .. } else {
      fail(line_points.stringify())
    }
    let line_id = function_id(line_point)
    assert_true(
      line_id != generic_id && line_id != local_id && line_id != imported_id,
    )
    for
      (id, name) in [
        (local_id, ".foo"),
        (imported_id, ".foo"),
        (generic_id, ".identity"),
        (generic_id, ".identity"),
      ] {
      peer.response(peer.send("continue", arguments={ "threadId": thread }))
      |> ignore
      assert_eq(peer.function_stop(id, name), thread)
    }
    // Unchecking clears functions, but must leave source breakpoints intact.
    assert_eq(peer.set_functions([]), [])
    peer.response(peer.send("continue", arguments={ "threadId": thread }))
    |> ignore
    let stop = peer.event("stopped")
    assert_true(
      stop
      is { "reason": String("breakpoint"), "hitBreakpointIds": Array(ids), .. } &&
      ids.contains(Json(line_id)),
      msg=stop.stringify(),
    )
    assert_frame_location(peer.top_frame(thread), source, checkpoint)
    // Re-enable foo; deleting it at the next stop must prevent more function stops.
    let reenabled = peer.set_functions(["foo"])
    peer.response(peer.send("continue", arguments={ "threadId": thread }))
    |> ignore
    peer.function_stop(function_id(reenabled[0]), ".foo") |> ignore
    peer.set_functions([]) |> ignore
    peer.response(peer.send("continue", arguments={ "threadId": thread }))
    |> ignore
    assert_true(peer.event("exited") is { "exitCode": Number(0, ..), .. })
    peer.disconnect()
  })
}

///|
async test "DAP bare executable function breakpoints only resolve main without build metadata" {
  guard toolchain_acceptance_enabled() else { return }
  toolchain_acceptance_mutex.acquire()
  defer toolchain_acceptance_mutex.release()
  let (fixture, program, _) = build_dap_control_fixture("dap_functions")
  @async.with_task_group(group => {
    let peer = LivePeer::start(group)
    defer peer.close()
    let launch = peer.initialize_launch(program, fixture)
    let points = peer.set_functions(["foo", "@util.foo", "main"])
    for point in points[:2] {
      assert_true(
        point is { "verified": False, "message": String(message), .. } &&
        message.contains("launch.package"),
      )
    }
    let id = function_id(points[2])
    peer.response(peer.send("configurationDone")) |> ignore
    peer.response(launch) |> ignore
    peer.function_stop(id, "moonbit_main") |> ignore
    peer.disconnect()
  })
}

///|
async test "DAP running target accepts function updates and remains disconnectable" {
  guard toolchain_acceptance_enabled() else { return }
  toolchain_acceptance_mutex.acquire()
  defer toolchain_acceptance_mutex.release()
  let (fixture, program, _) = build_dap_control_fixture("dap_pause")
  @async.with_task_group(group => {
    let peer = LivePeer::start(group)
    defer peer.close()
    let launch = peer.initialize_launch(program, fixture)
    let points = peer.set_functions(["main"])
    peer.response(peer.send("configurationDone")) |> ignore
    peer.response(launch) |> ignore
    let thread = peer.function_stop(function_id(points[0]), "moonbit_main")
    let process = peer.event("process")
    guard process is { "systemProcessId": Number(pid, ..), .. } else {
      fail(process.stringify())
    }
    peer.set_functions([]) |> ignore
    peer.response(peer.send("continue", arguments={ "threadId": thread }))
    |> ignore
    function_id(peer.set_functions(["main"])[0]) |> ignore
    peer.set_functions([]) |> ignore
    peer.disconnect()
    assert_target_gone(pid.to_int())
  })
}
