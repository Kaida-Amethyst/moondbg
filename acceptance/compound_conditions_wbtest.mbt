///|
async test "REPL compound function conditions survive updates disable rerun and generic instances" {
  guard toolchain_acceptance_enabled() else { return }
  toolchain_acceptance_mutex.acquire()
  defer toolchain_acceptance_mutex.release()
  let (_, moondbg) = require_toolchain()
  let fixture = "\{@fs.realpath(".")}/testdata/dwarf_probe"
  let process = @pty_testkit.PtyProcess::spawn_debug(
    moondbg,
    fixture,
    package_name="conditional_functions",
  )
  defer process.close()
  breakpoint_expect(process, "(moondbg) ", "startup")
  breakpoint_command(process, "b probe if i >= 3 && i < 8", [
    "pending", "condition: i >= 3 && i < 8",
  ])
  breakpoint_command(process, "run", ["Stopped (breakpoint)"])
  breakpoint_command(process, "p i", ["i:", " = 3"])
  breakpoint_command(process, "condition 1 i == 7 && (i > 0 || missing == 0)", [
    "condition:",
  ])
  breakpoint_command(process, "c", ["Stopped (breakpoint)"])
  breakpoint_command(process, "p i", ["i:", " = 7"])
  breakpoint_command(process, "disable 1", ["disabled"])
  breakpoint_command(process, "run", ["Process exited normally (code 0)."])
  breakpoint_command(process, "enable 1", ["enabled"])
  breakpoint_command(process, "run", ["Stopped (breakpoint)"])
  breakpoint_command(process, "p i", ["i:", " = 7"])
  breakpoint_command(process, "delete 1", ["deleted"])
  breakpoint_command(process, "b identity if !(value != 7)", [
    "verified", "condition: !(value != 7)",
  ])
  breakpoint_command(process, "breakpoints", ["identity", "!(value != 7)"])
  breakpoint_command(process, "c", ["Stopped (breakpoint)"])
  breakpoint_command(process, "p value", ["value:", " = 7"])
  breakpoint_command(process, "c", ["Stopped (breakpoint)"])
  breakpoint_command(process, "p value", ["value:", " = 7"])
  breakpoint_command(process, "c", [
    "breakpoint condition error", "Unsupported condition scalar type: Double",
  ])
  breakpoint_command(process, "p value", ["value:", " = 1.5"])
  breakpoint_command(process, "condition 2", ["condition cleared"])
  breakpoint_command(process, "c", ["Process exited normally (code 0)."])
  breakpoint_command(process, "run", ["Stopped (breakpoint)"])
  breakpoint_command(process, "p value", ["value:", " = 1"])
  breakpoint_quit(process)
}

///|
async fn LivePeer::conditioned_functions(
  self : LivePeer,
  points : Array[Json],
) -> Array[Json] {
  let body = self.response(
    self.send("setFunctionBreakpoints", arguments={ "breakpoints": points }),
  )
  guard body is { "breakpoints": Array(installed), .. } else {
    fail(body.stringify())
  }
  installed
}

///|
async fn LivePeer::condition_value(
  self : LivePeer,
  stop : Json,
  path : String,
  expected : String,
) -> Unit {
  let frame = self.top_frame(dap_thread_id(stop))
  guard frame is { "id": id, .. } else { fail(frame.stringify()) }
  let value = self.evaluate_path(id, path)
  assert_true(
    value is { "result": String(actual), .. } && actual == expected,
    msg=value.stringify(),
  )
}

