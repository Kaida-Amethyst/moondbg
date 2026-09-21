///|
fn variable_reference(value : Json) -> Int raise {
  guard value is { "variablesReference": Number(id, ..), .. } else {
    fail(value.stringify())
  }
  id.to_int()
}

///|
fn named_variable(body : Json, name : String) -> Json raise {
  guard body is { "variables": Array(values), .. } else {
    fail(body.stringify())
  }
  for value in values {
    if value is { "name": String(actual), .. } && actual == name {
      return value
    }
  }
  fail("Missing \{name}: \{body.stringify()}")
}

///|
async fn LivePeer::frame_locals(self : LivePeer, frame : Json) -> Json {
  let scopes = self.response(
    self.send("scopes", arguments={ "frameId": frame }),
  )
  guard scopes is { "scopes": Array([scope, ..]), .. } else {
    fail(scopes.stringify())
  }
  self.children_of(scope)
}

///|
async fn LivePeer::children_of(self : LivePeer, variable : Json) -> Json {
  self.response(
    self.send("variables", arguments={
      "variablesReference": variable_reference(variable),
    }),
  )
}

///|
async test "DAP variable trees inspect frames structs arrays enum payloads and invalidate old handles" {
  guard toolchain_acceptance_enabled() else { return }
  toolchain_acceptance_mutex.acquire()
  defer toolchain_acceptance_mutex.release()
  let (fixture, program, source) = build_dap_control_fixture("dap_variables")
  let first = unique_source_line(source, "let marker = point.x")
  let second = unique_source_line(source, "println(marker)")
  @async.with_task_group(group => {
    let peer = LivePeer::start(group)
    defer peer.close()
    let launch = peer.initialize_launch(program, fixture)
    peer.response(
      peer.send("setBreakpoints", arguments={
        "source": { "path": source },
        "breakpoints": [{ "line": first }, { "line": second }],
      }),
    )
    |> ignore
    peer.response(peer.send("configurationDone")) |> ignore
    peer.response(launch) |> ignore
    let thread = dap_thread_id(peer.event("stopped"))
    let stack = peer.response(
      peer.send("stackTrace", arguments={ "threadId": thread, "levels": 20 }),
    )
    guard stack
      is {
        "stackFrames": Array([{ "id": top, .. }, { "id": caller, .. }, ..]),
        ..
      } else {
      fail(stack.stringify())
    }
    let locals = peer.frame_locals(top)
    let point = named_variable(locals, "point")
    assert_true(
      named_variable(peer.children_of(point), "x")
      is { "value": String("35"), .. },
    )
    let values = named_variable(locals, "values")
    assert_true(
      values
      is {
        "type": String("Array[Double]"),
        "indexedVariables": Number(3, ..),
        ..
      },
      msg=values.stringify(),
    )
    assert_true(
      named_variable(peer.children_of(values), "[0]")
      is { "value": String("1.5"), .. },
    )
    let fixed = named_variable(locals, "fixed")
    assert_true(
      fixed
      is {
        "type": String("FixedArray[Int]"),
        "indexedVariables": Number(1000, ..),
        ..
      },
      msg=fixed.stringify(),
    )
    let tail = peer.response(
      peer.send("variables", arguments={
        "variablesReference": variable_reference(fixed),
        "filter": "indexed",
        "start": 995,
        "count": 5,
      }),
    )
    assert_true(
      named_variable(tail, "[999]") is { "value": String("1000"), .. },
    )
    let ranges = peer.children_of(fixed)
    let range = named_variable(ranges, "[0..99]")
    let page = peer.children_of(range)
    assert_true(named_variable(page, "[99]") is { "value": String("100"), .. })
    let points = peer.children_of(named_variable(locals, "points"))
    let element = named_variable(points, "[1]")
    assert_true(
      named_variable(peer.children_of(element), "y")
      is { "value": String("6"), .. },
    )
    let list = named_variable(locals, "list")
    assert_true(list is { "value": String("Cons"), .. }, msg=list.stringify())
    let payload = peer.children_of(list)
    assert_true(named_variable(payload, ".0") is { "value": String("3"), .. })
    let tail = named_variable(payload, ".1")
    assert_true(tail is { "value": String("Cons"), .. })
    let next = peer.children_of(tail)
    assert_true(named_variable(next, ".0") is { "value": String("2"), .. })
    let last = peer.children_of(named_variable(next, ".1"))
    let empty = named_variable(last, ".1")
    assert_true(
      empty
      is { "value": String("Empty"), "variablesReference": Number(0, ..), .. },
      msg=empty.stringify(),
    )
    let caller_locals = peer.frame_locals(caller)
    assert_true(
      named_variable(caller_locals, "caller_only")
      is { "value": String("700"), .. },
      msg=caller_locals.stringify(),
    )
    // Old tree locators must still point into the original frame after viewing a caller.
    assert_true(
      named_variable(peer.children_of(point), "x")
      is { "value": String("35"), .. },
    )
    peer.response(peer.send("continue", arguments={ "threadId": thread }))
    |> ignore
    peer.event("stopped") |> ignore
    peer.response(
      peer.send("variables", arguments={
        "variablesReference": variable_reference(values),
      }),
      success=false,
    )
    |> ignore
    peer.response(
      peer.send("scopes", arguments={ "frameId": top }),
      success=false,
    )
    |> ignore
    let frame = peer.top_frame(thread)
    guard frame is { "id": fresh, .. } else { fail(frame.stringify()) }
    let locals = peer.frame_locals(fresh)
    let values = named_variable(locals, "values")
    assert_true(
      named_variable(peer.children_of(values), "[0]")
      is { "value": String("42"), .. },
    )
    peer.disconnect()
  })
}
