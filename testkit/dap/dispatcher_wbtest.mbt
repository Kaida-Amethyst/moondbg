///|
fn response_message(
  seq : Int,
  request_seq : Int,
  command : String,
  body : Json,
) -> Json {
  {
    "seq": seq,
    "type": "response",
    "request_seq": request_seq,
    "command": command,
    "success": true,
    "body": body,
  }
}

///|
fn event_message(seq : Int, name : String, body : Json) -> Json {
  { "seq": seq, "type": "event", "event": name, "body": body }
}

///|
async test "dispatcher allocates sequence numbers and sends complete requests" {
  let transport = ScriptedTransport::new([])
  let dispatcher = @dap_protocol.DapDispatcher::from_transport(
    transport.as_transport(),
  )
  assert_eq(dispatcher.send_request("initialize", { "clientID": "moondbg" }), 1)
  assert_eq(dispatcher.send_request("threads", {}), 2)
  guard transport.sent_messages() is [initialize, threads] else {
    fail("expected two complete DAP requests")
  }
  assert_true(
    initialize
    is {
      "seq": Number(1, ..),
      "type": String("request"),
      "command": String("initialize"),
      "arguments": { "clientID": String("moondbg"), .. },
      ..
    },
  )
  assert_true(
    threads
    is {
      "seq": Number(2, ..),
      "type": String("request"),
      "command": String("threads"),
      "arguments": { },
      ..
    },
  )
}

///|
async test "dispatcher buffers out-of-order responses without losing events" {
  let transport = ScriptedTransport::new([
    ScriptedMessage(response_message(20, 2, "configurationDone", {})),
    ScriptedMessage(event_message(21, "initialized", {})),
    ScriptedMessage(response_message(22, 1, "launch", {})),
  ])
  let dispatcher = @dap_protocol.DapDispatcher::from_transport(
    transport.as_transport(),
  )
  assert_true(dispatcher.next_for_request(1) is @dap_protocol.BufferedResponse)
  assert_true(
    dispatcher.next_for_request(1) is @dap_protocol.SessionEvent(event) &&
    event.name() == "initialized",
  )
  assert_true(
    dispatcher.next_for_request(1) is @dap_protocol.Matched(response) &&
    response.command() == Some("launch"),
  )
  assert_true(
    dispatcher.next_for_request(2) is @dap_protocol.Matched(response) &&
    response.command() == Some("configurationDone"),
  )
  assert_eq(transport.remaining_inputs(), 0)
}

///|
async test "dispatcher routes adapter requests" {
  let transport = ScriptedTransport::new([
    ScriptedMessage({
      "seq": 30,
      "type": "request",
      "command": "runInTerminal",
      "arguments": { "kind": "integrated" },
    }),
  ])
  let dispatcher = @dap_protocol.DapDispatcher::from_transport(
    transport.as_transport(),
  )
  assert_true(
    dispatcher.next() is @dap_protocol.AdapterRequest(request) &&
    request.command() == "runInTerminal",
  )
}

///|
async test "dispatcher rejects invalid sequences and duplicate responses" {
  let invalid = ScriptedTransport::new([
    ScriptedMessage(event_message(-1, "initialized", {})),
  ])
  let invalid_dispatcher = @dap_protocol.DapDispatcher::from_transport(
    invalid.as_transport(),
  )
  let rejected_sequence = try {
    invalid_dispatcher.next() |> ignore
    false
  } catch {
    @dap_protocol.InvalidSequence(-1) => true
    _ => false
  }
  assert_true(rejected_sequence)

  let duplicate = ScriptedTransport::new([
    ScriptedMessage(response_message(40, 2, "threads", {})),
    ScriptedMessage(response_message(41, 2, "threads", {})),
  ])
  let duplicate_dispatcher = @dap_protocol.DapDispatcher::from_transport(
    duplicate.as_transport(),
  )
  assert_true(
    duplicate_dispatcher.next_for_request(1) is @dap_protocol.BufferedResponse,
  )
  let rejected_duplicate = try {
    duplicate_dispatcher.next_for_request(1) |> ignore
    false
  } catch {
    @dap_protocol.DuplicateResponse(2) => true
    _ => false
  }
  assert_true(rejected_duplicate)
}

///|
async test "dispatcher propagates EOF transport errors and explicit close" {
  let eof = ScriptedTransport::new([ScriptedClosed])
  let eof_dispatcher = @dap_protocol.DapDispatcher::from_transport(
    eof.as_transport(),
  )
  let reached_eof = try {
    eof_dispatcher.next() |> ignore
    false
  } catch {
    @dap_protocol.AdapterClosed => true
    _ => false
  }
  assert_true(reached_eof)

  let failed = ScriptedTransport::new([ScriptedFailure("read failed")])
  let failed_dispatcher = @dap_protocol.DapDispatcher::from_transport(
    failed.as_transport(),
  )
  let propagated_failure = try {
    failed_dispatcher.next() |> ignore
    false
  } catch {
    ScriptedTransportFailure("read failed") => true
    _ => false
  }
  assert_true(propagated_failure)

  let closed = ScriptedTransport::new([])
  let closed_dispatcher = @dap_protocol.DapDispatcher::from_transport(
    closed.as_transport(),
  )
  closed_dispatcher.close()
  assert_true(closed.is_closed())
  let rejected_send = try {
    closed_dispatcher.send_request("threads", {}) |> ignore
    false
  } catch {
    @dap_protocol.AdapterClosed => true
    _ => false
  }
  assert_true(rejected_send)
}