///|
async test "DAP compound function conditions update in place and generic errors remain inspectable" {
  guard toolchain_acceptance_enabled() else { return }
  toolchain_acceptance_mutex.acquire()
  defer toolchain_acceptance_mutex.release()
  let fixture = "\{@fs.realpath(".")}/testdata/dwarf_probe"
  @async.with_task_group(group => {
    let peer = LivePeer::start(group)
    defer peer.close()
    let launch = peer.initialize_package("\{fixture}/conditional_functions")
    peer.event("initialized") |> ignore
    let points = peer.conditioned_functions([
      { "name": "probe", "condition": "i >= 3 && i < 8" },
    ])
    let id = function_id(points[0])
    peer.response(peer.send("configurationDone")) |> ignore
    peer.response(launch) |> ignore
    let first = peer.event("stopped")
    assert_true(
      first is { "reason": String("function breakpoint"), .. },
      msg=first.stringify(),
    )
    peer.condition_value(first, "i", "3")
    let points = peer.conditioned_functions([
      { "name": "probe", "condition": "i == 7 || (i < 0 && missing == 0)" },
    ])
    assert_eq(function_id(points[0]), id)
    peer.response(
      peer.send("continue", arguments={ "threadId": dap_thread_id(first) }),
    )
    |> ignore
    let second = peer.event("stopped")
    peer.condition_value(second, "i", "7")
    let points = peer.conditioned_functions([
      { "name": "identity", "condition": "!(value != 7)" },
    ])
    let generic = function_id(points[0])
    assert_true(
      points[0] is { "message": String(text), .. } &&
      text.contains("3 function"),
      msg=points[0].stringify(),
    )
    for expected in ["7", "7", "1.5"] {
      peer.response(
        peer.send("continue", arguments={ "threadId": dap_thread_id(second) }),
      )
      |> ignore
      let stop = peer.event("stopped")
      assert_true(
        stop
        is {
          "reason": String("function breakpoint"),
          "hitBreakpointIds": Array(ids),
          ..
        } &&
        ids.contains(Json(generic)),
        msg=stop.stringify(),
      )
      peer.condition_value(stop, "value", expected)
      if expected == "1.5" {
        assert_true(
          stop is { "description": String(text), .. } &&
          text.contains("Unsupported condition scalar type: Double"),
          msg=stop.stringify(),
        )
      } else {
        assert_false(
          stop is { "description": String(text), .. } &&
          text.contains("condition error"),
          msg=stop.stringify(),
        )
      }
    }
    peer.conditioned_functions([]) |> ignore
    peer.response(
      peer.send("continue", arguments={ "threadId": dap_thread_id(second) }),
    )
    |> ignore
    assert_true(peer.event("exited") is { "exitCode": Number(0, ..), .. })
    peer.event("terminated") |> ignore
    peer.disconnect()
  })
}

///|
async test "DAP source conditions short circuit missing paths and preserve unconditional function stops" {
  guard toolchain_acceptance_enabled() else { return }
  toolchain_acceptance_mutex.acquire()
  defer toolchain_acceptance_mutex.release()
  let fixture = "\{@fs.realpath(".")}/testdata/dwarf_probe"
  let source = "\{fixture}/conditional_functions/main.mbt"
  let line = unique_source_line(source, "let result = i + 1")
  @async.with_task_group(group => {
    let peer = LivePeer::start(group)
    defer peer.close()
    let launch = peer.initialize_package("\{fixture}/conditional_functions")
    peer.event("initialized") |> ignore
    peer.response(
      peer.send("setBreakpoints", arguments={
        "source": { "path": source },
        "breakpoints": [{ "line": line, "condition": "i < 0 && missing == 0" }],
      }),
    )
    |> ignore
    peer.conditioned_functions([{ "name": "probe" }]) |> ignore
    peer.response(peer.send("configurationDone")) |> ignore
    peer.response(launch) |> ignore
    let first = peer.event("stopped")
    peer.condition_value(first, "i", "0")
    peer.conditioned_functions([]) |> ignore
    peer.response(
      peer.send("setBreakpoints", arguments={
        "source": { "path": source },
        "breakpoints": [
          {
            "line": line,
            "condition": "(i >= 3 && i < 4) || (i < 0 && missing == 0)",
          },
        ],
      }),
    )
    |> ignore
    peer.response(
      peer.send("continue", arguments={ "threadId": dap_thread_id(first) }),
    )
    |> ignore
    let stop = peer.event("stopped")
    peer.condition_value(stop, "i", "3")
    peer.response(
      peer.send("continue", arguments={ "threadId": dap_thread_id(stop) }),
    )
    |> ignore
    assert_true(peer.event("exited") is { "exitCode": Number(0, ..), .. })
    peer.event("terminated") |> ignore
    peer.disconnect()
  })
}
