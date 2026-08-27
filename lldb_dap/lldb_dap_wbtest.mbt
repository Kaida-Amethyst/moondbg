///|
fn LogicalBreakpoint::new(
  id : Int,
  source_path : String,
  requested_line : Int,
) -> LogicalBreakpoint {
  { id, source_path, requested_line, }
}

///|
fn test_event(name : String, body : Json) -> @dap.DapEvent raise {
  guard @dap.classify_message({
      "seq": 10,
      "type": "event",
      "event": name,
      "body": body,
    })
    is @dap.Event(event) else {
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
) -> @dap.DapResponse raise {
  guard @dap.classify_message({
      "seq": seq,
      "type": "response",
      "request_seq": request_seq,
      "command": command,
      "success": true,
      "body": body,
    })
    is @dap.Response(response) else {
    fail("expected a DAP response")
  }
  response
}

///|
fn test_failed_response(
  seq : Int,
  request_seq : Int,
  command : String,
  message : String,
) -> @dap.DapResponse raise {
  guard @dap.classify_message({
      "seq": seq,
      "type": "response",
      "request_seq": request_seq,
      "command": command,
      "success": false,
      "message": message,
    })
    is @dap.Response(response) else {
    fail("expected a failed DAP response")
  }
  response
}

///|
test "lldb-dap resume kinds share request construction and user actions" {
  let capabilities : Json = { "supportsSteppingGranularity": true }
  let cases = [
    (StepExecution(@dap.DapNext), "next", "step over"),
    (StepExecution(@dap.DapStepIn), "stepIn", "step into"),
    (StepExecution(@dap.DapStepOut), "stepOut", "step out"),
  ]
  for _, case in cases {
    let (kind, command, action) = case
    let request = kind.request(9, capabilities)
    assert_eq(kind.action(), action)
    assert_eq(request.command(), command)
    assert_true(
      request.arguments()
      is { "threadId": Number(9, ..), "granularity": String("line"), .. },
    )
  }
  let fallback = StepExecution(@dap.DapNext).request(10, {})
  assert_true(fallback.arguments() is { "threadId": Number(10, ..), .. })
  assert_false(fallback.arguments().stringify().contains("granularity"))
  let continue_request = ContinueExecution.request(11, capabilities)
  assert_eq(ContinueExecution.action(), "continue execution")
  assert_eq(continue_request.command(), "continue")
  assert_true(
    continue_request.arguments()
    is { "threadId": Number(11, ..), "singleThread": False, .. },
  )
}

///|
async test "lldb-dap stepping shares stop epochs snapshots and variable invalidation" {
  @async.with_task_group(async fn(group) {
    let executable = "/tmp/moondbg-p2-fake-program"
    let backend = LldbDapBackend::start(
      group,
      "tools/fake_dap.py",
      preparation_timeout_ms=10000,
    )
    let session = @moondbg.DebugSession::new(executable, backend)
    defer session.close()
    let rejected = try {
      session.next() |> ignore
      false
    } catch {
      @moondbg.OperationNotAllowed(state~, action~) =>
        state is @moondbg.Ready && action == "step over"
      _ => false
    }
    assert_true(rejected)
    let pending = session.add_source_breakpoint("/tmp/main.mbt", 4)
    assert_eq(pending.id(), 1)
    guard session.run() is @moondbg.Stopped(_) else {
      fail("fake execution should stop after launch")
    }
    guard backend.session.breakpoints is [logical] else {
      fail("backend should import one stable source breakpoint")
    }
    assert_eq(logical.id, pending.id())
    assert_eq(logical.source_path, "/tmp/main.mbt")
    assert_eq(logical.requested_line, 4)
    guard backend.session.execution is Some(execution) else {
      fail("stopped session should retain its execution")
    }
    assert_eq(execution.machine.stop_epoch, 1)
    guard session.find_variable("answer") is @moondbg.VariableFound(variable) else {
      fail("fake execution should expose answer")
    }
    assert_eq(variable.value(), "42")
    assert_true(execution.variable_cache.cached_scopes(1) is Some(_))
    guard session.next() is @moondbg.Stopped(after_next) else {
      fail("next should stop again")
    }
    assert_eq(after_next.reason(), "step")
    assert_eq(execution.machine.stop_epoch, 2)
    assert_true(execution.variable_cache.cached_scopes(1) is None)
    guard session.step() is @moondbg.Stopped(after_step) else {
      fail("step should stop again")
    }
    assert_eq(after_step.reason(), "step")
    assert_eq(execution.machine.stop_epoch, 3)
    guard session.finish() is @moondbg.Stopped(after_finish) else {
      fail("finish should stop again")
    }
    assert_eq(after_finish.reason(), "step")
    assert_eq(execution.machine.stop_epoch, 4)
    assert_eq(execution.machine.selected_thread_id(), Some(1))
    session.disconnect()
    assert_true(session.state() is @moondbg.Exited)
  })
}

///|
test "initialized and stopped events advance the session state machine" {
  let machine = DapSessionMachine::new()
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
  let machine = DapSessionMachine::new()
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
  let machine = DapSessionMachine::new()
  machine.begin_execution()
  machine.mark_running()
  let stopped = test_event("stopped", { "threadId": 9 })
  machine.accept_event(stopped)
  assert_true(machine.state is Stopped)
  let response = test_response(31, 30, "continue", {
    "allThreadsContinued": true,
  })
  validate_response(response, "continue") |> ignore
  assert_true(machine.state is Stopped)
  assert_eq(machine.stop_epoch, 1)
}

///|
test "exited and terminated collapse into one terminal state" {
  let machine = DapSessionMachine::new()
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
  let machine = DapSessionMachine::new()
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
  let machine = DapSessionMachine::new()
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
test "a fallback thread id is retained in the current stop epoch" {
  let machine = DapSessionMachine::new()
  machine.begin_execution()
  machine.mark_running()
  machine.accept_event(test_event("stopped", {}))
  assert_eq(machine.selected_thread_id(), None)
  machine.select_thread(13)
  assert_eq(machine.selected_thread_id(), Some(13))
  machine.mark_resumed()
  assert_eq(machine.selected_thread_id(), None)
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
  assert_true(first_snapshot.status() is @moondbg.Verified)
  let second_snapshot = state.snapshot(second)
  assert_eq(second_snapshot.id(), 2)
  assert_true(
    second_snapshot.status()
    is @moondbg.Rejected("no executable code at this location"),
  )
}

///|
test "a failed setBreakpoints response rejects the complete source set" {
  let first = LogicalBreakpoint::new(1, "/tmp/main.mbt", 4)
  let second = LogicalBreakpoint::new(2, "/tmp/main.mbt", 9)
  let state = ExecutionBreakpointState::new()
  apply_breakpoint_response(
    state,
    [first, second],
    test_failed_response(41, 5, "setBreakpoints", "source is unavailable"),
  )
  assert_true(
    state.snapshot(first).status() is @moondbg.Rejected("source is unavailable"),
  )
  assert_true(
    state.snapshot(second).status()
    is @moondbg.Rejected("source is unavailable"),
  )
}

///|
test "adapter breakpoint outcomes are isolated per execution" {
  let breakpoint = LogicalBreakpoint::new(1, "/tmp/main.mbt", 4)
  let first = ExecutionBreakpointState::new()
  let second = ExecutionBreakpointState::new()
  first.verify(breakpoint, Some(5), Some(17))
  assert_true(first.snapshot(breakpoint).status() is @moondbg.Verified)
  assert_true(second.snapshot(breakpoint).status() is @moondbg.Pending)
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
test "lldb-dap scopes exclude register-only lookup and variables retain DAP fields" {
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
  assert_eq(variable.variables_reference, 0)
}

///|
test "lldb-dap variable caches are isolated by stop epoch" {
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
test "lldb-dap output events preserve user text and discard adapter-only output" {
  guard output_from_event(
      test_event("output", { "category": "stdout", "output": "42\n" }),
    )
    is Some(output) else {
    fail("expected stdout output")
  }
  assert_true(output.kind() is @moondbg.StandardOutput)
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
test "lldb-dap a second stop creates a new epoch after resume" {
  let machine = DapSessionMachine::new()
  machine.begin_execution()
  machine.mark_running()
  machine.accept_event(test_event("stopped", { "threadId": 7 }))
  assert_eq(machine.current_stop_epoch(), Some(1))
  machine.mark_resumed()
  assert_eq(machine.current_stop_epoch(), None)
  machine.accept_event(test_event("stopped", { "threadId": 7 }))
  assert_eq(machine.current_stop_epoch(), Some(2))
}
