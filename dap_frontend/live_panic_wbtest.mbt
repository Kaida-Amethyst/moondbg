///|
async fn panic_test_breakpoint(
  id : Int,
) -> @lldb_dap.InstalledFunctionBreakpoint {
  let driver = @lldb_dap.FunctionBreakpointDriver::new((command, args) => {
    assert_eq(command, "evaluate")
    assert_true(
      args
      is {
        "expression": String(
          "breakpoint set --name moonbit_panic --breakpoint-name __moondbg_panic"
        ),
        ..
      },
    )
    function_reply(
      "Breakpoint \{id}: where = program`moonbit_panic, address = 0x1234",
    )
  })
  driver.install_panic()
}

///|
test "panic filter capability defaults on and connection test remains synthetic" {
  let client = ConnectionSession::new()
  assert_true(
    client.handle(request(1, "initialize"))
    is [
      {
        "body": {
          "exceptionBreakpointFilters": [
            { "filter": String("moonbit-panic"), "default": True, .. },
          ],
          ..
        },
        ..
      },
    ],
  )
  assert_true(panic_filter({ "filters": ["moonbit-panic"] }))
  assert_false(panic_filter({ "filters": [] }))
  for
    args in (
      [
        {},
        { "filters": ["all"] },
        { "filters": [1] },
        {
          "filters": [],
          "filterOptions": [
            { "filterId": "moonbit-panic", "condition": "true" },
          ],
        },
      ] : Array[Json]) {
    assert_true(
      try {
        panic_filter(args) |> ignore
        false
      } catch {
        _ => true
      },
    )
  }
  assert_true(
    client.handle(
      request(2, "setExceptionBreakpoints", arguments={
        "filters": ["moonbit-panic"],
      }),
    )
    is [{ "body": { "breakpoints": [{ "verified": False, .. }], .. }, .. }],
  )
}

///|
async test "panic configuration gates execution but never disconnect and hides internal IDs" {
  let (session, transport) = live_test_session()
  session.configured = false
  let messages = capture_messages(writer => {
    session.on_client(
      writer,
      request(10, "setExceptionBreakpoints", arguments={
        "filters": ["moonbit-panic"],
      }),
    )
    session.on_client(writer, request(11, "configurationDone"))
    assert_true(transport.sent_messages().is_empty())
    session.on_adapter(
      writer,
      {
        "type": "event",
        "event": "breakpoint",
        "body": {
          "reason": "new",
          "breakpoint": { "id": 99, "verified": true },
        },
      },
      2,
      {},
    )
    session.complete_panic(writer, Ok(Some(panic_test_breakpoint(99))))
  })
  assert_true(
    messages
    is [{ "command": String("setExceptionBreakpoints"), "success": True, .. }],
    msg=Json(messages).stringify(),
  )
  assert_true(
    transport.sent_messages()
    is [{ "command": String("configurationDone"), .. }],
  )
  let messages = capture_messages(writer => {
    session.on_client(
      writer,
      request(12, "setExceptionBreakpoints", arguments={ "filters": [] }),
    )
    session.on_client(
      writer,
      request(13, "continue", arguments={ "threadId": 1 }),
    )
    session.on_client(writer, request(14, "disconnect"))
    session.complete_panic(writer, Ok(None)) // cancelled worker completion
  })
  for seq in [12, 13] {
    assert_true(
      messages.any(message => {
        message is { "request_seq": Number(id, ..), "success": False, .. } &&
        id == seq.to_double()
      }),
    )
  }
  assert_true(session.closing)
}

///|
async test "omitting exception configuration installs advertised default before launch" {
  let (session, transport) = live_test_session()
  session.configured = false
  let messages = capture_messages(writer => {
    session.on_client(writer, request(10, "configurationDone"))
    assert_eq(session.panic.active, Some(0))
    assert_true(session.panic.jobs.get())
    assert_true(transport.sent_messages().is_empty())
    session.complete_panic(writer, Ok(Some(panic_test_breakpoint(1))))
  })
  assert_true(messages.is_empty()) // no fabricated request_seq = 0 response
  assert_true(
    transport.sent_messages()
    is [{ "command": String("configurationDone"), .. }],
  )
}

///|
async test "panic frame lookup preserves signals and discards a stale stop response" {
  let (session, transport) = live_test_session()
  session.panic.breakpoint = Some(panic_test_breakpoint(99))
  let messages = capture_messages(writer => {
    session.on_adapter(
      writer,
      {
        "type": "event",
        "event": "stopped",
        "body": {
          "reason": "exception",
          "description": "signal SIGABRT",
          "threadId": 1,
        },
      },
      2,
      {},
    )
    assert_true(transport.sent_messages().is_empty())
    session.on_adapter(
      writer,
      {
        "type": "event",
        "event": "stopped",
        "body": {
          "reason": "breakpoint",
          "hitBreakpointIds": [99],
          "threadId": 1,
        },
      },
      2,
      {},
    )
    session.on_adapter(
      writer,
      { "type": "event", "event": "continued", "body": { "threadId": 1 } },
      2,
      {},
    )
    session.on_adapter(
      writer,
      {
        "type": "response",
        "command": "stackTrace",
        "request_seq": 1,
        "success": true,
        "body": { "stackFrames": [{ "id": 0, "name": "moonbit_panic" }] },
      },
      2,
      {},
    )
  })
  assert_true(
    messages
    is [
      {
        "event": String("stopped"),
        "body": { "description": String("signal SIGABRT"), .. },
        ..
      },
      { "event": String("continued"), .. },
    ],
    msg=Json(messages).stringify(),
  )
  assert_true(session.panic.thread is None)
}

///|
async test "panic without project source context reports absence and preserves full frame order" {
  let (session, _) = live_test_session()
  session.panic.breakpoint = Some(panic_test_breakpoint(99))
  let frames : Array[Json] = [
    {
      "id": 0,
      "name": "moonbit_panic [opt]",
      "line": 1,
      "column": 1,
      "source": { "path": "/runtime.c" },
    },
    {
      "id": 1,
      "name": "caller",
      "line": 4,
      "column": 1,
      "source": { "path": "/project/main.mbt" },
    },
  ]
  let messages = capture_messages(writer => {
    session.on_adapter(
      writer,
      {
        "type": "event",
        "event": "stopped",
        "body": {
          "reason": "breakpoint",
          "hitBreakpointIds": [99],
          "threadId": 1,
        },
      },
      2,
      {},
    )
    session.on_adapter(
      writer,
      {
        "type": "response",
        "command": "stackTrace",
        "request_seq": 1,
        "success": true,
        "body": { "stackFrames": frames },
      },
      2,
      {},
    )
  })
  assert_true(
    messages
    is [
      { "event": String("output"), .. },
      {
        "event": String("stopped"),
        "body": { "reason": String("exception"), .. },
        ..
      },
    ],
  )
  assert_true(
    Json(messages).stringify().contains("project source context is unavailable"),
  )
  session.panic.present_frames({ "threadId": 1 }, frames)
  assert_true(
    frames.all(frame => frame is { "presentationHint": String("subtle"), .. }),
  )
  session.panic.project_sources.set("/project/main.mbt", true)
  session.panic.present_frames({ "threadId": 1 }, frames)
  assert_true(
    frames
    is [
      { "id": Number(0, ..), "presentationHint": String("subtle"), .. },
      { "id": Number(1, ..), "presentationHint": String("normal"), .. },
    ],
  )
}
