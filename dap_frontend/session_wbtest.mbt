///|
fn request(seq : Int, command : String, arguments? : Json = {}) -> Json {
  { "seq": seq, "type": "request", "command": command, "arguments": arguments }
}

///|
test "connection test replies in order without claiming a target was run" {
  let session = ConnectionSession::new()
  assert_true(
    session.handle(request(1, "initialize"))
    is [
      {
        "seq": Number(1, ..),
        "request_seq": Number(1, ..),
        "success": True,
        "body": {
          "supportsConfigurationDoneRequest": True,
          "supportsFunctionBreakpoints": False,
          ..
        },
        ..
      },
    ],
  )
  assert_true(
    session.handle(request(2, "launch", arguments={ "connectionTest": true }))
    is [{ "seq": Number(2, ..), "event": String("initialized"), .. }],
  )
  assert_true(
    session.handle(
      request(3, "setBreakpoints", arguments={ "breakpoints": [{ "line": 18 }] }),
    )
    is [{ "body": { "breakpoints": [{ "verified": False, .. }], .. }, .. }],
  )
  let messages = session.handle(request(4, "configurationDone"))
  assert_true(
    messages
    is [
      {
        "seq": Number(4, ..),
        "request_seq": Number(4, ..),
        "command": String("configurationDone"),
        "success": True,
        ..
      },
      {
        "seq": Number(5, ..),
        "request_seq": Number(2, ..),
        "command": String("launch"),
        "success": True,
        ..
      },
      { "seq": Number(6, ..), "event": String("output"), .. },
      { "seq": Number(7, ..), "event": String("terminated"), .. },
    ],
  )
  assert_true(messages[2].stringify().contains("DAP 连接验证成功"))
  assert_true(
    messages.all(message => !message.stringify().contains("\"exited\"")),
  )
  assert_true(session.finished)
  assert_false(session.closed)
  assert_true(
    session.handle(request(5, "disconnect"))
    is [
      {
        "seq": Number(8, ..),
        "request_seq": Number(5, ..),
        "success": True,
        ..
      },
    ],
  )
  assert_true(session.closed)
}

///|
test "threads returns an empty list even while the client handles terminated" {
  let session = ConnectionSession::new()
  session.handle(request(1, "initialize")) |> ignore
  session.handle(request(2, "launch", arguments={ "connectionTest": true }))
  |> ignore
  session.handle(request(3, "configurationDone")) |> ignore
  assert_true(
    session.handle(request(4, "threads"))
    is [{ "success": True, "body": { "threads": [], .. }, .. }],
  )
}

///|
test "connection test rejects unexpected actions and invalid sequencing" {
  let session = ConnectionSession::new()
  for command in ["launch", "configurationDone"] {
    assert_true(
      session.handle(request(session.last_request_seq + 1, command))
      is [{ "success": False, .. }],
    )
  }
  session.handle(request(3, "initialize")) |> ignore
  for
    command in [
      "initialize", "configurationDone", "continue", "evaluate", "attach", "launch",
    ] {
    assert_true(
      session.handle(request(session.last_request_seq + 1, command))
      is [{ "success": False, .. }],
    )
  }
  assert_false(session.finished)
  assert_true(session.launch_seq is None)
}

///|
test "disconnect cancels pending launch and works before initialization" {
  let early = ConnectionSession::new()
  assert_true(
    early.handle(request(1, "disconnect")) is [{ "success": True, .. }],
  )
  assert_true(early.closed)
  let session = ConnectionSession::new()
  session.handle(request(1, "initialize")) |> ignore
  session.handle(request(2, "launch", arguments={ "connectionTest": true }))
  |> ignore
  assert_true(
    session.handle(request(3, "disconnect"))
    is [
      {
        "request_seq": Number(2, ..),
        "command": String("launch"),
        "success": False,
        ..
      },
      {
        "request_seq": Number(3, ..),
        "command": String("disconnect"),
        "success": True,
        ..
      },
    ],
  )
  assert_true(session.closed)
  assert_false(session.finished)
}

///|
test "invalid client envelopes and repeated request ids are rejected" {
  let invalid : Array[Json] = [
    null,
    { "seq": 0, "type": "request", "command": "initialize" },
    { "seq": 1.5, "type": "request", "command": "initialize" },
    { "seq": 2147483648, "type": "request", "command": "initialize" },
    { "seq": 1, "type": "event", "event": "initialize" },
  ]
  for message in invalid {
    let session = ConnectionSession::new()
    assert_true(
      try {
        session.handle(message) |> ignore
        false
      } catch {
        InvalidClientRequest => true
        _ => false
      },
    )
  }
  let session = ConnectionSession::new()
  session.handle(request(1, "initialize")) |> ignore
  assert_true(
    try {
      session.handle(request(1, "initialize")) |> ignore
      false
    } catch {
      InvalidClientRequest => true
      _ => false
    },
  )
}
