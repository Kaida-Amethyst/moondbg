///|
fn function_reply(result : String) -> @dap.DapResponse raise {
  guard @dap.classify_message({
      "type": "response",
      "seq": 1,
      "request_seq": 1,
      "command": "evaluate",
      "success": true,
      "body": { "result": result },
    })
    is @dap.Response(response) else {
    fail("response")
  }
  response
}

///|
async test "function replacement deduplicates retains and deletes only owned handles" {
  let commands : Array[String] = []
  let driver = @lldb_dap.FunctionBreakpointDriver::new((_, args) => {
    guard args is { "expression": String(command), .. } else {
      fail(args.stringify())
    }
    commands.push(command)
    function_reply(
      if command.has_prefix("breakpoint delete ") {
        "1 breakpoints deleted; 0 breakpoint locations disabled."
      } else {
        "Breakpoint 17: 2 locations."
      },
    )
  })
  let installed : Map[String, @lldb_dap.InstalledFunctionBreakpoint] = Map([])
  let context = @debugger.DebugContext::new("demo/main", [])
  let result = replace_functions(driver, context, installed, [
    { "name": "foo" },
    { "name": "foo" },
    { "name": "@missing.foo" },
    { "name": "bar", "condition": "x > 1" },
  ])
  assert_eq(commands, [
    "breakpoint set --func-regex '^_M0FP24demo4main3foo($|G|H)'",
  ])
  assert_eq(result.length(), 4)
  assert_eq(result[0], result[1])
  assert_true(result[2] is { "verified": False, .. })
  assert_true(result[3] is { "verified": False, .. })
  replace_functions(driver, context, installed, [{ "name": "foo" }]) |> ignore
  assert_eq(commands.length(), 1)
  replace_functions(driver, context, installed, []) |> ignore
  assert_eq(commands[1], "breakpoint delete 17")
  assert_true(installed.is_empty())
}

///|
async test "function creation rejects command injection and uncertain replies" {
  let commands : Array[Json] = []
  let driver = @lldb_dap.FunctionBreakpointDriver::new((_, args) => {
    commands.push(args)
    function_reply("unrecognized output")
  })
  assert_true(
    try {
      driver.install(
        @debugger.FunctionBreakpointSelector::exact_physical("main'; quit"),
      )
      |> ignore
      false
    } catch {
      @debugger.BreakpointSyncRejected(_) => true
      _ => false
    },
  )
  assert_true(commands.is_empty())
  assert_true(
    try {
      driver.install(@debugger.FunctionBreakpointSelector::family("_M0FP0foo"))
      |> ignore
      false
    } catch {
      @debugger.BreakpointSyncUncertain(_) => true
      _ => false
    },
  )
}

///|
async test "function replacement keeps disconnect responsive and rejects deferred work" {
  let (session, transport) = live_test_session()
  let messages = capture_messages(writer => {
    session.on_client(
      writer,
      request(10, "setFunctionBreakpoints", arguments={
        "breakpoints": [{ "name": "main" }],
      }),
    )
    session.on_client(
      writer,
      request(11, "continue", arguments={ "threadId": 1 }),
    )
    session.on_client(
      writer,
      request(12, "setFunctionBreakpoints", arguments={ "breakpoints": [] }),
    )
    assert_eq(transport.sent_messages().length(), 0)
    session.on_client(writer, request(13, "disconnect"))
  })
  assert_true(session.closing)
  assert_true(session.functions.active is None)
  assert_true(session.functions.deferred.is_empty())
  for seq in [10, 11, 12] {
    assert_true(
      messages.any(message => {
        message is { "request_seq": Number(id, ..), "success": False, .. } &&
        id == seq.to_double()
      }),
    )
  }
  assert_true(
    transport.sent_messages() is [{ "command": String("disconnect"), .. }],
  )
}

///|
async test "function installation publishes before early stops and preserves source events" {
  let (session, _) = live_test_session()
  let messages = capture_messages(writer => {
    session.on_client(
      writer,
      request(10, "setFunctionBreakpoints", arguments={
        "breakpoints": [{ "name": "main" }],
      }),
    )
    session.on_adapter(
      writer,
      {
        "type": "event",
        "event": "stopped",
        "body": {
          "reason": "breakpoint",
          "threadId": 1,
          "hitBreakpointIds": [77],
        },
      },
      2,
      {},
    )
    assert_eq(session.functions.stops.length(), 1)
    session.complete_functions(writer, Ok([{ "id": 77, "verified": true }]))
    session.function_event(writer, {
      "reason": "changed",
      "breakpoint": { "id": 78, "verified": true },
    })
    session.functions.published.clear()
    session.function_event(writer, {
      "reason": "removed",
      "breakpoint": { "id": 77, "verified": true },
    })
  })
  assert_true(
    messages
    is [
      { "command": String("setFunctionBreakpoints"), .. },
      {
        "event": String("stopped"),
        "body": {
          "reason": String("function breakpoint"),
          "hitBreakpointIds": [Number(77, ..)],
          ..
        },
        ..
      },
      {
        "event": String("breakpoint"),
        "body": { "breakpoint": { "id": Number(78, ..), .. }, .. },
        ..
      },
    ],
    msg=Json(messages).stringify(),
  )
}
