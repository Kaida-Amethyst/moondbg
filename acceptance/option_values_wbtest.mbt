///|
// Experimental compiler contract; keep stable toolchain acceptance independent.
// See docs/option_view.md before enabling or updating these expectations.
fn option_view_acceptance_enabled() -> Bool {
  toolchain_acceptance_enabled() &&
  @env.get_env_var("MOONDBG_OPTION_VIEW_ACCEPTANCE") == Some("1")
}

///|
async test "REPL inspects optimized boxed and nested Options using the compiler contract" {
  guard option_view_acceptance_enabled() else { return }
  toolchain_acceptance_mutex.acquire()
  defer toolchain_acceptance_mutex.release()
  let (_, moondbg) = require_toolchain()
  let fixture = "\{@fs.realpath(".")}/testdata/dwarf_probe"
  let source = "\{fixture}/option_values/main.mbt"
  let ready = unique_source_line(source, "println(123) // OPTION_READY")
  let changed = unique_source_line(source, "println(456) // OPTION_CHANGED")
  let process = @pty_testkit.PtyProcess::spawn_debug(
    moondbg,
    fixture,
    package_name="option_values",
  )
  defer process.close()
  breakpoint_expect(process, "(moondbg) ", "startup")
  breakpoint_command(process, "b \{source}:\{ready}", ["Breakpoint 1 pending"])
  breakpoint_command(process, "b \{source}:\{changed}", ["Breakpoint 2 pending"])
  breakpoint_command(process, "run", ["Stopped (breakpoint)"])
  for
    (command, expected) in [
      ("p argument", "Some(42)"),
      ("p local", "Some(23)"),
      ("p changing_int", "Some(12)"),
      ("p changing_point.0.x", " = 30"),
      ("p values.integer", "Some(7)"),
      ("p values.negative.0", " = -2147483648"),
      ("p values.unsigned.0", " = 4294967295"),
      ("p values.absent", "None"),
      ("p values.absent.0", "None has 0 positional member"),
      ("p values.point", "Some(Point { x: 3, y: 4 })"),
      ("p values.point.0.x", " = 3"),
      ("p values.no_point", "None"),
      ("p values.no_point.0", "None has 0 positional member"),
      ("p values.nested.0", "Some(9)"),
      ("p values.nested.0.0", " = 9"),
      ("p values.inner_none.0", "None"),
      ("p values.inner_none.0.0", "None has 0 positional member"),
      ("p values.outer_none", "None"),
      ("p values.nested_point.0.0.y", " = 20"),
      ("p values.flag", "Some(true)"),
      ("p values.no_flag", "None"),
      ("p values.double", "Some(1.5)"),
      ("p values.text.0", "option🙂"),
      ("p values.items[0].0", " = 11"),
      ("p values.items[1]", "None"),
      ("p values.changing.0.x", " = 5"),
      ("locals", "argument: Option[Int] = Some"),
    ] {
    breakpoint_command(process, command, [expected])
  }
  breakpoint_command(process, "continue", ["Stopped (breakpoint)"])
  breakpoint_command(process, "p values.changing", ["None"])
  breakpoint_command(process, "p changing_int", ["None"])
  breakpoint_command(process, "p changing_point", ["None"])
  breakpoint_command(process, "p values.changing.0", [
    "None has 0 positional member",
  ])
  breakpoint_command(process, "continue", ["Process exited normally (code 0)."])
  breakpoint_quit(process)
}

///|
async test "DAP Option children Watch and stop lifetime share one representation" {
  guard option_view_acceptance_enabled() else { return }
  toolchain_acceptance_mutex.acquire()
  defer toolchain_acceptance_mutex.release()
  let (fixture, program, source) = build_dap_control_fixture("option_values")
  let ready = unique_source_line(source, "println(123) // OPTION_READY")
  let changed = unique_source_line(source, "println(456) // OPTION_CHANGED")
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
    let some = peer.evaluate_path(id, "values.integer")
    assert_true(
      some is { "result": String("Some(7)"), "type": String("Option[Int]"), .. },
    )
    let payload = named_variable(peer.children_of(some), ".0")
    assert_true(
      payload
      is {
        "value": String("7"),
        "evaluateName": String("values.integer.0"),
        ..
      },
    )
    for
      path in [
        "values.absent", "values.no_point", "values.inner_none.0", "values.outer_none",
        "values.no_flag",
      ] {
      let none = peer.evaluate_path(id, path)
      assert_true(
        none
        is { "result": String("None"), "variablesReference": Number(0, ..), .. },
        msg=path,
      )
      peer.evaluate_path(id, "\{path}.0", success=false) |> ignore
    }
    for
      (path, expected) in [
        ("values.point.0.x", "3"),
        ("values.nested.0.0", "9"),
        ("values.nested_point.0.0.y", "20"),
        ("values.items[0].0", "11"),
      ] {
      for context in ["watch", "hover", "repl"] {
        assert_true(
          peer.evaluate_path(id, path, context~)
          is { "result": String(value), .. } &&
          value == expected,
          msg=path,
        )
      }
    }
    let previous = peer.evaluate_path(id, "values.changing")
    let point = named_variable(peer.children_of(previous), ".0")
    assert_true(
      named_variable(peer.children_of(point), "x")
      is { "value": String("5"), .. },
    )
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
    assert_true(
      peer.evaluate_path(fresh, "values.changing")
      is { "result": String("None"), "variablesReference": Number(0, ..), .. },
    )
    peer.evaluate_path(fresh, "values.changing.0", success=false) |> ignore
    peer.disconnect()
  })
}
