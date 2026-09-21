///|
fn conditional_stop() -> Json {
  { "reason": "breakpoint", "threadId": 7, "hitBreakpointIds": [10] }
}

///|
fn bind_test_condition(session : LiveSession) -> Unit raise {
  session.conditions.bindings.replace("/main.mbt", [
    (10, Some(@expression.Condition::parse("i == 7"))),
  ])
}

///|
async test "false condition is an invisible stop continue transaction" {
  let (session, transport) = live_test_session()
  bind_test_condition(session)
  let messages = capture_messages(writer => {
    session.publish_stop(writer, conditional_stop())
    assert_true(session.inspection_epoch() is None)
    assert_true(session.condition_epoch() is Some(0))
    session.complete_condition(writer, 0, Ok(false))
    assert_false(session.stopped)
    control_event(session, writer, "continued")
    control_reply(session, writer, 1, "continue", success=true)
  })
  assert_eq(messages, [])
  assert_true(
    transport.sent_messages() is [{ "command": String("continue"), .. }],
  )
}

///|
async test "true and failed conditions publish a real inspectable stop" {
  for result in [Ok(true), Err("i unavailable")] {
    let (session, transport) = live_test_session()
    bind_test_condition(session)
    let messages = capture_messages(writer => {
      session.publish_stop(writer, conditional_stop())
      session.complete_condition(writer, 0, result)
    })
    assert_eq(transport.sent_messages(), [])
    assert_true(session.inspection_epoch() is Some(0))
    assert_true(messages.last() is Some({ "event": String("stopped"), .. }))
    assert_eq(messages.length(), if result is Ok(_) { 1 } else { 2 })
  }
}

///|
async test "pause and disconnect supersede in-flight condition evaluation" {
  for command in ["pause", "disconnect"] {
    let (session, transport) = live_test_session()
    bind_test_condition(session)
    let messages = capture_messages(writer => {
      session.publish_stop(writer, conditional_stop())
      session.on_client(
        writer,
        request(20, command, arguments={ "threadId": 7 }),
      )
      session.complete_condition(writer, 0, Ok(false))
    })
    assert_false(
      transport
      .sent_messages()
      .any(message => message is { "command": String("continue"), .. }),
    )
    if command == "pause" {
      assert_true(
        messages
        is [
          { "request_seq": Number(20, ..), "success": True, .. },
          {
            "event": String("stopped"),
            "body": { "reason": String("pause"), .. },
            ..
          },
        ],
      )
      assert_true(session.stopped)
      assert_true(session.inspection_epoch() is Some(_))
    } else {
      assert_true(session.closing)
      assert_true(
        transport.sent_messages() is [{ "command": String("disconnect"), .. }],
      )
    }
  }
}

///|
async test "single stepping and an outstanding pause retain conditional breakpoint stops" {
  for pause in [false, true] {
    let (session, transport) = live_test_session()
    bind_test_condition(session)
    session.conditions.stepping = !pause
    if pause {
      session.pause_revision = Some(0)
    }
    let messages = capture_messages(writer => {
      session.on_adapter(
        writer,
        { "type": "event", "event": "stopped", "body": conditional_stop() },
        2,
        {},
      )
    })
    assert_true(messages is [{ "event": String("stopped"), .. }])
    assert_eq(transport.sent_messages(), [])
    assert_true(session.conditions.active is None)
  }
}

///|
async test "conditional source replacement never forwards expressions to LLDB" {
  let (session, transport) = live_test_session()
  let arguments : Json = {
    "source": { "path": "/main.mbt" },
    "breakpoints": [{ "line": 4, "condition": "i == 7" }],
  }
  let messages = capture_messages(writer => {
    session.handle_live_request(writer, 10, "setBreakpoints", arguments)
    session.on_adapter(
      writer,
      { "type": "event", "event": "stopped", "body": conditional_stop() },
      2,
      {},
    )
    assert_eq(session.functions.stops.length(), 1)
    session.handle_live_request(writer, 11, "continue", { "threadId": 7 })
    session.on_adapter(
      writer,
      {
        "type": "response",
        "request_seq": 1,
        "command": "setBreakpoints",
        "success": true,
        "body": { "breakpoints": [{ "verified": true, "id": 10 }] },
      },
      2,
      {},
    )
    assert_true(session.conditions.active is Some(_))
    assert_eq(session.functions.deferred.length(), 1)
  })
  assert_true(
    messages is [{ "command": String("setBreakpoints"), "success": True, .. }],
  )
  assert_true(
    transport.sent_messages()
    is [{ "arguments": { "breakpoints": [point], .. }, .. }] &&
    point == Json({ "line": 4 }),
  )
}

///|
async test "invalid condition update preserves the previous bindings" {
  let (session, transport) = live_test_session()
  bind_test_condition(session)
  let messages = capture_messages(writer => {
    session.handle_live_request(writer, 10, "setBreakpoints", {
      "source": { "path": "/main.mbt" },
      "breakpoints": [{ "line": 4, "condition": "i = 3" }],
    })
  })
  assert_true(messages is [{ "success": False, .. }])
  assert_eq(transport.sent_messages(), [])
  assert_true(
    session.conditions.bindings.for_stop(conditional_stop()) is Some(_),
  )
}

///|
async test "failed internal continue stops safely and late failure cannot override newer state" {
  for newer_stop in [false, true] {
    let (session, _) = live_test_session()
    bind_test_condition(session)
    let messages = capture_messages(writer => {
      session.publish_stop(writer, conditional_stop())
      session.complete_condition(writer, 0, Ok(false))
      if newer_stop {
        control_event(session, writer, "stopped")
      }
      control_reply(session, writer, 1, "continue", success=false)
    })
    assert_true(session.stopped)
    assert_true(messages.last() is Some({ "event": String("stopped"), .. }))
    assert_eq(messages.length(), if newer_stop { 1 } else { 2 })
    assert_false(
      messages.any(message => message is { "type": String("response"), .. }),
    )
  }
}

///|
async test "malformed replacement replies fail explicitly and do not commit new bindings" {
  let (session, _) = live_test_session()
  bind_test_condition(session)
  let messages = capture_messages(writer => {
    session.handle_live_request(writer, 10, "setBreakpoints", {
      "source": { "path": "/main.mbt" },
      "breakpoints": [{ "line": 4, "condition": "i == 2" }],
    })
    assert_true(
      try {
        session.on_adapter(
          writer,
          {
            "type": "response",
            "request_seq": 1,
            "command": "setBreakpoints",
            "success": true,
            "body": { "breakpoints": [] },
          },
          2,
          {},
        )
        false
      } catch {
        _ => true
      },
    )
  })
  assert_true(
    messages is [{ "request_seq": Number(10, ..), "success": False, .. }],
  )
  assert_true(
    session.conditions.bindings.for_stop(conditional_stop())
    is Some([condition]) &&
    condition.text == "i == 7",
  )
}
