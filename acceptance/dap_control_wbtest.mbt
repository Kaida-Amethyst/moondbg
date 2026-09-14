///|
async fn build_dap_control_fixture(
  package_name : String,
) -> (String, String, String) {
  let (moon, _) = require_toolchain()
  let fixture = "\{@fs.realpath(".")}/testdata/dwarf_probe"
  let (code, _, stderr) = @process.collect_output(
    moon,
    ["run", package_name, "--build-only", "--target", "native", "-g"],
    cwd=fixture,
    inherit_env=true,
  )
  assert_eq(code, 0, msg=stderr.text())
  (
    fixture,
    "\{fixture}/_build/native/debug/build/\{package_name}/\{package_name}.exe",
    "\{fixture}/\{package_name}/main.mbt",
  )
}

///|
async fn LivePeer::top_frame(self : LivePeer, thread : Int) -> Json {
  let stack = self.response(
    self.send("stackTrace", arguments={
      "threadId": thread,
      "startFrame": 0,
      "levels": 20,
    }),
  )
  guard stack is { "stackFrames": Array([frame, ..]), .. } else {
    fail(stack.stringify())
  }
  frame
}

///|
async fn assert_frame_location(
  frame : Json,
  source : String,
  line : Int,
) -> Unit {
  guard frame
    is {
      "line": Number(actual, ..),
      "source": { "path": String(path), .. },
      ..
    } else {
    fail(frame.stringify())
  }
  assert_eq(@fs.realpath(path), @fs.realpath(source))
  assert_eq(actual.to_int(), line, msg=frame.stringify())
}

///|
async test "live DAP next stepIn and stepOut navigate MoonBit source frames" {
  guard toolchain_acceptance_enabled() else { return }
  toolchain_acceptance_mutex.acquire()
  defer toolchain_acceptance_mutex.release()
  let (fixture, program, source) = build_dap_control_fixture("dap_steps")
  let initial_line = unique_source_line(source, "let second = first + 2")
  let call_line = unique_source_line(source, "let result = increment(second)")
  let callee_line = unique_source_line(source, "let result = value + 1")
  @async.with_task_group(group => {
    let peer = LivePeer::start(group)
    defer peer.close()
    let launch = peer.initialize_launch(program, fixture)
    let points = peer.response(
      peer.send("setBreakpoints", arguments={
        "source": { "path": source },
        "breakpoints": [{ "line": initial_line }],
      }),
    )
    assert_true(points is { "breakpoints": [{ "verified": True, .. }], .. })
    peer.response(peer.send("configurationDone")) |> ignore
    peer.response(launch) |> ignore
    let process = peer.event("process")
    guard process is { "systemProcessId": Number(pid, ..), .. } else {
      fail(process.stringify())
    }
    let thread = dap_thread_id(peer.event("stopped"))
    assert_frame_location(peer.top_frame(thread), source, initial_line)
    peer.response(peer.send("next", arguments={ "threadId": thread })) |> ignore
    let stop = peer.event("stopped")
    assert_true(stop is { "reason": String("step"), .. }, msg=stop.stringify())
    let thread = dap_thread_id(stop)
    assert_frame_location(peer.top_frame(thread), source, call_line)
    peer.response(peer.send("stepIn", arguments={ "threadId": thread }))
    |> ignore
    let thread = dap_thread_id(peer.event("stopped"))
    let frame = peer.top_frame(thread)
    assert_frame_location(frame, source, callee_line)
    assert_true(
      frame is { "name": String(name), .. } && name.contains("increment"),
    )
    peer.response(peer.send("stepOut", arguments={ "threadId": thread }))
    |> ignore
    let thread = dap_thread_id(peer.event("stopped"))
    let frame = peer.top_frame(thread)
    assert_true(
      frame is { "name": String("moonbit_main"), .. },
      msg=frame.stringify(),
    )
    // LLDB may stop at the caller's call-site or the following statement.
    guard frame is { "line": Number(line, ..), .. } else {
      fail(frame.stringify())
    }
    assert_true(line.to_int() == call_line || line.to_int() == call_line + 1)
    assert_frame_location(frame, source, line.to_int())
    peer.response(peer.send("continue", arguments={ "threadId": thread }))
    |> ignore
    assert_true(peer.event("exited") is { "exitCode": Number(0, ..), .. })
    peer.event("terminated") |> ignore
    peer.disconnect()
    assert_target_gone(pid.to_int())
  })
}

///|
async test "live DAP pauses a running MoonBit loop repeatedly and cleans up" {
  guard toolchain_acceptance_enabled() else { return }
  toolchain_acceptance_mutex.acquire()
  defer toolchain_acceptance_mutex.release()
  let (fixture, program, source) = build_dap_control_fixture("dap_pause")
  for disconnect_while_running in [false, true] {
    @async.with_task_group(group => {
      let peer = LivePeer::start(group)
      defer peer.close()
      let launch = peer.initialize_launch(program, fixture)
      // Reach user code before pausing: immediately after launch LLDB can still
      // be stopped on an internal dynamic-loader breakpoint.
      let loop_line = unique_source_line(
        source, "counter = (counter + 1) % 1000000",
      )
      peer.response(
        peer.send("setBreakpoints", arguments={
          "source": { "path": source },
          "breakpoints": [{ "line": loop_line }],
        }),
      )
      |> ignore
      peer.response(peer.send("configurationDone")) |> ignore
      peer.response(launch) |> ignore
      let process = peer.event("process")
      guard process is { "systemProcessId": Number(pid, ..), .. } else {
        fail(process.stringify())
      }
      let thread = dap_thread_id(peer.event("stopped"))
      peer.response(
        peer.send("setBreakpoints", arguments={
          "source": { "path": source },
          "breakpoints": [],
        }),
      )
      |> ignore
      peer.response(peer.send("continue", arguments={ "threadId": thread }))
      |> ignore
      for iteration in 0..<2 {
        peer.response(peer.send("pause", arguments={ "threadId": thread }))
        |> ignore
        let stop = peer.event("stopped")
        assert_true(
          stop is { "reason": String("pause"), .. },
          msg=stop.stringify(),
        )
        let frame = peer.top_frame(dap_thread_id(stop))
        guard frame is { "source": { "path": String(path), .. }, .. } else {
          fail(frame.stringify())
        }
        assert_eq(@fs.realpath(path), @fs.realpath(source))
        peer.response(
          peer.send("pause", arguments={ "threadId": thread }),
          success=false,
        )
        |> ignore
        if iteration == 0 || disconnect_while_running {
          // Step-out cannot complete in this infinite function. The next
          // pause must still interrupt the outstanding step plan.
          let command = if iteration == 0 && !disconnect_while_running {
            "stepOut"
          } else {
            "continue"
          }
          peer.response(peer.send(command, arguments={ "threadId": thread }))
          |> ignore
        }
      }
      peer.disconnect()
      assert_target_gone(pid.to_int())
    })
  }
}
