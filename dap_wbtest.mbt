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

///|
test "initialized and stopped events advance the session state machine" {
  let machine = DebugSessionMachine::new()
  assert_true(machine.state is Ready)
  assert_eq(machine.execution_epoch, 0)
  machine.begin_execution()
  assert_true(machine.state is Preparing)
  assert_eq(machine.execution_epoch, 1)
  machine.accept_event(test_event("initialized", {}))
  assert_true(machine.state is Configuring)
  machine.mark_running()
  assert_true(machine.state is Running)
  machine.accept_event(test_event("stopped", { "threadId": 7 }))
  assert_true(machine.state is Stopped)
  assert_eq(machine.stop_epoch, 1)
  assert_true(machine.stop_context is Some({ thread_id: Some(7), .. }))
}

///|
test "a duplicate stable event does not advance the stop epoch twice" {
  let machine = DebugSessionMachine::new()
  machine.begin_execution()
  machine.mark_running()
  let stopped = test_event("stopped", { "threadId": 7 })
  machine.accept_event(stopped)
  machine.accept_event(stopped)
  assert_true(machine.state is Stopped)
  assert_eq(machine.stop_epoch, 1)
}

///|
test "an early stable event is not lost while its response is still pending" {
  let inbox = DapInbox::new()
  let machine = DebugSessionMachine::new()
  machine.begin_execution()
  machine.mark_running()
  let stopped = test_event("stopped", { "threadId": 9 })
  guard inbox.route(Event(stopped), 30) is SessionEvent(event) else {
    fail("stopped should be routed to the session")
  }
  machine.accept_event(event)
  assert_true(machine.state is Stopped)
  let response = test_response(31, 30, "continue", {
    "allThreadsContinued": true,
  })
  assert_true(
    inbox.route(Response(response), 30) is Matched({ request_seq: 30, .. }),
  )
  assert_true(machine.state is Stopped)
  assert_eq(machine.stop_epoch, 1)
}

///|
test "exited and terminated collapse into one terminal state" {
  let machine = DebugSessionMachine::new()
  machine.begin_execution()
  machine.mark_running()
  machine.accept_event(test_event("exited", { "exitCode": 0 }))
  assert_true(machine.state is Exited)
  machine.accept_event(test_event("terminated", {}))
  assert_true(machine.state is Exited)
  assert_eq(machine.execution_epoch, 1)
}

///|
test "adapter failure enters Failed and clears the current stop context" {
  let machine = DebugSessionMachine::new()
  machine.begin_execution()
  machine.mark_running()
  machine.accept_event(test_event("stopped", { "threadId": 7 }))
  machine.select_frame(42)
  machine.fail("adapter closed")
  assert_true(machine.state is Failed)
  assert_eq(machine.failure_message, Some("adapter closed"))
  assert_false(machine.has_current_frame(42))
  machine.accept_event(test_event("terminated", {}))
  assert_true(machine.state is Failed)
}

///|
test "resuming invalidates frame and variable references from the stop epoch" {
  let machine = DebugSessionMachine::new()
  machine.begin_execution()
  machine.mark_running()
  machine.accept_event(test_event("stopped", { "threadId": 7 }))
  machine.select_frame(42)
  machine.remember_variable_reference(99)
  assert_true(machine.has_current_frame(42))
  assert_true(machine.has_current_variable_reference(99))
  machine.mark_resumed()
  assert_true(machine.state is Running)
  assert_false(machine.has_current_frame(42))
  assert_false(machine.has_current_variable_reference(99))
}

///|
test "breakpoint responses preserve moondbg ids and adapter outcomes" {
  let first = LogicalBreakpoint::new(1, "/tmp/main.mbt", 4)
  let second = LogicalBreakpoint::new(2, "/tmp/main.mbt", 9)
  apply_breakpoint_response(
    [first, second],
    test_response(40, 4, "setBreakpoints", {
      "breakpoints": [
        { "id": 17, "verified": true, "line": 5 },
        { "verified": false, "message": "no executable code at this location" },
      ],
    }),
  )
  let first_snapshot = first.snapshot()
  assert_eq(first_snapshot.id(), 1)
  assert_eq(first_snapshot.requested_line(), 4)
  assert_eq(first_snapshot.actual_line(), Some(5))
  assert_true(first_snapshot.status() is Verified)
  let second_snapshot = second.snapshot()
  assert_eq(second_snapshot.id(), 2)
  assert_true(
    second_snapshot.status() is Rejected("no executable code at this location"),
  )
}

///|
test "a failed setBreakpoints response rejects the complete source set" {
  let first = LogicalBreakpoint::new(1, "/tmp/main.mbt", 4)
  let second = LogicalBreakpoint::new(2, "/tmp/main.mbt", 9)
  apply_breakpoint_response([first, second], {
    seq: 41,
    request_seq: 5,
    command: Some("setBreakpoints"),
    success: false,
    message: Some("source is unavailable"),
    body: null,
  })
  assert_true(first.snapshot().status() is Rejected("source is unavailable"))
  assert_true(second.snapshot().status() is Rejected("source is unavailable"))
}

///|
test "setBreakpoints arguments replace the complete set for one source" {
  let first = LogicalBreakpoint::new(1, "/tmp/main.mbt", 4)
  let second = LogicalBreakpoint::new(2, "/tmp/other.mbt", 7)
  let third = LogicalBreakpoint::new(3, "/tmp/main.mbt", 9)
  let selected = breakpoints_for_source([first, second, third], "/tmp/main.mbt")
  assert_eq(selected.length(), 2)
  let arguments = set_breakpoints_arguments("/tmp/main.mbt", selected)
  guard arguments
    is {
      "source": { "path": String("/tmp/main.mbt"), .. },
      "breakpoints": Array(breakpoints),
      "sourceModified": False,
      ..
    } else {
    fail("expected complete source breakpoint arguments")
  }
  assert_eq(breakpoints.length(), 2)
  assert_true(breakpoints[0] is { "line": Number(4, ..), .. })
  assert_true(breakpoints[1] is { "line": Number(9, ..), .. })
}

///|
test "stack frame selection prefers the first MoonBit source frame" {
  guard select_stack_frame({
      "stackFrames": [
        {
          "id": 10,
          "name": "runtime_entry",
          "source": { "path": "/tmp/runtime.c" },
          "line": 20,
          "column": 1,
        },
        {
          "id": 11,
          "name": "main.inspect_value",
          "source": { "path": "/tmp/main.mbt" },
          "line": 4,
          "column": 3,
        },
      ],
    })
    is Some(frame) else {
    fail("expected a stack frame")
  }
  assert_eq(frame.id, 11)
  assert_eq(frame.name, "main.inspect_value")
  assert_eq(frame.source_path, Some("/tmp/main.mbt"))
  assert_eq(frame.line, Some(4))
  assert_eq(frame.column, Some(3))
}

///|
test "thread fallback selects the first DAP thread" {
  assert_eq(
    first_thread_id({
      "threads": [{ "id": 7, "name": "worker" }, { "id": 9, "name": "main" }],
    }),
    Some(7),
  )
  assert_eq(first_thread_id({ "threads": [] }), None)
}
