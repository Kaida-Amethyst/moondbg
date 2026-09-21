///|
async test "REPL break if creates conditioned file and current-frame line breakpoints" {
  guard toolchain_acceptance_enabled() else { return }
  toolchain_acceptance_mutex.acquire()
  defer toolchain_acceptance_mutex.release()
  let (_, moondbg) = require_toolchain()
  let fixture = "\{@fs.realpath(".")}/testdata/dwarf_probe"
  let process = @pty_testkit.PtyProcess::spawn_debug(
    moondbg,
    fixture,
    package_name="conditional",
  )
  defer process.close()
  breakpoint_expect(process, "(moondbg) ", "startup")
  breakpoint_command(process, "b conditional/main.mbt:4 if i = 7", [
    "Use == for equality",
  ])
  breakpoint_command(process, "breakpoints", ["No breakpoints."])
  breakpoint_command(process, "b conditional/main.mbt:4 if i == 7", [
    "Breakpoint 1 pending", "condition: i == 7",
  ])
  breakpoint_command(process, "run", ["Stopped (breakpoint)"])
  breakpoint_command(process, "p i", ["i:", " = 7"])
  breakpoint_command(process, "disable 1", ["Breakpoint 1 disabled."])
  breakpoint_command(process, "b main if i = 9", ["Use == for equality"])
  breakpoint_command(process, "break 4 if i == 9", [
    "Breakpoint 2 verified", "condition: i == 9",
  ])
  breakpoint_command(process, "c", ["Stopped (breakpoint)"])
  breakpoint_command(process, "p i", ["i:", " = 9"])
  breakpoint_command(process, "run", ["Stopped (breakpoint)"])
  breakpoint_command(process, "p i", ["i:", " = 9"])
  breakpoint_command(process, "condition 2", ["condition cleared"])
  breakpoint_command(process, "c", ["Process exited normally (code 0)."])
  breakpoint_quit(process)
}

///|
async test "REPL conditional line breakpoint filters loop and preserves edits on rerun" {
  guard toolchain_acceptance_enabled() else { return }
  toolchain_acceptance_mutex.acquire()
  defer toolchain_acceptance_mutex.release()
  let (_, moondbg) = require_toolchain()
  let fixture = "\{@fs.realpath(".")}/testdata/dwarf_probe"
  let process = @pty_testkit.PtyProcess::spawn_debug(
    moondbg,
    fixture,
    package_name="conditional",
  )
  defer process.close()
  breakpoint_expect(process, "(moondbg) ", "startup")
  breakpoint_command(process, "b conditional/main.mbt:4", [
    "Breakpoint 1 pending",
  ])
  breakpoint_command(process, "condition 1 i == 7", [
    "Breakpoint 1 condition: i == 7",
  ])
  breakpoint_command(process, "run", ["Stopped (breakpoint)"])
  breakpoint_command(process, "p i", ["i:", " = 7"])
  breakpoint_command(process, "condition 1 i = 3", ["Use == for equality"])
  breakpoint_command(process, "breakpoints", ["i == 7"])
  breakpoint_command(process, "run", ["Stopped (breakpoint)"])
  breakpoint_command(process, "p i", ["i:", " = 7"])
  breakpoint_command(process, "condition 1", ["condition cleared"])
  breakpoint_command(process, "c", ["Stopped (breakpoint)"])
  breakpoint_command(process, "p i", ["i:", " = 8"])
  breakpoint_command(process, "condition 1 missing > 0", [
    "condition: missing > 0",
  ])
  breakpoint_command(process, "c", ["breakpoint condition error", "missing"])
  breakpoint_command(process, "p i", ["i:", " = 9"])
  breakpoint_command(process, "condition 1 i == -1", ["condition: i == -1"])
  breakpoint_command(process, "run", ["Process exited normally (code 0)."])
  breakpoint_quit(process)
}

