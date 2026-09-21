///|
async fn LivePeer::continue_to_panic_end(self : LivePeer, thread : Int) -> Json {
  self.response(self.send("continue", arguments={ "threadId": thread }))
  |> ignore
  let next = self.expect(message => {
    message is { "event": String("exited" | "stopped"), .. }
  })
  assert_true(
    (
      next
      is {
        "event": String("exited"),
        "body": { "exitCode": Number(code, ..), .. },
        ..
      } &&
      code != 0
    ) ||
    (
      next
      is {
        "event": String("stopped"),
        "body": {
          "reason": String("exception"),
          "description": String(description),
          ..
        },
        ..
      } &&
      description.contains("SIGABRT")
    ),
    msg=next.stringify(),
  )
  next
}

///|
async test "DAP panic lifecycle keeps source function and internal breakpoints independent" {
  guard toolchain_acceptance_enabled() else { return }
  toolchain_acceptance_mutex.acquire()
  defer toolchain_acceptance_mutex.release()
  let fixture = "\{@fs.realpath(".")}/testdata/dwarf_probe"
  for
    (package_name, statement) in [
      ("panic_stop", "println(fail(value))"),
      ("panic_bounds", "println(access(values, index))"),
      ("panic_context", "println(@probe.fail(value))"),
    ] {
    @async.with_task_group(group => {
      let peer = LivePeer::start(group)
      defer peer.close()
      let source = "\{fixture}/\{package_name}/main.mbt"
      let line = unique_source_line(source, statement)
      let launch = peer.initialize_package("\{fixture}/\{package_name}")
      peer.event("initialized") |> ignore
      peer.response(
        peer.send("setExceptionBreakpoints", arguments={
          "filters": ["moonbit-panic"],
        }),
      )
      |> ignore
      peer.response(
        peer.send("setFunctionBreakpoints", arguments={
          "breakpoints": [{ "name": "main" }],
        }),
      )
      |> ignore
      peer.response(
        peer.send("setBreakpoints", arguments={
          "source": { "path": source },
          "breakpoints": [{ "line": line }],
        }),
      )
      |> ignore
      peer.response(peer.send("configurationDone")) |> ignore
      peer.response(launch) |> ignore
      let main = peer.event("stopped")
      assert_true(
        main is { "reason": String("function breakpoint"), .. },
        msg=main.stringify(),
      )
      peer.response(
        peer.send("setFunctionBreakpoints", arguments={ "breakpoints": [] }),
      )
      |> ignore
      peer.response(
        peer.send("continue", arguments={ "threadId": dap_thread_id(main) }),
      )
      |> ignore
      let source_stop = peer.event("stopped")
      assert_true(
        source_stop is { "reason": String("breakpoint"), .. },
        msg=source_stop.stringify(),
      )
      assert_frame_location(
        peer.top_frame(dap_thread_id(source_stop)),
        source,
        line,
      )
      peer.response(
        peer.send("setBreakpoints", arguments={
          "source": { "path": source },
          "breakpoints": [],
        }),
      )
      |> ignore
      peer.response(
        peer.send("continue", arguments={
          "threadId": dap_thread_id(source_stop),
        }),
      )
      |> ignore
      let panic_stop = peer.event("stopped")
      assert_true(
        panic_stop
        is {
          "reason": String("exception"),
          "description": String("MoonBit panic"),
          "text": String(text),
          ..
        } &&
        text.contains("does not recover"),
        msg=panic_stop.stringify(),
      )
      if package_name == "panic_context" {
        assert_true(
          peer.transcript.any(message => {
            message
            is {
              "event": String("output"),
              "body": { "output": String(text), .. },
              ..
            } &&
            text.contains("panic context example")
          }),
        )
      }
      guard peer.event("process") is { "systemProcessId": Number(pid, ..), .. } else {
        fail("missing target PID")
      }
      let owned = owned_descendants(peer.process.pid)
      assert_true(
        owned.contains(pid.to_int()),
        msg="target must belong to this session",
      )
      assert_true(owned.length() >= 2)
      let old = peer.top_frame(dap_thread_id(panic_stop))
      peer.continue_to_panic_end(dap_thread_id(panic_stop)) |> ignore
      guard old is { "id": id, .. } else { fail(old.stringify()) }
      peer.response(
        peer.send("scopes", arguments={ "frameId": id }),
        success=false,
      )
      |> ignore
      peer.disconnect()
      assert_processes_gone(owned)
    })
  }
}

///|
async test "DAP normal exit has no panic stop and cleans up" {
  guard toolchain_acceptance_enabled() else { return }
  toolchain_acceptance_mutex.acquire()
  defer toolchain_acceptance_mutex.release()
  let fixture = "\{@fs.realpath(".")}/testdata/dwarf_probe"
  @async.with_task_group(group => {
    let peer = LivePeer::start(group)
    defer peer.close()
    let launch = peer.initialize_package("\{fixture}/panic_normal")
    peer.event("initialized") |> ignore
    peer.response(peer.send("configurationDone")) |> ignore
    peer.response(launch) |> ignore
    guard peer.event("process") is { "systemProcessId": Number(pid, ..), .. } else {
      fail("missing target PID")
    }
    assert_true(peer.event("exited") is { "exitCode": Number(0, ..), .. })
    peer.event("terminated") |> ignore
    let owned = owned_descendants(peer.process.pid)
    peer.disconnect()
    assert_processes_gone(owned)
    assert_processes_gone([pid.to_int()])
    assert_false(
      peer.transcript.any(message => {
        message is { "event": String("stopped"), .. }
      }),
    )
    assert_true(
      peer.transcript.any(message => {
        message
        is {
          "event": String("output"),
          "body": { "output": String(text), .. },
          ..
        } &&
        text.contains("panic lifecycle normal exit")
      }),
    )
  })
}

///|
async test "DAP panic continuation preserves actual SIGABRT and Stop cleans up both processes" {
  guard toolchain_acceptance_enabled() else { return }
  toolchain_acceptance_mutex.acquire()
  defer toolchain_acceptance_mutex.release()
  let directory = @fs.tmpdir(prefix="moondbg-dap-panic-signal-")
  defer @fs.rmdir(directory, recursive=true)
  let program = build_panic_signal_probe(directory)
  for continue_first in [false, true] {
    @async.with_task_group(group => {
      let peer = LivePeer::start(group)
      defer peer.close()
      let launch = peer.initialize_launch(program, directory)
      peer.response(peer.send("configurationDone")) |> ignore
      peer.response(launch) |> ignore
      let stop = peer.event("stopped")
      assert_true(
        stop
        is {
          "reason": String("exception"),
          "description": String(description),
          ..
        } &&
        description.has_prefix("MoonBit panic"),
        msg=stop.stringify(),
      )
      guard peer.event("process") is { "systemProcessId": Number(pid, ..), .. } else {
        fail("missing target PID")
      }
      let owned = owned_descendants(peer.process.pid)
      assert_true(owned.contains(pid.to_int()))
      assert_true(owned.length() >= 2)
      if continue_first {
        let next = peer.continue_to_panic_end(dap_thread_id(stop))
        assert_true(
          next is { "event": String("stopped"), .. },
          msg=next.stringify(),
        )
        let frame = peer.top_frame(dap_thread_id(stop))
        assert_false(
          frame is { "presentationHint": String("subtle"), .. },
          msg="panic-only frame hints must expire on SIGABRT",
        )
      }
      peer.disconnect()
      assert_processes_gone(owned)
    })
  }
}
