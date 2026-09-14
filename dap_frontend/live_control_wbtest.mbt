///|
async fn control_reply(
  session : LiveSession,
  writer : &@io.Writer,
  seq : Int,
  command : String,
  success~ : Bool,
) -> Unit {
  session.on_adapter(
    writer,
    {
      "type": "response",
      "request_seq": seq,
      "command": command,
      "success": success,
      "message": "adapter test response",
    },
    2,
    {},
  )
}

///|
async fn control_event(
  session : LiveSession,
  writer : &@io.Writer,
  name : String,
) -> Unit {
  session.on_adapter(
    writer,
    {
      "type": "event",
      "event": name,
      "body": { "threadId": 7, "reason": "step" },
    },
    2,
    {},
  )
}

///|
async test "source stepping routes independently of stops and rejects duplicate resumes" {
  for command in ["continue", "next", "stepIn", "stepOut"] {
    for stop_first in [false, true] {
      let (session, transport) = live_test_session()
      let messages = capture_messages(writer => {
        session.on_client(
          writer,
          request(10, command, arguments={ "threadId": 7 }),
        )
        assert_false(session.stopped)
        session.on_client(
          writer,
          request(11, "next", arguments={ "threadId": 7 }),
        )
        if stop_first {
          control_event(session, writer, "stopped")
        }
        control_reply(session, writer, 1, command, success=true)
        assert_eq(session.stopped, stop_first)
        if !stop_first {
          control_event(session, writer, "stopped")
        }
        assert_true(session.stopped)
      })
      assert_eq(transport.sent_messages(), [
        {
          "seq": 1,
          "type": "request",
          "command": command,
          "arguments": { "threadId": 7, "singleThread": false },
        },
      ])
      assert_true(
        messages[0] is { "request_seq": Number(11, ..), "success": False, .. },
      )
      assert_eq(messages.length(), 3)
    }
  }
}

///|
async test "pause acknowledges without fabricating a stop and allows resume after stop" {
  for stop_first in [false, true] {
    let (session, transport) = live_test_session()
    session.stopped = false
    let messages = capture_messages(writer => {
      session.on_client(
        writer,
        request(10, "pause", arguments={ "threadId": 7 }),
      )
      assert_false(session.stopped)
      session.on_client(
        writer,
        request(11, "pause", arguments={ "threadId": 7 }),
      )
      if stop_first {
        control_event(session, writer, "stopped")
      }
      control_reply(session, writer, 1, "pause", success=true)
      assert_eq(session.stopped, stop_first)
      if !stop_first {
        session.on_client(
          writer,
          request(12, "pause", arguments={ "threadId": 7 }),
        )
      }
      if !stop_first {
        control_event(session, writer, "stopped")
      }
      session.on_client(
        writer,
        request(13, "continue", arguments={ "threadId": 7 }),
      )
      assert_false(session.stopped)
    })
    assert_eq(transport.sent_messages().length(), 2)
    assert_true(
      transport.sent_messages()[0]
      is {
        "command": String("pause"),
        "arguments": { "threadId": Number(7, ..), .. },
        ..
      },
    )
    assert_true(
      messages[0] is { "request_seq": Number(11, ..), "success": False, .. },
    )
  }
}

///|
async test "rejected resume restores the stop and rejected pause leaves execution running" {
  for command in ["continue", "next", "stepIn", "stepOut", "pause"] {
    let (session, _) = live_test_session()
    let initially_stopped = command != "pause"
    session.stopped = initially_stopped
    let messages = capture_messages(writer => {
      session.on_client(
        writer,
        request(10, command, arguments={ "threadId": 7 }),
      )
      control_reply(session, writer, 1, command, success=false)
    })
    assert_eq(session.stopped, initially_stopped)
    assert_true(session.pause_revision is None)
    assert_true(
      messages is [{ "request_seq": Number(10, ..), "success": False, .. }],
    )
  }
}

