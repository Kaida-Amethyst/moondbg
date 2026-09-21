///|
async test "REPL inspects tuples active enum payloads and mixed positional paths" {
  guard toolchain_acceptance_enabled() else { return }
  toolchain_acceptance_mutex.acquire()
  defer toolchain_acceptance_mutex.release()
  let (_, moondbg) = require_toolchain()
  let fixture = "\{@fs.realpath(".")}/testdata/dwarf_probe"
  let source = "\{fixture}/positional_values/main.mbt"
  let ready = unique_source_line(
    source, "let marker = pair.0 // POSITIONAL_READY",
  )
  let changed = unique_source_line(
    source, "println(values.changing is Err(_)) // POSITIONAL_CHANGED",
  )
  let process = @pty_testkit.PtyProcess::spawn_debug(
    moondbg,
    fixture,
    package_name="positional_values",
  )
  defer process.close()
  breakpoint_expect(process, "(moondbg) ", "startup")
  breakpoint_command(process, "b \{source}:\{ready}", ["Breakpoint 1 pending"])
  breakpoint_command(process, "b \{source}:\{changed}", ["Breakpoint 2 pending"])
  breakpoint_command(process, "run", ["Stopped (breakpoint)"])
  for
    (command, expected) in [
      ("p pair", ".0: Int = 42"),
      ("p pair.0", "pair.0: Int = 42"),
      ("p pair.1", "\"tuple🙂\""),
      ("p result", "Ok(Point { x: 3, y: 4 })"),
      ("p result.0", "x: Int = 3"),
      ("p result.0.x", "result.0.x: Int = 3"),
      ("p values.nested.0.1.y", " = 20"),
      ("p items[0].0", " = 11"),
      ("p items[0].1[0:5]", "\"array\""),
      ("p values.numbers.1[1]", " = 22"),
      (
        "p values.nested.1[0]", "Array element access through a positional member is not supported",
      ),
      ("p values.choice.0", " = 9"),
      ("p values.choice.1.y", " = 40"),
      ("p pair.2", "out of bounds"),
      ("p values.empty.0", "Empty has 0 positional member"),
      ("p pair.0.0", "requires a tuple or an enum payload"),
      ("p pair[0]", "not an Array or FixedArray"),
      ("p result.1", "out of bounds"),
      ("p values.changing.0.x", " = 5"),
    ] {
    breakpoint_command(process, command, [expected])
  }
  breakpoint_command(process, "continue", ["Stopped (breakpoint)"])
  breakpoint_command(process, "p values.changing", ["Err(", "changed🙂"])
  breakpoint_command(process, "p values.changing.0", ["String", "changed🙂"])
  breakpoint_command(process, "p values.changing.0.x", ["not a struct"])
  breakpoint_command(process, "continue", ["Process exited normally (code 0)."])
  breakpoint_quit(process)
}

///|
async test "DAP expansion and Watch share positional rules and refresh the active constructor" {
  guard toolchain_acceptance_enabled() else { return }
  toolchain_acceptance_mutex.acquire()
  defer toolchain_acceptance_mutex.release()
  let (fixture, program, source) = build_dap_control_fixture(
    "positional_values",
  )
  let ready = unique_source_line(
    source, "let marker = pair.0 // POSITIONAL_READY",
  )
  let changed = unique_source_line(
    source, "println(values.changing is Err(_)) // POSITIONAL_CHANGED",
  )
  @async.with_task_group(group => {
    let peer = LivePeer::start(group)
    defer peer.close()
    let launch = peer.initialize_launch(program, fixture)
    peer.response(
      peer.send("setBreakpoints", arguments={
        "source": { "path": source },
        "breakpoints": [{ "line": ready }, { "line": changed }],
      }),
    )
    |> ignore
    peer.response(peer.send("configurationDone")) |> ignore
    peer.response(launch) |> ignore
    let thread = dap_thread_id(peer.event("stopped"))
    guard peer.top_frame(thread) is { "id": id, .. } else { fail("frame") }
    let pair = peer.evaluate_path(id, "pair")
    let pair_children = peer.children_of(pair)
    assert_true(
      named_variable(pair_children, ".0")
      is { "value": String("42"), "evaluateName": String("pair.0"), .. },
    )
    let result = peer.evaluate_path(id, "result")
    assert_true(
      result
      is {
        "result": String("Ok(Point { x: 3, y: 4 })"),
        "type": String("Result[Point, String]"),
        ..
      },
    )
    let point = named_variable(peer.children_of(result), ".0")
    let x = named_variable(peer.children_of(point), "x")
    assert_true(
      x is { "value": String("3"), "evaluateName": String("result.0.x"), .. },
    )
    for context in ["watch", "hover", "repl"] {
      assert_true(
        peer.evaluate_path(id, "pair.0", context~)
        is { "result": String("42"), .. },
      )
      assert_true(
        peer.evaluate_path(id, "result.0.x", context~)
        is { "result": String("3"), .. },
      )
    }
    let numbers = peer.evaluate_path(id, "values.numbers.1")
    guard peer.children_of(numbers) is { "variables": Array(elements), .. } else {
      fail("array children")
    }
    for element in elements {
      guard element
        is { "evaluateName": String(path), "value": String(expected), .. } else {
        fail("array child locator")
      }
      assert_true(
        peer.evaluate_path(id, path) is { "result": String(actual), .. } &&
        actual == expected,
      )
    }
    for
      (path, expected) in [
        ("values.nested.0.1.y", "20"),
        ("items[0].0", "11"),
        ("values.choice.1.x", "30"),
      ] {
      assert_true(
        peer.evaluate_path(id, path) is { "result": String(value), .. } &&
        value == expected,
        msg=path,
      )
    }
    for
      path in [
        "pair.2", "result.1", "pair.0.0", "pair[0]", "values.empty.0", "values.nested.1[0]",
      ] {
      peer.evaluate_path(id, path, success=false) |> ignore
    }
    let previous = peer.evaluate_path(id, "values.changing.0")
    peer.response(peer.send("continue", arguments={ "threadId": thread }))
    |> ignore
    peer.event("stopped") |> ignore
    peer.response(
      peer.send("variables", arguments={
        "variablesReference": variable_reference(previous),
      }),
      success=false,
    )
    |> ignore
    guard peer.top_frame(thread) is { "id": fresh, .. } else { fail("frame") }
    let current = peer.evaluate_path(fresh, "values.changing")
    assert_true(
      current is { "result": String(value), .. } &&
      value.has_prefix("Err(") &&
      value.contains("changed🙂"),
    )
    let payload = named_variable(peer.children_of(current), ".0")
    assert_true(
      payload
      is {
        "type": String("String"),
        "evaluateName": String("values.changing.0"),
        "value": String(value),
        ..
      } &&
      value.contains("changed🙂"),
    )
    assert_true(
      peer.evaluate_path(fresh, "values.changing.0")
      is { "type": String("String"), "result": String(value), .. } &&
      value.contains("changed🙂"),
    )
    peer.evaluate_path(fresh, "values.changing.0.x", success=false) |> ignore
    peer.disconnect()
  })
}
