///|
async test "REPL bounded nested summaries do not restrict explicit paths" {
  guard toolchain_acceptance_enabled() else { return }
  toolchain_acceptance_mutex.acquire()
  defer toolchain_acceptance_mutex.release()
  let (_, moondbg) = require_toolchain()
  let fixture = "\{@fs.realpath(".")}/testdata/dwarf_probe"
  let source = "\{fixture}/value_summaries/main.mbt"
  let ready = unique_source_line(source, "let marker = 1 // SUMMARY_READY")
  let process = @pty_testkit.PtyProcess::spawn_debug(
    moondbg,
    fixture,
    package_name="value_summaries",
  )
  defer process.close()
  breakpoint_expect(process, "(moondbg) ", "startup")
  breakpoint_command(process, "b \{source}:\{ready}", ["Breakpoint 1 pending"])
  breakpoint_command(process, "run", ["Stopped (breakpoint)"])
  for
    (command, expected) in [
      ("p item", "Item(Point { x: 1, y: 2 })"),
      ("p nested", "Nested(Envelope { point: Point { … } })"),
      ("p many", "Many(1, 2, 3, 4, …)"),
      ("p text", "Text(\"🙂🙂"),
      ("p points", "Points(Array[Point] with length = 2)"),
      ("p nested.0.point.x", " = 3"),
      ("p many.4", " = 5"),
      ("p many.5.x", " = 6"),
      ("p text.0[0:4]", "\"🙂🙂\""),
      (
        "p missing", "Cannot distinguish an out-of-scope variable from missing debug information.",
      ),
    ] {
    breakpoint_command(process, command, [expected])
  }
  breakpoint_command(process, "continue", ["Process exited normally (code 0)."])
  breakpoint_quit(process)
}

///|
async test "DAP summary budgets keep all child handles accessible" {
  guard toolchain_acceptance_enabled() else { return }
  toolchain_acceptance_mutex.acquire()
  defer toolchain_acceptance_mutex.release()
  let (fixture, program, source) = build_dap_control_fixture("value_summaries")
  let ready = unique_source_line(source, "let marker = 1 // SUMMARY_READY")
  @async.with_task_group(group => {
    let peer = LivePeer::start(group)
    defer peer.close()
    let launch = peer.initialize_launch(program, fixture)
    peer.response(
      peer.send("setBreakpoints", arguments={
        "source": { "path": source },
        "breakpoints": [{ "line": ready }],
      }),
    )
    |> ignore
    peer.response(peer.send("configurationDone")) |> ignore
    peer.response(launch) |> ignore
    let thread = dap_thread_id(peer.event("stopped"))
    guard peer.top_frame(thread) is { "id": id, .. } else { fail("frame") }
    for
      (path, expected) in [
        ("item", "Item(Point { x: 1, y: 2 })"),
        ("nested", "Nested(Envelope { point: Point { … } })"),
        ("many", "Many(1, 2, 3, 4, …)"),
        ("points", "Points(Array[Point] with length = 2)"),
        ("nested.0.point.x", "3"),
        ("many.4", "5"),
        ("many.5.x", "6"),
      ] {
      let value = peer.evaluate_path(id, path)
      assert_true(
        value is { "result": String(actual), .. } && actual == expected,
        msg=value.stringify(),
      )
    }
    guard peer.evaluate_path(id, "text") is { "result": String(text), .. } else {
      fail("text preview")
    }
    assert_eq(text.iter().count(), 160)
    assert_true(text.has_suffix("…"))
    let many = peer.evaluate_path(id, "many")
    guard peer.children_of(many) is { "variables": Array(children), .. } else {
      fail("members")
    }
    assert_eq(children.length(), 6)
    let point = children[5]
    assert_true(
      point
      is { "name": String(".5"), "value": String("Point { x: 6, y: 7 }"), .. },
    )
    assert_true(
      named_variable(peer.children_of(point), "x")
      is { "value": String("6"), "evaluateName": String("many.5.x"), .. },
    )
    let nested = peer.evaluate_path(id, "nested")
    let envelope = named_variable(peer.children_of(nested), ".0")
    let inner = named_variable(peer.children_of(envelope), "point")
    assert_true(
      named_variable(peer.children_of(inner), "x")
      is { "value": String("3"), .. },
    )
    peer.evaluate_path(id, "missing", success=false) |> ignore
    peer.disconnect()
  })
}
