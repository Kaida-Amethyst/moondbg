///|
async test "DAP panic defaults on selects project context and exposes real variables" {
  guard toolchain_acceptance_enabled() else { return }
  toolchain_acceptance_mutex.acquire()
  defer toolchain_acceptance_mutex.release()
  let fixture = "\{@fs.realpath(".")}/testdata/dwarf_probe"
  // An omitted request must honor the default; explicit repeated enabling must
  // install only one independent breakpoint, even across function replacements.
  for explicit_filter in [false, true] {
    @async.with_task_group(group => {
      let peer = LivePeer::start(group)
      defer peer.close()
      let launch = peer.initialize_package("\{fixture}/panic_context")
      peer.event("initialized") |> ignore
      if explicit_filter {
        for _ in 0..<2 {
          let result = peer.response(
            peer.send("setExceptionBreakpoints", arguments={
              "filters": ["moonbit-panic"],
            }),
          )
          assert_true(
            result is { "breakpoints": [{ "verified": True, .. }], .. },
            msg=result.stringify(),
          )
        }
      }
      peer.response(
        peer.send("setFunctionBreakpoints", arguments={ "breakpoints": [] }),
      )
      |> ignore
      peer.response(peer.send("configurationDone")) |> ignore
      peer.response(launch) |> ignore
      let stop = peer.event("stopped")
      assert_true(
        stop
        is {
          "reason": String("exception"),
          "description": String("MoonBit panic"),
          ..
        },
        msg=stop.stringify(),
      )
      let thread = dap_thread_id(stop)
      let stack = peer.response(
        peer.send("stackTrace", arguments={ "threadId": thread, "levels": 20 }),
      )
      guard stack is { "stackFrames": Array(frames), .. } else {
        fail(stack.stringify())
      }
      assert_true(
        frames[0]
        is { "name": String(name), "presentationHint": String("subtle"), .. } &&
        name.has_prefix("moonbit_panic"),
        msg=stack.stringify(),
      )
      guard frames.filter(frame => {
          frame is { "presentationHint": String("normal"), .. }
        })
        is [frame, ..] else {
        fail(stack.stringify())
      }
      assert_frame_location(frame, "\{fixture}/panic_context_lib/fail.mbt", 4)
      guard frame is { "id": id, .. } else { fail(frame.stringify()) }
      let locals = peer.frame_locals(id)
      assert_true(
        named_variable(locals, "value") is { "value": String("42"), .. },
        msg=locals.stringify(),
      )
      assert_true(
        peer.evaluate_path(id, "value") is { "result": String("42"), .. },
      )
      // Disabling during a stop deletes only our internal breakpoint. Signals
      // retain LLDB's policy; disconnect does not need to wait for termination.
      peer.response(
        peer.send("setExceptionBreakpoints", arguments={ "filters": [] }),
      )
      |> ignore
      peer.disconnect()
    })
  }
}

///|
async test "DAP disabling panic at launch preserves user breakpoints and reenabling works" {
  guard toolchain_acceptance_enabled() else { return }
  toolchain_acceptance_mutex.acquire()
  defer toolchain_acceptance_mutex.release()
  let fixture = "\{@fs.realpath(".")}/testdata/dwarf_probe"
  for reenable in [false, true] {
    @async.with_task_group(group => {
      let peer = LivePeer::start(group)
      defer peer.close()
      let launch = peer.initialize_package("\{fixture}/panic_context")
      peer.event("initialized") |> ignore
      peer.response(
        peer.send("setExceptionBreakpoints", arguments={ "filters": [] }),
      )
      |> ignore
      peer.response(
        peer.send("setFunctionBreakpoints", arguments={
          "breakpoints": [{ "name": "main" }],
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
      if reenable {
        peer.response(
          peer.send("setExceptionBreakpoints", arguments={
            "filters": ["moonbit-panic"],
          }),
        )
        |> ignore
      }
      peer.response(
        peer.send("continue", arguments={ "threadId": dap_thread_id(main) }),
      )
      |> ignore
      if reenable {
        assert_true(
          peer.event("stopped")
          is { "description": String("MoonBit panic"), .. },
        )
      } else {
        let next = peer.expect(message => {
          message is { "event": String("exited" | "stopped"), .. }
        })
        // Depending on runtime configuration it exits or aborts. A SIGABRT is
        // not relabelled and is deliberately not masked by the panic checkbox.
        assert_true(
          next is { "event": String("exited"), .. } ||
          (
            next
            is {
              "event": String("stopped"),
              "body": { "description": String(description), .. },
              ..
            } &&
            description.contains("SIGABRT")
          ),
          msg=next.stringify(),
        )
      }
      peer.disconnect()
    })
  }
}
