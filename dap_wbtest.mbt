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
test "stepping responses pair by request seq without losing a stop event" {
  let cases = [
    (DapStepKind::DapNext, "next"),
    (DapStepKind::DapStepIn, "stepIn"),
    (DapStepKind::DapStepOut, "stepOut"),
  ]
  for index, case in cases {
    let (_, command) = case
    let request_seq = 70 + index
    let inbox = DapInbox::new()
    let stopped = test_event("stopped", { "reason": "step", "threadId": 41 })
    guard inbox.route(Event(stopped), request_seq) is SessionEvent(event) else {
      fail("step stop event should be routed to the session")
    }
    assert_eq(event.name, "stopped")
    assert_true(
      event.body is { "reason": String("step"), "threadId": Number(41, ..), .. },
    )
    let response = test_response(80 + index, request_seq, command, {})
    guard inbox.route(Response(response), request_seq) is Matched(matched) else {
      fail("step response should match its request")
    }
    assert_eq(matched.request_seq, request_seq)
    assert_eq(matched.command, Some(command))
    validate_response(matched, command) |> ignore
  }
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
  let state = ExecutionBreakpointState::new()
  apply_breakpoint_response(
    state,
    [first, second],
    test_response(40, 4, "setBreakpoints", {
      "breakpoints": [
        { "id": 17, "verified": true, "line": 5 },
        { "verified": false, "message": "no executable code at this location" },
      ],
    }),
  )
  let first_snapshot = state.snapshot(first)
  assert_eq(first_snapshot.id(), 1)
  assert_eq(first_snapshot.requested_line(), 4)
  assert_eq(first_snapshot.actual_line(), Some(5))
  assert_true(first_snapshot.status() is Verified)
  let second_snapshot = state.snapshot(second)
  assert_eq(second_snapshot.id(), 2)
  assert_true(
    second_snapshot.status() is Rejected("no executable code at this location"),
  )
}

///|
test "a failed setBreakpoints response rejects the complete source set" {
  let first = LogicalBreakpoint::new(1, "/tmp/main.mbt", 4)
  let second = LogicalBreakpoint::new(2, "/tmp/main.mbt", 9)
  let state = ExecutionBreakpointState::new()
  apply_breakpoint_response(state, [first, second], {
    seq: 41,
    request_seq: 5,
    command: Some("setBreakpoints"),
    success: false,
    message: Some("source is unavailable"),
    body: null,
  })
  assert_true(
    state.snapshot(first).status() is Rejected("source is unavailable"),
  )
  assert_true(
    state.snapshot(second).status() is Rejected("source is unavailable"),
  )
}

///|
test "adapter breakpoint outcomes are isolated per execution" {
  let breakpoint = LogicalBreakpoint::new(1, "/tmp/main.mbt", 4)
  let first = ExecutionBreakpointState::new()
  let second = ExecutionBreakpointState::new()
  first.verify(breakpoint, Some(5), Some(17))
  assert_true(first.snapshot(breakpoint).status() is Verified)
  assert_true(second.snapshot(breakpoint).status() is Pending)
  assert_eq(second.snapshot(breakpoint).actual_line(), None)
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

///|
test "P5 scopes exclude register-only lookup and variables retain DAP fields" {
  guard parse_scopes({
      "scopes": [
        {
          "name": "Locals",
          "presentationHint": "locals",
          "variablesReference": 1,
        },
        { "name": "Globals", "variablesReference": 2 },
        {
          "name": "Registers",
          "presentationHint": "registers",
          "variablesReference": 3,
        },
      ],
    })
    is Some([locals, globals, registers]) else {
    fail("expected three parsed scopes")
  }
  assert_true(locals.is_relevant())
  assert_true(globals.is_relevant())
  assert_false(registers.is_relevant())
  guard parse_variables({
      "variables": [
        {
          "name": "answer",
          "type": "int",
          "value": "42",
          "variablesReference": 0,
        },
      ],
    })
    is Some([variable]) else {
    fail("expected one parsed variable")
  }
  let snapshot = variable.snapshot()
  assert_eq(snapshot.name(), "answer")
  assert_eq(snapshot.type_name(), Some("int"))
  assert_eq(snapshot.value(), "42")
  assert_eq(snapshot.variables_reference(), 0)
}

///|
test "P5 variable caches are isolated by stop epoch" {
  let cache = StopVariableCache::new()
  let scopes = [
    DapScope::{
      name: "Locals",
      variables_reference: 1,
      presentation_hint: Some("locals"),
    },
  ]
  let variables = [
    DapVariable::{
      name: "answer",
      value: "42",
      type_name: Some("int"),
      variables_reference: 0,
    },
  ]
  cache.reset(1)
  cache.store_scopes(1, scopes)
  cache.store_variables(1, 1, variables)
  assert_true(cache.cached_scopes(1) is Some(_))
  assert_true(cache.cached_variables(1, 1) is Some(_))
  cache.reset(2)
  assert_true(cache.cached_scopes(1) is None)
  assert_true(cache.cached_variables(1, 1) is None)
  assert_true(cache.cached_scopes(2) is None)
  cache.store_variables(1, 1, variables)
  assert_true(cache.cached_variables(2, 1) is None)
}

///|
test "P5 output events preserve user text and discard adapter-only output" {
  guard output_from_event(
      test_event("output", { "category": "stdout", "output": "42\n" }),
    )
    is Some(output) else {
    fail("expected stdout output")
  }
  assert_eq(output.category(), Some("stdout"))
  assert_eq(output.text(), "42\n")
  assert_true(
    output_from_event(
      test_event("output", {
        "category": "telemetry",
        "output": "internal metrics",
      }),
    )
    is None,
  )
  assert_true(
    output_from_event(
      test_event("output", {
        "category": "console",
        "output": "Process exited with status = 0",
      }),
    )
    is None,
  )
}

///|
test "P5 a second stop creates a new epoch after resume" {
  let machine = DebugSessionMachine::new()
  machine.begin_execution()
  machine.mark_running()
  machine.accept_event(test_event("stopped", { "threadId": 7 }))
  assert_eq(machine.current_stop_epoch(), Some(1))
  machine.mark_resumed()
  assert_eq(machine.current_stop_epoch(), None)
  machine.accept_event(test_event("stopped", { "threadId": 7 }))
  assert_eq(machine.current_stop_epoch(), Some(2))
}
