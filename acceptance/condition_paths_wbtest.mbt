///|
async test "REPL conditions resolve paths Bool and exact wide integers" {
  guard toolchain_acceptance_enabled() else { return }
  toolchain_acceptance_mutex.acquire()
  defer toolchain_acceptance_mutex.release()
  let (_, moondbg) = require_toolchain()
  let fixture = "\{@fs.realpath(".")}/testdata/dwarf_probe"
  let source = "\{fixture}/conditional_paths/main.mbt"
  let line = unique_source_line(source, "let marker = scene.point.x")
  let process = @pty_testkit.PtyProcess::spawn_debug(
    moondbg,
    fixture,
    package_name="conditional_paths",
  )
  defer process.close()
  breakpoint_expect(process, "(moondbg) ", "startup")
  breakpoint_command(process, "b \{source}:\{line} if scene.point.x > 5", [
    "Breakpoint 1 pending", "condition: scene.point.x > 5",
  ])
  for
    (condition, expected) in [
      ("scene.point.x > 5", "6"),
      ("scene.arr[0] == 7", "7"),
      ("scene.line.start.x < limit", "0"),
      ("scene.points[0].x == limit", "7"),
      ("scene.fixed[0] == scene.arr[1]", "exit"),
      ("ready == true", "7"),
      ("ready == flag", "7"),
      ("unsigned == 8", "8"),
      ("signed == -9007199254740993", "1"),
      ("wide == 9007199254740993", "1"),
      ("max64 == 18446744073709551615", "0"),
    ] {
    breakpoint_command(process, "condition 1 \{condition}", [
      "condition: \{condition}",
    ])
    if expected == "exit" {
      breakpoint_command(process, "run", ["Process exited normally (code 0)."])
    } else {
      breakpoint_command(process, "run", ["Stopped (breakpoint)"])
      breakpoint_command(process, "p scene.point.x", [
        "scene.point.x:",
        " = \{expected}",
      ])
    }
  }
  for
    (condition, error) in [
      ("scene.point.x == unsigned", "type mismatch"),
      ("scene.point.x == 2147483648", "Int range"),
      ("ready == 1", "Bool"),
      ("ready < flag", "Bool conditions support only"),
      ("scene.point.missing == 0", "missing"),
      ("scene.point.x < missing", "missing"),
      ("scene.arr[99] == 0", "out of bounds"),
      ("ratio == 1", "Unsupported condition scalar type: Double"),
      ("scene.point == scene.point", "Unsupported condition scalar type"),
    ] {
    breakpoint_command(process, "condition 1 \{condition}", [
      "condition: \{condition}",
    ])
    breakpoint_command(process, "run", ["breakpoint condition error", error])
    breakpoint_command(process, "p scene.point.x", ["scene.point.x:", " = 0"])
  }
  breakpoint_quit(process)
}

///|
async test "DAP conditions share typed path comparison and retain error stops" {
  guard toolchain_acceptance_enabled() else { return }
  toolchain_acceptance_mutex.acquire()
  defer toolchain_acceptance_mutex.release()
  let fixture = "\{@fs.realpath(".")}/testdata/dwarf_probe"
  let source = "\{fixture}/conditional_paths/main.mbt"
  let line = unique_source_line(source, "let marker = scene.point.x")
  for
    (condition, expected, error) in [
      ("scene.point.x > 5", "6", None),
      ("scene.arr[0] == limit", "7", None),
      ("scene.line.start.x < limit", "0", None),
      ("scene.points[0].x == scene.fixed[0]", "0", None),
      ("ready == flag", "7", None),
      ("unsigned == 8", "8", None),
      ("signed == -9007199254740993", "1", None),
      ("wide == 9007199254740993", "1", None),
      ("scene.point.x == unsigned", "0", Some("type mismatch")),
      ("scene.arr[99] == 0", "0", Some("out of bounds")),
      ("scene.point.x == missing", "0", Some("missing")),
    ] {
    @async.with_task_group(group => {
      let peer = LivePeer::start(group)
      defer peer.close()
      let launch = peer.initialize_package("\{fixture}/conditional_paths")
      peer.event("initialized") |> ignore
      peer.response(
        peer.send("setBreakpoints", arguments={
          "source": { "path": source },
          "breakpoints": [{ "line": line, "condition": condition }],
        }),
      )
      |> ignore
      peer.response(peer.send("configurationDone")) |> ignore
      peer.response(launch) |> ignore
      let stop = peer.event("stopped")
      if error is Some(error) {
        assert_true(
          stop is { "description": String(message), .. } &&
          message.contains(error),
          msg="\{condition}: \{stop.stringify()}",
        )
      } else {
        assert_true(
          stop is { "reason": String("breakpoint"), .. },
          msg=stop.stringify(),
        )
        assert_false(
          stop is { "description": String(message), .. } &&
          message.contains("condition error"),
          msg=stop.stringify(),
        )
      }
      let frame = peer.top_frame(dap_thread_id(stop))
      guard frame is { "id": id, .. } else { fail(frame.stringify()) }
      let value = peer.evaluate_path(id, "scene.point.x")
      assert_true(
        value is { "result": String(actual), .. } && actual == expected,
        msg="\{condition}: \{value.stringify()}",
      )
      peer.disconnect()
    })
  }
}
