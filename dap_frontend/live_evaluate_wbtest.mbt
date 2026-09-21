///|
async test "evaluate validates syntax frames and stopped state without forwarding user text" {
  let (session, transport) = live_test_session()
  session.inspection.map_frames([{ "id": 90 }])
  let messages = capture_messages(writer => {
    let invalid : Array[Json] = [
      { "expression": "point.x" },
      { "expression": "point.x", "frameId": 90 },
      { "expression": "point.x", "frameId": 1.5 },
      { "expression": 123, "frameId": 1 },
      { "expression": "p point", "frameId": 1 },
      { "expression": "point()", "frameId": 1 },
      { "expression": "point.x = 42", "frameId": 1 },
      { "expression": "arr[-1]", "frameId": 1 },
    ]
    for i, args in invalid {
      session.on_client(writer, request(10 + i, "evaluate", arguments=args))
    }
    session.stopped = false
    session.on_client(
      writer,
      request(20, "evaluate", arguments={
        "expression": "point.x",
        "frameId": 1,
      }),
    )
  })
  assert_eq(messages.length(), 9)
  for message in messages {
    assert_true(
      message is { "command": String("evaluate"), "success": False, .. },
    )
  }
  assert_true(session.inspection.pending.is_empty())
  assert_true(transport.sent_messages().is_empty())
}

///|
async test "evaluate uses the requested frame in all contexts and invalidates queued results" {
  let (session, transport) = live_test_session()
  session.inspection.map_frames([{ "id": 90 }, { "id": 91 }])
  let messages = capture_messages(writer => {
    for i, context in ["hover", "watch", "repl"] {
      session.on_client(
        writer,
        request(10 + i, "evaluate", arguments={
          "expression": "  points[001].x  ",
          "frameId": 2,
          "context": context,
        }),
      )
      let job = session.inspection.jobs.get()
      assert_true(job.target is Evaluate(91, _))
      guard job.target is Evaluate(_, path) else { fail("evaluate job") }
      assert_eq(path.display_name(), "points[1].x")
    }
    session.on_client(
      writer,
      request(20, "continue", arguments={ "threadId": 7 }),
    )
    control_event(session, writer, "stopped")
    // A worker finishing late must not send a second response or mint handles.
    session.complete_inspection(writer, 10, Ok([]))
  })
  assert_eq(transport.sent_messages().length(), 1)
  assert_eq(
    messages
    .filter(message => {
      message is { "command": String("evaluate"), "success": False, .. }
    })
    .length(),
    3,
  )
  assert_true(session.inspection.pending.is_empty())
  assert_true(session.inspection.references.is_empty())
}

///|
async test "inspection errors identify a rejected memory read during explicit range access" {
  let inspector = @lldb_dap.VariableInspector::new(
    (command, args) => {
      let body : Json = match command {
        "scopes" =>
          { "scopes": [{ "name": "Locals", "variablesReference": 100 }] }
        "variables" if args is { "variablesReference": Number(101, ..), .. } =>
          {
            "variables": [
              {
                "name": "body",
                "type": "unsigned short *",
                "value": "0x1000",
                "variablesReference": 0,
              },
            ],
          }
        "variables" =>
          {
            "variables": [
              {
                "name": "text",
                "type": "String",
                "value": "0x1000",
                "variablesReference": 101,
              },
            ],
          }
        "readMemory" => {}
        _ => fail(command)
      }
      guard @dap.classify_message({
          "type": "response",
          "seq": 1,
          "request_seq": 1,
          "command": command,
          "success": command != "readMemory",
          "message": "unmapped address",
          "body": body,
        })
        is @dap.Response(response) else {
        fail("response")
      }
      response
    },
    () => Some(1),
    { "supportsReadMemoryRequest": true },
  )
  let message = try {
    inspector.tree_evaluate(
      10,
      @debugger.VariablePath::root("text").with_range(0, 1),
    )
    |> ignore
    fail("expected a failed memory read")
  } catch {
    error => inspection_error_message(error)
  }
  assert_eq(message, "Memory read failed: unmapped address")
}
