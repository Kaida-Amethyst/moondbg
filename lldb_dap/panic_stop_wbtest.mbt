///|
async test "runtime breakpoint is labeled panic only at the top frame" {
  for
    (reason, top, expected) in [
      ("breakpoint", "moonbit_panic", "MoonBit panic"),
      ("breakpoint", "moonbit_panic [opt]", "MoonBit panic"),
      ("breakpoint", "other_function", "breakpoint"),
      ("exception", "moonbit_panic", "exception"),
    ] {
    @async.with_task_group(async fn(group) {
      let script = stopped_execution_script(17000)
      script[4] = scripted_event(17004, "stopped", {
        "reason": reason,
        "threadId": 1,
      })
      script[5] = scripted_response(17005, 4, "stackTrace", {
        "stackFrames": [
          {
            "id": 40,
            "name": top,
            "line": 169,
            "source": { "path": "/tmp/backtrace.c" },
          },
          {
            "id": 41,
            "name": "moonbit_main",
            "line": 4,
            "source": { "path": "/tmp/main.mbt" },
          },
        ],
        "totalFrames": 2,
      })
      let transport = @dap_testkit.ScriptedTransport::new(script)
      let session = LldbDapSession::start_with_dispatcher_factory(group, () => {
        @dap.DapDispatcher::from_transport(transport.as_transport())
      })
      defer session.close()
      guard session.run("/tmp/program") is @debugger.Stopped(snapshot) else {
        fail("expected a stopped program")
      }
      assert_eq(snapshot.reason(), expected)
      // Keep the pre-existing source selection policy; P1 adds no panic-specific
      // frame selection and never discards the runtime frame from the stack.
      assert_eq(snapshot.source_path(), Some("/tmp/main.mbt"))
      assert_true(
        session.execution is Some({ stack_snapshot: Some(stack), .. }) &&
        stack.frames().length() == 2,
      )
      assert_eq(transport.remaining_inputs(), 0)
    })
  }
}