///|
async test "DAP conditional line breakpoint hides false hits and supports live replacement" {
  guard toolchain_acceptance_enabled() else { return }
  toolchain_acceptance_mutex.acquire()
  defer toolchain_acceptance_mutex.release()
  let fixture = "\{@fs.realpath(".")}/testdata/dwarf_probe"
  @async.with_task_group(group => {
    let peer = LivePeer::start(group)
    defer peer.close()
    let launch = peer.initialize_package("\{fixture}/conditional")
    peer.event("initialized") |> ignore
    let source : Json = { "path": "\{fixture}/conditional/main.mbt" }
    let points = peer.response(
      peer.send("setBreakpoints", arguments={
        "source": source,
        "breakpoints": [{ "line": 4, "condition": "i == 7" }],
      }),
    )
    assert_true(
      points is { "breakpoints": [{ "verified": True, .. }], .. },
      msg=points.stringify(),
    )
    peer.response(peer.send("configurationDone")) |> ignore
    peer.response(launch) |> ignore
    let stop = peer.event("stopped")
    let thread = dap_thread_id(stop)
    let stack = peer.response(
      peer.send("stackTrace", arguments={ "threadId": thread }),
    )
    guard stack is { "stackFrames": [{ "id": id, .. }, ..], .. } else {
      fail(stack.stringify())
    }
    let value = peer.evaluate_path(id, "i")
    assert_true(
      value is { "result": String("7"), .. },
      msg="\{stop.stringify()} \{value.stringify()}",
    )
    assert_eq(
      peer.transcript
      .filter(message => message is { "event": String("stopped"), .. })
      .length(),
      1,
    )
    peer.response(
      peer.send("setBreakpoints", arguments={
        "source": source,
        "breakpoints": [{ "line": 4, "condition": "i = 3" }],
      }),
      success=false,
    )
    |> ignore
    peer.response(
      peer.send("setBreakpoints", arguments={
        "source": source,
        "breakpoints": [{ "line": 4, "condition": "missing == 0" }],
      }),
    )
    |> ignore
    peer.response(peer.send("continue", arguments={ "threadId": thread }))
    |> ignore
    let error_stop = peer.event("stopped")
    assert_true(
      error_stop is { "description": String(message), .. } &&
      message.contains("missing"),
      msg=error_stop.stringify(),
    )
    peer.response(
      peer.send("setBreakpoints", arguments={
        "source": source,
        "breakpoints": [{ "line": 4 }],
      }),
    )
    |> ignore
    peer.response(peer.send("continue", arguments={ "threadId": thread }))
    |> ignore
    peer.event("stopped") |> ignore
    peer.response(peer.send("continue", arguments={ "threadId": thread }))
    |> ignore
    assert_true(peer.event("exited") is { "exitCode": Number(0, ..), .. })
    peer.event("terminated") |> ignore
    peer.disconnect()
  })
}

///|
async test "DAP pause and disconnect remain responsive inside an always false condition loop" {
  guard toolchain_acceptance_enabled() else { return }
  toolchain_acceptance_mutex.acquire()
  defer toolchain_acceptance_mutex.release()
  let fixture = "\{@fs.realpath(".")}/testdata/dwarf_probe"
  @async.with_task_group(group => {
    let peer = LivePeer::start(group)
    defer peer.close()
    let launch = peer.initialize_package("\{fixture}/dap_pause")
    peer.event("initialized") |> ignore
    let source : Json = { "path": "\{fixture}/dap_pause/main.mbt" }
    peer.response(
      peer.send("setBreakpoints", arguments={
        "source": source,
        "breakpoints": [{ "line": 5 }],
      }),
    )
    |> ignore
    peer.response(peer.send("configurationDone")) |> ignore
    peer.response(launch) |> ignore
    let thread = dap_thread_id(peer.event("stopped"))
    let descendants = owned_descendants(peer.process.pid)
    peer.response(
      peer.send("setBreakpoints", arguments={
        "source": source,
        "breakpoints": [{ "line": 5, "condition": "counter < 0" }],
      }),
    )
    |> ignore
    for _ in 0..<3 {
      peer.response(peer.send("continue", arguments={ "threadId": thread }))
      |> ignore
      // Leave enough time for repeated internal hits without blocking the DAP
      // loop; the debugger must still accept a pause in any inspection phase.
      @async.sleep(200)
      peer.response(peer.send("pause", arguments={ "threadId": thread }))
      |> ignore
      let stop = peer.event("stopped")
      // A pause can interrupt LLDB's internal single-instruction step over a
      // software breakpoint. Its real trace/step reason must also remain visible.
      assert_true(
        stop is { "reason": String("pause" | "breakpoint" | "step"), .. },
        msg=stop.stringify(),
      )
      let frame = peer.top_frame(thread)
      assert_true(frame is { "id": _, .. }, msg=frame.stringify())
    }
    peer.response(peer.send("continue", arguments={ "threadId": thread }))
    |> ignore
    @async.sleep(200)
    peer.disconnect()
    assert_processes_gone(descendants)
  })
}

///|
async test "false source condition never hides MoonBit panic" {
  guard toolchain_acceptance_enabled() else { return }
  toolchain_acceptance_mutex.acquire()
  defer toolchain_acceptance_mutex.release()
  let fixture = "\{@fs.realpath(".")}/testdata/dwarf_probe"
  @async.with_task_group(group => {
    let peer = LivePeer::start(group)
    defer peer.close()
    let launch = peer.initialize_package("\{fixture}/panic_bounds")
    peer.event("initialized") |> ignore
    peer.response(
      peer.send("setBreakpoints", arguments={
        "source": { "path": "\{fixture}/panic_bounds/main.mbt" },
        "breakpoints": [{ "line": 3, "condition": "index < 0" }],
      }),
    )
    |> ignore
    peer.response(peer.send("configurationDone")) |> ignore
    peer.response(launch) |> ignore
    let stop = peer.event("stopped")
    assert_true(
      stop is { "description": String("MoonBit panic"), .. },
      msg=stop.stringify(),
    )
    peer.disconnect()
  })
  let (_, moondbg) = require_toolchain()
  let process = @pty_testkit.PtyProcess::spawn_debug(
    moondbg,
    fixture,
    package_name="panic_bounds",
  )
  defer process.close()
  breakpoint_expect(process, "(moondbg) ", "startup")
  breakpoint_command(process, "b panic_bounds/main.mbt:3", [
    "Breakpoint 1 pending",
  ])
  breakpoint_command(process, "condition 1 index < 0", ["condition: index < 0"])
  breakpoint_command(process, "run", ["Stopped (MoonBit panic)"])
  breakpoint_quit(process)
}