///|
async test "only a requested SIGSTOP is presented as pause even after acknowledgement" {
  for acknowledge_first in [false, true] {
    let (session, _) = live_test_session()
    session.stopped = false
    let messages = capture_messages(writer => {
      session.on_client(
        writer,
        request(10, "pause", arguments={ "threadId": 7 }),
      )
      if acknowledge_first {
        control_reply(session, writer, 1, "pause", success=true)
      }
      session.on_adapter(
        writer,
        {
          "type": "event",
          "event": "stopped",
          "body": {
            "reason": "exception",
            "description": "signal SIGSTOP",
            "threadId": 7,
            "allThreadsStopped": true,
          },
        },
        2,
        {},
      )
      if !acknowledge_first {
        control_reply(session, writer, 1, "pause", success=true)
      }
    })
    assert_true(
      messages.any(message => {
        message
        is {
          "event": String("stopped"),
          "body": {
            "reason": String("pause"),
            "threadId": Number(7, ..),
            "allThreadsStopped": True,
            ..
          },
          ..
        }
      }),
    )
    assert_true(session.stopped)
    assert_true(session.pause_revision is None)
  }
  for requested in [false, true] {
    for reason in ["breakpoint", "exception"] {
      for description in ["signal SIGSTOP", "signal SIGSEGV"] {
        let (session, _) = live_test_session()
        if requested {
          session.pause_revision = Some(0)
        }
        let body : Json = { "reason": reason, "description": description }
        let mapped = session.pause_stop_body(body)
        let expected = if requested &&
          reason == "exception" &&
          description == "signal SIGSTOP" {
          "pause"
        } else {
          reason
        }
        assert_true(
          mapped is { "reason": String(actual), .. } && actual == expected,
        )
        assert_true(session.pause_revision is None)
      }
    }
  }
}

///|
async test "old failures cannot overwrite a newer resume or exit" {
  for event in ["stopped", "continued", "exited", "terminated"] {
    let (session, _) = live_test_session()
    capture_messages(writer => {
      session.on_client(
        writer,
        request(10, "next", arguments={ "threadId": 7 }),
      )
      control_event(session, writer, event)
      if event == "stopped" {
        session.on_client(
          writer,
          request(11, "stepOut", arguments={ "threadId": 7 }),
        )
      }
      control_reply(session, writer, 1, "next", success=false)
      assert_false(session.stopped)
    })
    |> ignore
  }
}

///|
async test "pause may interrupt an outstanding step without blocking disconnect" {
  let (session, transport) = live_test_session()
  capture_messages(writer => {
    session.on_client(
      writer,
      request(10, "stepOut", arguments={ "threadId": 7 }),
    )
    session.on_client(writer, request(11, "pause", arguments={ "threadId": 7 }))
    session.on_client(writer, request(12, "disconnect"))
  })
  |> ignore
  assert_eq(transport.sent_messages().length(), 3)
  assert_true(session.closing)
}

///|
async test "invalid control arguments never reach LLDB or change state" {
  let invalid : Array[Json] = [
    {},
    { "threadId": 0 },
    { "threadId": -1 },
    { "threadId": 1.5 },
    { "threadId": 2147483648 },
    { "threadId": "7" },
    { "threadId": 7, "singleThread": true },
    { "threadId": 7, "singleThread": "false" },
    { "threadId": 7, "granularity": "instruction" },
    { "threadId": 7, "targetId": 1 },
  ]
  for command in ["continue", "next", "stepIn", "stepOut", "pause"] {
    for arguments in invalid {
      let (session, transport) = live_test_session()
      session.stopped = command != "pause"
      let messages = capture_messages(writer => {
        session.on_client(writer, request(10, command, arguments~))
      })
      assert_eq(session.stopped, command != "pause")
      assert_eq(transport.sent_messages().length(), 0)
      assert_true(messages is [{ "success": False, .. }])
    }
  }
  assert_eq(
    execution_arguments("next", {
      "threadId": 7,
      "singleThread": false,
      "granularity": "statement",
    }),
    { "threadId": 7, "singleThread": false },
  )
}

///|
async test "control rejects wrong states including the exited to terminated gap" {
  for command in ["continue", "next", "stepIn", "stepOut", "pause"] {
    for
      state in [
        "wrong-stop", "unconfigured", "launching", "exited", "ended", "closing",
      ] {
      let (session, transport) = live_test_session()
      session.stopped = command != "pause"
      match state {
        "wrong-stop" => session.stopped = !session.stopped
        "unconfigured" => session.configured = false
        "launching" => session.launch_answered = false
        "exited" => session.exited = true
        "ended" => session.ended = true
        _ => session.closing = true
      }
      let messages = capture_messages(writer => {
        session.on_client(
          writer,
          request(10, command, arguments={ "threadId": 7 }),
        )
      })
      assert_eq(transport.sent_messages().length(), 0)
      assert_true(messages is [{ "success": False, .. }])
    }
  }
}
