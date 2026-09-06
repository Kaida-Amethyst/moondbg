///|
async test "breakpoint stop reasons hide LLDB ids while other descriptions stay intact" {
  let cases : Array[(Json, String)] = [
    (
      { "reason": "breakpoint", "description": "breakpoint 3.1", "threadId": 1 },
      "breakpoint",
    ),
    (
      {
        "reason": "breakpoint",
        "description": "breakpoint 2.1 7.2",
        "threadId": 1,
      },
      "breakpoint",
    ),
    (
      { "reason": "step", "description": "step over", "threadId": 1 },
      "step over",
    ),
    (
      {
        "reason": "exception",
        "description": "EXC_BAD_ACCESS (code=1)",
        "threadId": 1,
      },
      "EXC_BAD_ACCESS (code=1)",
    ),
    ({ "reason": "step", "threadId": 1 }, "step"),
  ]
  for pair in cases {
    let (body, expected) = pair
    @async.with_task_group(async fn(group) {
      let script = management_entry_script()
      script[4] = scripted_event(16004, "stopped", body)
      let transport = @dap_testkit.ScriptedTransport::new(script)
      let session = LldbDapSession::start_with_dispatcher_factory(
        group,
        () => @dap.DapDispatcher::from_transport(transport.as_transport()),
        preparation_timeout_ms=10000,
      )
      defer session.close()
      guard session.run("/tmp/program") is @moondbg.Stopped(snapshot) else {
        fail("stopped snapshot")
      }
      assert_eq(snapshot.reason(), expected)
      assert_eq(transport.remaining_inputs(), 0)
    })
  }
}
