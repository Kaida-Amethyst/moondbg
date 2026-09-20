///|
fn live_test_session() -> (LiveSession, @dap_testkit.ScriptedTransport) {
  let transport = @dap_testkit.ScriptedTransport::new([])
  let client = ConnectionSession::new()
  client.initialized = true
  let session : LiveSession = {
    client,
    transport: transport.as_transport(),
    launch_seq: 2,
    launch_answered: true,
    pending: {},
    next_seq: 1,
    configured: true,
    ready: true,
    stopped: true,
    execution_revision: 0,
    pause_revision: None,
    exited: false,
    ended: false,
    closing: false,
    deadline: None,
    inspection: InspectionState::new(),
    capabilities: {},
    functions: FunctionState::new(@debugger.DebugContext::empty()),
  }
  (session, transport)
}

///|
async fn capture_messages(action : async (&@io.Writer) -> Unit) -> Array[Json] {
  let reader = @io.MemoryReader(action)
  defer reader.close()
  let messages = []
  while @dap.read_frame(reader) is Some(text) {
    messages.push(@json.parse(text))
  }
  messages
}

///|
test "line breakpoint requests replace one source and reject unsupported options" {
  let cleared = line_breakpoint_arguments({
    "source": { "path": "/project/main.mbt" },
  })
  assert_eq(cleared, {
    "source": { "path": "/project/main.mbt" },
    "breakpoints": [],
  })
  let invalid : Array[Json] = [
    { "source": { "path": "relative.mbt" } },
    { "source": { "path": "/main.mbt" }, "breakpoints": [{ "line": 0 }] },
    { "source": { "path": "/main.mbt" }, "breakpoints": [{ "line": 1.5 }] },
    {
      "source": { "path": "/main.mbt" },
      "breakpoints": [{ "line": 3, "condition": "x > 1" }],
    },
    {
      "source": { "path": "/main.mbt" },
      "breakpoints": [{ "line": 3, "logMessage": "hello" }],
    },
  ]
  for arguments in invalid {
    assert_true(
      try {
        line_breakpoint_arguments(arguments) |> ignore
        false
      } catch {
        _ => true
      },
    )
  }
}

///|
async test "live response routing remains correct when replies arrive out of order" {
  let (session, transport) = live_test_session()
  let messages = capture_messages(writer => {
    session.on_client(writer, request(41, "threads"))
    session.on_client(
      writer,
      request(42, "setBreakpoints", arguments={
        "source": { "path": "/main.mbt" },
        "breakpoints": [],
      }),
    )
    session.on_adapter(
      writer,
      {
        "type": "response",
        "seq": 90,
        "request_seq": 2,
        "command": "setBreakpoints",
        "success": true,
        "body": { "breakpoints": [] },
      },
      2,
      {},
    )
    session.on_adapter(
      writer,
      {
        "type": "response",
        "seq": 91,
        "request_seq": 1,
        "command": "threads",
        "success": true,
        "body": { "threads": [{ "id": 7, "name": "main" }] },
      },
      2,
      {},
    )
  })
  assert_true(
    transport.sent_messages()
    is [
      { "seq": Number(1, ..), "command": String("threads"), .. },
      { "seq": Number(2, ..), "command": String("setBreakpoints"), .. },
    ],
  )
  assert_true(
    messages
    is [
      {
        "seq": Number(1, ..),
        "request_seq": Number(42, ..),
        "success": True,
        ..
      },
      {
        "seq": Number(2, ..),
        "request_seq": Number(41, ..),
        "success": True,
        ..
      },
    ],
  )
  assert_eq(session.pending.length(), 0)
}

///|
async test "continue response output and later stop are independent messages" {
  let (session, _) = live_test_session()
  let messages = capture_messages(writer => {
    session.on_client(
      writer,
      request(10, "continue", arguments={ "threadId": 7 }),
    )
    assert_false(session.stopped)
    session.on_adapter(
      writer,
      {
        "type": "event",
        "event": "output",
        "body": { "category": "stdout", "output": "hello\n" },
      },
      2,
      {},
    )
    session.on_adapter(
      writer,
      {
        "type": "event",
        "event": "stopped",
        "body": { "reason": "breakpoint", "threadId": 7 },
      },
      2,
      {},
    )
    session.on_adapter(
      writer,
      {
        "type": "response",
        "request_seq": 1,
        "command": "continue",
        "success": true,
      },
      2,
      {},
    )
    assert_true(session.stopped)
    // LLDB capabilities must not turn unsupported frontend features on.
    session.on_adapter(
      writer,
      {
        "type": "event",
        "event": "capabilities",
        "body": { "supportsEvaluateForHovers": true },
      },
      2,
      {},
    )
  })
  assert_true(
    messages
    is [
      { "event": String("output"), .. },
      { "event": String("stopped"), .. },
      { "request_seq": Number(10, ..), "success": True, .. },
    ],
  )
}

///|
async test "disconnect cancels pending launch once and forces target termination" {
  let (session, transport) = live_test_session()
  session.launch_answered = false
  session.configured = false
  session.ready = false
  session.stopped = false
  let messages = capture_messages(writer => {
    session.on_client(
      writer,
      request(10, "disconnect", arguments={ "terminateDebuggee": false }),
    )
    session.on_adapter(
      writer,
      {
        "type": "response",
        "request_seq": 1,
        "command": "disconnect",
        "success": true,
      },
      2,
      {},
    )
    assert_true(session.finish() is None)
  })
  assert_true(
    transport.sent_messages()
    is [
      {
        "command": String("disconnect"),
        "arguments": { "terminateDebuggee": True, .. },
        ..
      },
    ],
  )
  assert_true(
    messages
    is [
      {
        "command": String("launch"),
        "request_seq": Number(2, ..),
        "success": False,
        ..
      },
      {
        "command": String("disconnect"),
        "request_seq": Number(10, ..),
        "success": True,
        ..
      },
      { "event": String("terminated"), .. },
    ],
  )
  assert_true(session.client.closed)
}

///|
test "non-native DAP source coordinates are rejected at initialize" {
  let invalid : Array[Json] = [
    { "pathFormat": "uri" },
    { "linesStartAt1": false },
    { "columnsStartAt1": false },
  ]
  for arguments in invalid {
    let session = ConnectionSession::new()
    assert_true(
      session.handle(request(1, "initialize", arguments~))
      is [{ "success": False, .. }],
    )
    assert_false(session.initialized)
  }
}
