///|
fn test_event(name : String, body : Json) -> DapEvent raise {
  guard classify_message({
      "seq": 10,
      "type": "event",
      "event": name,
      "body": body,
    })
    is Event(event) else {
    fail("expected a DAP event")
  }
  event
}

///|
fn test_response(
  seq : Int,
  request_seq : Int,
  command : String,
  body : Json,
) -> DapResponse raise {
  guard classify_message({
      "seq": seq,
      "type": "response",
      "request_seq": request_seq,
      "command": command,
      "success": true,
      "body": body,
    })
    is Response(response) else {
    fail("expected a DAP response")
  }
  response
}

///|
test "stepping requests encode DAP commands thread ids and line granularity" {
  let cases = [
    (DapStepKind::DapNext, "next"),
    (DapStepKind::DapStepIn, "stepIn"),
    (DapStepKind::DapStepOut, "stepOut"),
  ]
  for _, case in cases {
    let (kind, command) = case
    let request = stepping_request(kind, 41, supports_stepping_granularity=true)
    assert_eq(request.command, command)
    assert_true(
      request.arguments
      is { "threadId": Number(41, ..), "granularity": String("line"), .. },
    )
    guard request_message(8, request)
      is {
        "seq": Number(8, ..),
        "type": String("request"),
        "command": String(encoded_command),
        "arguments": {
          "threadId": Number(41, ..),
          "granularity": String("line"),
          ..
        },
        ..
      } else {
      fail("expected a complete stepping request")
    }
    assert_eq(encoded_command, command)
  }
  let request = stepping_request(
    DapNext,
    42,
    supports_stepping_granularity=false,
  )
  assert_true(request.arguments is { "threadId": Number(42, ..), .. })
  assert_false(request.arguments.stringify().contains("granularity"))
}

///|
test "responses pair by request seq without losing an earlier event" {
  let inbox = DapInbox::new()
  let stopped = test_event("stopped", { "reason": "step", "threadId": 41 })
  guard inbox.route(Event(stopped), 70) is SessionEvent(event) else {
    fail("stop event should be routed to the client")
  }
  assert_eq(event.name, "stopped")
  assert_true(
    event.body is { "reason": String("step"), "threadId": Number(41, ..), .. },
  )
  let response = test_response(80, 70, "next", {})
  guard inbox.route(Response(response), 70) is Matched(matched) else {
    fail("response should match its request")
  }
  assert_eq(matched.request_seq, 70)
  assert_eq(matched.command, Some("next"))
  assert_true(matched.success)
}

///|
test "DAP framing counts UTF-8 bytes" {
  assert_eq(frame_message("hi"), "Content-Length: 2\r\n\r\nhi")
  assert_eq(frame_message("月"), "Content-Length: 3\r\n\r\n月")
}

///|
test "Content-Length parsing is case-insensitive" {
  assert_eq(parse_content_length("Content-Length: 42\r\n"), Some(42))
  assert_eq(parse_content_length("content-length: 7"), Some(7))
  assert_eq(parse_content_length("Content-Type: application/json"), None)
  assert_eq(parse_content_length("Content-Length: nope"), None)
}

///|
test "classified messages retain protocol fields and complete payloads" {
  guard classify_message({
      "seq": 2,
      "type": "event",
      "event": "output",
      "body": { "category": "stdout", "output": "hello" },
    })
    is Event(event) else {
    fail("expected an event")
  }
  assert_eq(event.seq, 2)
  assert_eq(event.name, "output")
  assert_true(
    event.body
    is { "category": String("stdout"), "output": String("hello"), .. },
  )
  guard classify_message({
      "seq": 3,
      "type": "response",
      "request_seq": 1,
      "command": "initialize",
      "success": true,
      "body": { "supportsConfigurationDoneRequest": true },
    })
    is Response(response) else {
    fail("expected a response")
  }
  assert_eq(response.seq, 3)
  assert_eq(response.request_seq, 1)
  assert_eq(response.command, Some("initialize"))
  assert_true(response.success)
  assert_true(response.body is { "supportsConfigurationDoneRequest": True, .. })
  guard classify_message({
      "seq": 4,
      "type": "request",
      "command": "runInTerminal",
      "arguments": { "kind": "integrated" },
    })
    is Request(request) else {
    fail("expected an adapter request")
  }
  assert_eq(request.seq, 4)
  assert_eq(request.command, "runInTerminal")
  assert_true(request.arguments is { "kind": String("integrated"), .. })
}

///|
test "inbox matches request_seq and buffers an early unrelated response" {
  let inbox = DapInbox::new()
  let second = test_response(20, 2, "configurationDone", { "second": true })
  assert_true(inbox.route(Response(second), 1) is BufferedResponse)
  let initialized = test_event("initialized", { "adapter": "lldb-dap" })
  assert_true(
    inbox.route(Event(initialized), 1)
    is SessionEvent({ name: "initialized", .. }),
  )
  let first = test_response(21, 1, "launch", { "first": true })
  assert_true(
    inbox.route(Response(first), 1) is Matched({ request_seq: 1, .. }),
  )
  guard inbox.take_response(2) is Some(buffered) else {
    fail("response 2 should have been buffered")
  }
  assert_eq(buffered.command, Some("configurationDone"))
  assert_true(buffered.body is { "second": True, .. })
  assert_true(inbox.take_response(2) is None)
}
