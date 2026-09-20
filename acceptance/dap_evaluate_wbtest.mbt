///|
async fn LivePeer::evaluate_path(
  self : LivePeer,
  frame : Json,
  expression : String,
  context? : String = "watch",
  success? : Bool = true,
) -> Json {
  self.response(
    self.send("evaluate", arguments={
      "expression": expression,
      "frameId": frame,
      "context": context,
    }),
    success~,
  )
}

///|
async test "DAP evaluate supports hover watch console paths expandable values and fresh frames" {
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
    for context in ["hover", "watch", "repl"] {
      let value = peer.evaluate_path(top, "  point.x  ", context~)
      assert_true(
        value
        is { "result": String("3"), "variablesReference": Number(0, ..), .. },
        msg=value.stringify(),
      )
    }
    for
      (expression, expected) in [
        ("point.y", "4"),
        ("values[0]", "1.5"),
        ("fixed[999]", "1000"),
        ("points[001].x", "5"),
        ("points[1].y", "6"),
      ] {
      let value = peer.evaluate_path(top, expression)
      assert_true(
        value is { "result": String(actual), .. } && actual == expected,
        msg=value.stringify(),
      )
    }
    let point = peer.evaluate_path(top, "points[1]")
    let children = peer.children_of(point)
    let x = named_variable(children, "x")
    assert_true(
      x is { "value": String("5"), "evaluateName": String("points[1].x"), .. },
      msg=x.stringify(),
    )
    let fixed = peer.evaluate_path(top, "fixed")
    assert_true(
      fixed
      is {
        "result": String("length = 1000"),
        "indexedVariables": Number(1000, ..),
        ..
      },
    )
    let tail = peer.response(
      peer.send("variables", arguments={
        "variablesReference": variable_reference(fixed),
        "start": 999,
        "count": 1,
      }),
    )
    assert_true(
      named_variable(tail, "[999]")
      is { "value": String("1000"), "evaluateName": String("fixed[999]"), .. },
    )
    let list = peer.evaluate_path(top, "list")
    assert_true(list is { "result": String("Cons"), .. })
    let payload = peer.children_of(list)
    assert_true(named_variable(payload, ".0") is { "value": String("3"), .. })
    // Positional enum paths aren't part of the grammar yet: don't advertise one.
    guard named_variable(payload, ".1") is Object(fields) else {
      fail("payload")
    }
    assert_false(fields.contains("evaluateName"))
    for
      invalid in [
        "missing", "point.missing", "point.x.y", "point[0]", "values[3]", "values[-1]",
        "values[i]", "point.x+1", "point.x=99", "point()", "p point",
      ] {
      peer.evaluate_path(top, invalid, success=false) |> ignore
    }
    peer.response(
      peer.send("evaluate", arguments={ "expression": "point" }),
      success=false,
    )
    |> ignore
    let caller_value = peer.evaluate_path(caller, "caller_only")
    assert_true(caller_value is { "result": String("700"), .. })
    peer.evaluate_path(top, "caller_only", success=false) |> ignore
    // Rejected writes/calls haven't mutated the object. A caller query hasn't
    // redirected previously returned child handles into that caller's frame.
    assert_true(
      named_variable(peer.children_of(point), "x")
      is { "value": String("5"), .. },
    )
    assert_true(
      peer.evaluate_path(top, "point.x") is { "result": String("3"), .. },
    )
    peer.response(peer.send("continue", arguments={ "threadId": thread }))
    |> ignore
    peer.event("stopped") |> ignore
    peer.evaluate_path(top, "point.x", success=false) |> ignore
    peer.response(
      peer.send("variables", arguments={
        "variablesReference": variable_reference(point),
      }),
      success=false,
    )
    |> ignore
    let frame = peer.top_frame(thread)
    guard frame is { "id": fresh, .. } else { fail(frame.stringify()) }
    assert_true(
      peer.evaluate_path(fresh, "values[0]") is { "result": String("42"), .. },
    )
    peer.disconnect()
  })
}
