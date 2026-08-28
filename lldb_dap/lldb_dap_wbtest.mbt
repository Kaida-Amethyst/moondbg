///|
fn LogicalSourceBreakpoint::new(
  id : Int,
  source_path : String,
  requested_line : Int,
) -> LogicalSourceBreakpoint {
  { id, source_path, requested_line, }
}

///|
fn LogicalFunctionBreakpoint::new(
  id : Int,
  display_name : String,
  physical_name : String,
) -> LogicalFunctionBreakpoint {
  {
    id,
    display_name,
    selector: @moondbg.FunctionBreakpointSelector::exact_physical(physical_name),
  }
}

///|
fn LogicalFunctionBreakpoint::family(
  id : Int,
  display_name : String,
  base : String,
) -> LogicalFunctionBreakpoint {
  {
    id,
    display_name,
    selector: @moondbg.FunctionBreakpointSelector::family(base),
  }
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
fn scripted_response(
  seq : Int,
  request_seq : Int,
  command : String,
  body : Json,
) -> @dap_testkit.ScriptedInput {
  @dap_testkit.ScriptedMessage({
    "seq": seq,
    "type": "response",
    "request_seq": request_seq,
    "command": command,
    "success": true,
    "body": body,
  })
}

///|
fn scripted_failed_response(
  seq : Int,
  request_seq : Int,
  command : String,
  message : String,
) -> @dap_testkit.ScriptedInput {
  @dap_testkit.ScriptedMessage({
    "seq": seq,
    "type": "response",
    "request_seq": request_seq,
    "command": command,
    "success": false,
    "message": message,
  })
}

///|
fn scripted_event(
  seq : Int,
  name : String,
  body : Json,
) -> @dap_testkit.ScriptedInput {
  @dap_testkit.ScriptedMessage({
    "seq": seq,
    "type": "event",
    "event": name,
    "body": body,
  })
}

///|
fn scripted_stack_body(frame_id : Int, line : Int) -> Json {
  {
    "stackFrames": [
      {
        "id": frame_id,
        "name": "main.inspect_value",
        "source": { "path": "/tmp/main.mbt" },
        "line": line,
        "column": 3,
      },
    ],
  }
}

///|
fn lifecycle_script() -> Array[@dap_testkit.ScriptedInput] {
  [
    scripted_response(100, 1, "initialize", {
      "supportsConfigurationDoneRequest": true,
      "supportsSteppingGranularity": true,
    }),
    scripted_event(101, "initialized", {}),
    scripted_response(102, 3, "setBreakpoints", {
      "breakpoints": [{ "id": 17, "verified": true, "line": 4 }],
    }),
    scripted_response(103, 4, "configurationDone", {}),
    scripted_response(104, 2, "launch", {}),
    scripted_event(105, "output", {
      "category": "stdout",
      "output": "hello from debuggee\n",
    }),
    scripted_event(106, "output", {
      "category": "telemetry",
      "output": "adapter metrics",
    }),
    scripted_event(107, "stopped", { "reason": "breakpoint", "threadId": 1 }),
    scripted_response(108, 5, "stackTrace", scripted_stack_body(10, 4)),
    scripted_response(109, 6, "scopes", {
      "scopes": [
        {
          "name": "Locals",
          "presentationHint": "locals",
          "variablesReference": 100,
        },
        {
          "name": "Registers",
          "presentationHint": "registers",
          "variablesReference": 200,
        },
      ],
    }),
    scripted_response(110, 7, "variables", {
      "variables": [
        {
          "name": "answer",
          "type": "int",
          "value": "42",
          "variablesReference": 0,
        },
      ],
    }),
    scripted_event(111, "stopped", { "reason": "step", "threadId": 1 }),
    scripted_response(112, 8, "next", {}),
    scripted_response(113, 9, "stackTrace", scripted_stack_body(11, 5)),
    scripted_response(114, 10, "stepIn", {}),
    scripted_event(115, "stopped", { "reason": "step", "threadId": 1 }),
    scripted_response(116, 11, "stackTrace", scripted_stack_body(12, 6)),
    scripted_response(117, 12, "stepOut", {}),
    scripted_event(118, "stopped", { "reason": "step", "threadId": 1 }),
    scripted_response(119, 13, "stackTrace", scripted_stack_body(13, 7)),
    scripted_event(120, "terminated", {}),
  ]
}

///|
fn function_family_script() -> Array[@dap_testkit.ScriptedInput] {
  [
    scripted_response(200, 1, "initialize", {
      "supportsConfigurationDoneRequest": true,
      "supportsFunctionBreakpoints": true,
    }),
    scripted_event(201, "initialized", {}),
    scripted_response(202, 3, "evaluate", {
      "result": "Breakpoint 7: 2 locations.\n",
      "variablesReference": 0,
    }),
    scripted_response(203, 4, "configurationDone", {}),
    scripted_response(204, 2, "launch", {}),
    scripted_event(205, "stopped", {
      "reason": "breakpoint",
      "threadId": 1,
      "hitBreakpointIds": [7],
    }),
    scripted_response(206, 5, "stackTrace", scripted_stack_body(20, 8)),
  ]
}

///|
fn dynamic_breakpoint_script() -> Array[@dap_testkit.ScriptedInput] {
  [
    scripted_response(300, 1, "initialize", {
      "supportsConfigurationDoneRequest": true,
      "supportsFunctionBreakpoints": true,
    }),
    scripted_event(301, "initialized", {}),
    scripted_response(302, 3, "configurationDone", {}),
    scripted_response(303, 2, "launch", {}),
    scripted_event(304, "stopped", { "reason": "entry", "threadId": 1 }),
    scripted_response(305, 4, "stackTrace", scripted_stack_body(30, 3)),
    scripted_response(306, 5, "setBreakpoints", {
      "breakpoints": [{ "id": 17, "verified": true, "line": 4 }],
    }),
    scripted_response(307, 6, "setBreakpoints", {
      "breakpoints": [
        { "id": 27, "verified": true, "line": 5 },
        { "id": 28, "verified": true, "line": 9 },
      ],
    }),
    scripted_response(308, 7, "setFunctionBreakpoints", {
      "breakpoints": [{ "id": 37, "verified": true }],
    }),
    scripted_response(309, 8, "setFunctionBreakpoints", {
      "breakpoints": [
        { "id": 47, "verified": true },
        { "id": 48, "verified": true },
      ],
    }),
    scripted_response(310, 9, "evaluate", {
      "result": "Breakpoint 57: 2 locations.\n",
      "variablesReference": 0,
    }),
    scripted_response(311, 10, "evaluate", {
      "result": "Breakpoint 58: no locations (pending).\n",
      "variablesReference": 0,
    }),
    scripted_failed_response(312, 11, "setBreakpoints", "source is unavailable"),
  ]
}

///|
fn stopped_execution_script(
  first_seq : Int,
) -> Array[@dap_testkit.ScriptedInput] {
  [
    scripted_response(first_seq, 1, "initialize", {
      "supportsConfigurationDoneRequest": true,
    }),
    scripted_event(first_seq + 1, "initialized", {}),
    scripted_response(first_seq + 2, 3, "configurationDone", {}),
    scripted_response(first_seq + 3, 2, "launch", {}),
    scripted_event(first_seq + 4, "stopped", {
      "reason": "entry",
      "threadId": 1,
    }),
    scripted_response(
      first_seq + 5,
      4,
      "stackTrace",
      scripted_stack_body(40, 3),
    ),
  ]
}

///|
fn struct_variable_script() -> Array[@dap_testkit.ScriptedInput] {
  [
    scripted_response(1300, 1, "initialize", {
      "supportsConfigurationDoneRequest": true,
    }),
    scripted_event(1301, "initialized", {}),
    scripted_response(1302, 3, "configurationDone", {}),
    scripted_response(1303, 2, "launch", {}),
    scripted_event(1304, "stopped", { "reason": "breakpoint", "threadId": 1 }),
    scripted_response(1305, 4, "stackTrace", scripted_stack_body(70, 20)),
    scripted_response(1306, 5, "scopes", {
      "scopes": [
        {
          "name": "Locals",
          "presentationHint": "locals",
          "variablesReference": 100,
        },
      ],
    }),
    scripted_response(1307, 6, "variables", {
      "variables": [
        {
          "name": "line1",
          "type": "example/geometry/Line &",
          "value": "0x1000",
          "variablesReference": 101,
        },
        {
          "name": "arr",
          "type": "example/OpaqueAggregate",
          "value": "moonbit.array_i32 @ 0x2000",
          "variablesReference": 102,
        },
        {
          "name": "choice",
          "type": "example/geometry/Choice &",
          "value": "0x3000",
          "variablesReference": 103,
        },
      ],
    }),
    scripted_response(1308, 7, "variables", {
      "variables": [
        {
          "name": "start",
          "type": "example/geometry/Point &",
          "value": "0x1100",
          "variablesReference": 111,
        },
        {
          "name": "end",
          "type": "example/geometry/Point &",
          "value": "0x1200",
          "variablesReference": 112,
        },
      ],
    }),
    scripted_response(1309, 8, "variables", {
      "variables": [
        { "name": "x", "type": "double", "value": "1", "variablesReference": 0 },
        { "name": "y", "type": "double", "value": "2", "variablesReference": 0 },
      ],
    }),
    scripted_response(1310, 9, "variables", {
      "variables": [
        { "name": "x", "type": "double", "value": "4", "variablesReference": 0 },
        { "name": "y", "type": "double", "value": "6", "variablesReference": 0 },
      ],
    }),
    scripted_response(1311, 10, "variables", {
      "variables": [
        {
          "name": "__moonbit_enum_marker",
          "type": "moonbit.enum",
          "value": "0",
          "variablesReference": 0,
        },
        {
          "name": "Some",
          "type": "example/geometry/Choice.Some *",
          "value": "0x3000",
          "variablesReference": 113,
        },
      ],
    }),
  ]
}

///|
fn field_path_variable_script() -> Array[@dap_testkit.ScriptedInput] {
  let scopes : Json = {
    "scopes": [
      {
        "name": "Locals",
        "presentationHint": "locals",
        "variablesReference": 300,
      },
    ],
  }
  let roots : Json = {
    "variables": [
      {
        "name": "line1",
        "type": "example/geometry/Line &",
        "value": "0x3000",
        "variablesReference": 301,
      },
    ],
  }
  let line_fields : Json = {
    "variables": [
      {
        "name": "start",
        "type": "example/geometry/Point &",
        "value": "0x3100",
        "variablesReference": 311,
      },
      {
        "name": "end",
        "type": "example/geometry/Point &",
        "value": "<error: variable not available>",
        "variablesReference": 312,
      },
      {
        "name": "values",
        "type": "FixedArray[Int]",
        "value": "FixedArray[Int] @ 0x3300",
        "variablesReference": 313,
      },
    ],
  }
  let point_fields : Json = {
    "variables": [
      { "name": "x", "type": "double", "value": "1", "variablesReference": 0 },
      { "name": "y", "type": "double", "value": "2", "variablesReference": 0 },
    ],
  }
  [
    scripted_response(1700, 1, "initialize", {
      "supportsConfigurationDoneRequest": true,
      "supportsReadMemoryRequest": true,
      "supportsSteppingGranularity": true,
    }),
    scripted_event(1701, "initialized", {}),
    scripted_response(1702, 3, "configurationDone", {}),
    scripted_response(1703, 2, "launch", {}),
    scripted_event(1704, "stopped", { "reason": "breakpoint", "threadId": 1 }),
    scripted_response(1705, 4, "stackTrace", scripted_stack_body(110, 20)),
    scripted_response(1706, 5, "scopes", scopes),
    scripted_response(1707, 6, "variables", roots),
    scripted_response(1708, 7, "variables", line_fields),
    scripted_response(1709, 8, "variables", point_fields),
    scripted_response(1710, 9, "variables", {
      "variables": [
        {
          "name": "body",
          "type": "int *",
          "value": "0x3300",
          "evaluateName": "line1.values.body",
          "memoryReference": "0x3300",
          "variablesReference": 0,
        },
      ],
    }),
    scripted_response(1711, 10, "readMemory", { "data": "AAAAAAMAAAA=" }),
    scripted_response(1712, 11, "readMemory", { "data": "AQAAAAIAAAADAAAA" }),
    scripted_event(1713, "stopped", { "reason": "step", "threadId": 1 }),
    scripted_response(1714, 12, "next", {}),
    scripted_response(1715, 13, "stackTrace", scripted_stack_body(111, 21)),
    scripted_response(1716, 14, "scopes", scopes),
    scripted_response(1717, 15, "variables", roots),
    scripted_response(1718, 16, "variables", line_fields),
    scripted_response(1719, 17, "variables", point_fields),
  ]
}

///|
fn truncated_struct_script() -> Array[@dap_testkit.ScriptedInput] {
  [
    scripted_response(1400, 1, "initialize", {
      "supportsConfigurationDoneRequest": true,
    }),
    scripted_event(1401, "initialized", {}),
    scripted_response(1402, 3, "configurationDone", {}),
    scripted_response(1403, 2, "launch", {}),
    scripted_event(1404, "stopped", { "reason": "breakpoint", "threadId": 1 }),
    scripted_response(1405, 4, "stackTrace", scripted_stack_body(80, 20)),
    scripted_response(1406, 5, "variables", {
      "variables": [
        {
          "name": "start",
          "type": "example/geometry/Point &",
          "value": "0x1100",
          "variablesReference": 111,
        },
        {
          "name": "end",
          "type": "example/geometry/Point &",
          "value": "0x1200",
          "variablesReference": 112,
        },
      ],
    }),
  ]
}

///|
fn cyclic_struct_script() -> Array[@dap_testkit.ScriptedInput] {
  [
    scripted_response(1500, 1, "initialize", {
      "supportsConfigurationDoneRequest": true,
    }),
    scripted_event(1501, "initialized", {}),
    scripted_response(1502, 3, "configurationDone", {}),
    scripted_response(1503, 2, "launch", {}),
    scripted_event(1504, "stopped", { "reason": "breakpoint", "threadId": 1 }),
    scripted_response(1505, 4, "stackTrace", scripted_stack_body(90, 20)),
    scripted_response(1506, 5, "variables", {
      "variables": [
        {
          "name": "next",
          "type": "example/Node &",
          "value": "0x1000",
          "variablesReference": 101,
        },
      ],
    }),
  ]
}

///|
fn fixed_array_variable_script() -> Array[@dap_testkit.ScriptedInput] {
  [
    scripted_response(1600, 1, "initialize", {
      "supportsConfigurationDoneRequest": true,
      "supportsReadMemoryRequest": true,
    }),
    scripted_event(1601, "initialized", {}),
    scripted_response(1602, 3, "configurationDone", {}),
    scripted_response(1603, 2, "launch", {}),
    scripted_event(1604, "stopped", { "reason": "breakpoint", "threadId": 1 }),
    scripted_response(1605, 4, "stackTrace", scripted_stack_body(100, 20)),
    scripted_response(1606, 5, "scopes", {
      "scopes": [
        {
          "name": "Locals",
          "presentationHint": "locals",
          "variablesReference": 200,
        },
      ],
    }),
    scripted_response(1607, 6, "variables", {
      "variables": [
        {
          "name": "short",
          "type": "moonbit.array_i32",
          "value": "moonbit.array_i32 @ 0x2000",
          "variablesReference": 201,
        },
        {
          "name": "long",
          "type": "FixedArray[Int]",
          "value": "FixedArray[Int] @ 0x3000",
          "variablesReference": 202,
        },
        {
          "name": "points",
          "type": "FixedArray[Point]",
          "value": "FixedArray[Point] @ 0x4000",
          "variablesReference": 203,
        },
        {
          "name": "empty",
          "type": "FixedArray[Int]",
          "value": "FixedArray[Int] @ 0x0",
          "variablesReference": 204,
        },
      ],
    }),
    scripted_response(1608, 7, "variables", {
      "variables": [
        {
          "name": "body",
          "type": "int *",
          "value": "0x2000",
          "evaluateName": "short.body",
          "memoryReference": "0x2000",
          "variablesReference": 0,
        },
      ],
    }),
    scripted_response(1609, 8, "readMemory", { "data": "AAAAAAMAAAA=" }),
    scripted_response(1610, 9, "readMemory", { "data": "AQAAAAIAAAADAAAA" }),
    scripted_response(1611, 10, "variables", {
      "variables": [
        {
          "name": "body",
          "type": "Int *",
          "value": "0x3000",
          "evaluateName": "long.body",
          "memoryReference": "0x3000",
          "variablesReference": 0,
        },
      ],
    }),
    scripted_response(1612, 11, "readMemory", { "data": "AAAAAGQAAAA=" }),
    scripted_response(1613, 12, "readMemory", {
      "data": "AQAAAAIAAAADAAAABAAAAAUAAAAGAAAABwAAAAgAAAAJAAAACgAAAAsAAAAMAAAADQAAAA4AAAAPAAAA",
    }),
    scripted_response(1614, 13, "readMemory", { "data": "ZAAAAA==" }),
    scripted_response(1615, 14, "variables", {
      "variables": [
        {
          "name": "body",
          "type": "example/geometry/Point **",
          "value": "0x4000",
          "evaluateName": "points.body",
          "memoryReference": "0x4000",
          "variablesReference": 0,
        },
      ],
    }),
    scripted_response(1616, 15, "readMemory", { "data": "AAAAAGQAAAA=" }),
    scripted_response(1617, 16, "variables", {
      "variables": [
        {
          "name": "body",
          "type": "int *",
          "value": "0x0000000000000000",
          "evaluateName": "empty.body",
          "variablesReference": 0,
        },
      ],
    }),
  ]
}

///|
fn sent_command(message : Json) -> String? {
  match message {
    { "command": String(command), .. } => Some(command)
    _ => None
  }
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
async test "scripted lldb-dap lifecycle preserves mappings epochs output and caches" {
  @async.with_task_group(async fn(group) {
    let executable = "/tmp/moondbg-scripted-program"
    let transport = @dap_testkit.ScriptedTransport::new(lifecycle_script())
    let lldb_session = LldbDapSession::start_with_dispatcher_factory(
      group,
      () => @dap.DapDispatcher::from_transport(transport.as_transport()),
      preparation_timeout_ms=10000,
    )
    let backend = LldbDapBackend::{
      session: lldb_session,
      imported_source_breakpoints: 0,
      imported_function_breakpoints: 0,
    }
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
      fail("scripted execution should stop after launch")
    }
    guard backend.session.source_breakpoints is [logical] else {
      fail("backend should import one stable source breakpoint")
    }
    assert_eq(logical.id, pending.id())
    assert_eq(logical.source_path, "/tmp/main.mbt")
    assert_eq(logical.requested_line, 4)
    guard backend.session.execution is Some(execution) else {
      fail("stopped session should retain its execution")
    }
    assert_eq(execution.machine.stop_epoch, 1)
    guard session.take_output() is [output] else {
      fail("only user-visible debuggee output should be retained")
    }
    assert_true(output.kind() is @moondbg.StandardOutput)
    assert_eq(output.text(), "hello from debuggee\n")
    guard session.find_variable(@moondbg.VariablePath::root("answer"))
      is @moondbg.VariableFound(variable) else {
      fail("scripted execution should expose answer")
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
    guard session.source_breakpoints() is [verified] else {
      fail("expected one stable logical breakpoint")
    }
    assert_eq(verified.id(), pending.id())
    assert_eq(verified.actual_line(), Some(4))
    assert_true(verified.status() is @moondbg.Verified)
    session.disconnect()
    assert_true(session.state() is @moondbg.Exited)
    assert_true(transport.is_closed())
    assert_eq(transport.remaining_inputs(), 0)
    assert_eq(transport.sent_messages().filter_map(sent_command), [
      "initialize", "launch", "setBreakpoints", "configurationDone", "stackTrace",
      "scopes", "variables", "next", "stackTrace", "stepIn", "stackTrace", "stepOut",
      "stackTrace", "disconnect",
    ])
  })
}

///|
async test "scripted function family breakpoint uses LLDB command and one logical result" {
  @async.with_task_group(async fn(group) {
    let transport = @dap_testkit.ScriptedTransport::new(
      function_family_script(),
    )
    let lldb_session = LldbDapSession::start_with_dispatcher_factory(
      group,
      () => @dap.DapDispatcher::from_transport(transport.as_transport()),
      preparation_timeout_ms=10000,
    )
    let backend = LldbDapBackend::{
      session: lldb_session,
      imported_source_breakpoints: 0,
      imported_function_breakpoints: 0,
    }
    let debug_context = @moondbg.DebugContext::new("example/app/main", [
      ("util", "example/lib/util"),
    ])
    let session = @moondbg.DebugSession::new(
      "/tmp/moondbg-function-family-program",
      backend,
      debug_context~,
    )
    defer session.close()
    let pending = session.add_function_breakpoint(
      @moondbg.FunctionBreakpointRequest::imported("util", "identity"),
    )
    guard session.run() is @moondbg.Stopped(_) else {
      fail("scripted family breakpoint should stop the execution")
    }
    guard session.function_breakpoints() is [verified] else {
      fail("one function family should remain one logical breakpoint")
    }
    assert_eq(verified.id(), pending.id())
    assert_eq(verified.location_count(), Some(2))
    assert_true(verified.status() is @moondbg.Verified)
    guard backend.session.execution is Some(execution) &&
      execution.breakpoint_state.outcomes.get(pending.id()) is Some(outcome) else {
      fail("LLDB breakpoint id should be retained for the active execution")
    }
    assert_eq(outcome.dap_id, Some(7))
    assert_eq(outcome.location_count, Some(2))
    let sent = transport.sent_messages()
    assert_eq(sent.filter_map(sent_command), [
      "initialize", "launch", "evaluate", "configurationDone", "stackTrace",
    ])
    guard sent[2]
      is {
        "arguments": {
          "context": String("repl"),
          "expression": String(expression),
          ..
        },
        ..
      } else {
      fail("evaluate should carry one LLDB function regex command")
    }
    assert_eq(
      expression, "breakpoint set --func-regex '^_M0FP37example3lib4util8identity($|G|H)'",
    )
  })
}

///|
async test "stopped execution dynamically synchronizes complete sets and one family" {
  @async.with_task_group(async fn(group) {
    let transport = @dap_testkit.ScriptedTransport::new(
      dynamic_breakpoint_script(),
    )
    let session = LldbDapSession::start_with_dispatcher_factory(
      group,
      () => @dap.DapDispatcher::from_transport(transport.as_transport()),
      preparation_timeout_ms=10000,
    )
    defer session.close()
    guard session.run("/tmp/dynamic-program") is @moondbg.Stopped(_) else {
      fail("scripted execution should stop before dynamic synchronization")
    }

    let first_source = LogicalSourceBreakpoint::new(1, "/tmp/main.mbt", 4)
    let first_source_snapshot = session.install_source_breakpoint(first_source)
    assert_true(first_source_snapshot.status() is @moondbg.Verified)
    let second_source = LogicalSourceBreakpoint::new(2, "/tmp/main.mbt", 9)
    let second_source_snapshot = session.install_source_breakpoint(
      second_source,
    )
    assert_true(second_source_snapshot.status() is @moondbg.Verified)

    let first_exact = LogicalFunctionBreakpoint::new(3, "main", "moonbit_main")
    assert_true(
      session.install_function_breakpoint(first_exact).status()
      is @moondbg.Verified,
    )
    let second_exact = LogicalFunctionBreakpoint::new(
      4, "sum", "_M0FP34demo4main3sum",
    )
    assert_true(
      session.install_function_breakpoint(second_exact).status()
      is @moondbg.Verified,
    )

    let family = LogicalFunctionBreakpoint::family(
      5, "identity", "_M0FP34demo3lib8identity",
    )
    let family_snapshot = session.install_function_breakpoint(family)
    assert_true(family_snapshot.status() is @moondbg.Verified)
    assert_eq(family_snapshot.location_count(), Some(2))
    let missing_family = LogicalFunctionBreakpoint::family(
      6, "missing", "_M0FP34demo4main7missing",
    )
    assert_true(
      session.install_function_breakpoint(missing_family).status()
      is @moondbg.Rejected("no matching function instances were found"),
    )

    let rejected_source = LogicalSourceBreakpoint::new(7, "/tmp/missing.mbt", 1)
    assert_true(
      session.install_source_breakpoint(rejected_source).status()
      is @moondbg.Rejected("source is unavailable"),
    )

    guard session.execution is Some(execution) else {
      fail("dynamic synchronization should retain the stopped execution")
    }
    guard execution.breakpoint_state.outcomes.get(1) is Some(first_outcome) &&
      execution.breakpoint_state.outcomes.get(3) is Some(first_exact_outcome) &&
      execution.breakpoint_state.outcomes.get(4) is Some(second_exact_outcome) &&
      execution.breakpoint_state.outcomes.get(5) is Some(family_outcome) else {
      fail("dynamic synchronization should retain all adapter mappings")
    }
    assert_eq(first_outcome.dap_id, Some(27))
    assert_eq(first_outcome.actual_line, Some(5))
    assert_eq(first_exact_outcome.dap_id, Some(47))
    assert_eq(second_exact_outcome.dap_id, Some(48))
    assert_eq(family_outcome.dap_id, Some(57))
    assert_eq(family_outcome.location_count, Some(2))
    assert_eq(session.source_breakpoints.length(), 3)
    assert_eq(session.function_breakpoints.length(), 4)

    let sent = transport.sent_messages()
    assert_eq(sent.filter_map(sent_command), [
      "initialize", "launch", "configurationDone", "stackTrace", "setBreakpoints",
      "setBreakpoints", "setFunctionBreakpoints", "setFunctionBreakpoints", "evaluate",
      "evaluate", "setBreakpoints",
    ])
    guard sent[5]
      is { "arguments": { "breakpoints": Array(source_set), .. }, .. } &&
      sent[7] is { "arguments": { "breakpoints": Array(function_set), .. }, .. } else {
      fail("dynamic replacement requests should carry complete sets")
    }
    assert_eq(source_set.length(), 2)
    assert_eq(function_set.length(), 2)
    assert_eq(transport.remaining_inputs(), 0)
  })
}

///|
async test "dynamic transport failure archives configuration and prepares recovery" {
  @async.with_task_group(async fn(group) {
    let failed_script = stopped_execution_script(400)
    failed_script.push(@dap_testkit.ScriptedClosed)
    let failed_transport = @dap_testkit.ScriptedTransport::new(failed_script)
    let recovered_transport = @dap_testkit.ScriptedTransport::new([
      scripted_response(500, 1, "initialize", {}),
    ])
    let transports = [failed_transport, recovered_transport]
    let mut factory_index = 0
    let session = LldbDapSession::start_with_dispatcher_factory(
      group,
      () => {
        let transport = transports[factory_index]
        factory_index += 1
        @dap.DapDispatcher::from_transport(transport.as_transport())
      },
      preparation_timeout_ms=10000,
    )
    defer session.close()
    guard session.run("/tmp/dynamic-failure-program") is @moondbg.Stopped(_) else {
      fail("scripted execution should stop before the adapter failure")
    }
    let breakpoint = LogicalSourceBreakpoint::new(1, "/tmp/main.mbt", 4)
    let failed = try {
      session.install_source_breakpoint(breakpoint) |> ignore
      false
    } catch {
      LldbDapBackendError::AdapterFailure(_) => true
      _ => false
    }
    assert_true(failed)
    assert_true(session.state() is Ready)
    assert_true(session.execution is None)
    assert_true(session.preparation is Some(_))
    assert_eq(session.source_breakpoints.length(), 1)
    guard session.source_breakpoints() is [pending] else {
      fail("failed dynamic installation should retain one logical breakpoint")
    }
    assert_true(pending.status() is @moondbg.Pending)
  })
}

///|
async test "scripted launch failure is recovered by a fresh prepared execution" {
  @async.with_task_group(async fn(group) {
    let failed_transport = @dap_testkit.ScriptedTransport::new([
      scripted_response(200, 1, "initialize", {}),
      scripted_event(201, "initialized", {}),
      scripted_failed_response(202, 2, "launch", "launch rejected"),
      scripted_response(203, 3, "configurationDone", {}),
      scripted_event(204, "terminated", {}),
    ])
    let recovered_transport = @dap_testkit.ScriptedTransport::new([
      scripted_response(300, 1, "initialize", {}),
      scripted_event(301, "initialized", {}),
      scripted_response(302, 3, "configurationDone", {}),
      scripted_response(303, 2, "launch", {}),
      scripted_event(304, "stopped", { "reason": "breakpoint", "threadId": 1 }),
      scripted_response(305, 4, "stackTrace", scripted_stack_body(20, 4)),
    ])
    let transports = [failed_transport, recovered_transport]
    let mut factory_index = 0
    let lldb_session = LldbDapSession::start_with_dispatcher_factory(
      group,
      () => {
        let transport = transports[factory_index]
        factory_index += 1
        @dap.DapDispatcher::from_transport(transport.as_transport())
      },
      preparation_timeout_ms=10000,
    )
    let backend = LldbDapBackend::{
      session: lldb_session,
      imported_source_breakpoints: 0,
      imported_function_breakpoints: 0,
    }
    let session = @moondbg.DebugSession::new(
      "/tmp/moondbg-recovery-program", backend,
    )
    defer session.close()
    let failed = try {
      session.run() |> ignore
      false
    } catch {
      @moondbg.AdapterFailure(message) => message.contains("launch rejected")
      _ => false
    }
    assert_true(failed)
    assert_true(session.state() is @moondbg.Ready)
    assert_true(failed_transport.is_closed())
    guard session.run() is @moondbg.Stopped(snapshot) else {
      fail("replacement scripted execution should stop")
    }
    assert_eq(snapshot.line(), Some(4))
    assert_eq(factory_index, 2)
    assert_eq(failed_transport.remaining_inputs(), 0)
    assert_eq(recovered_transport.remaining_inputs(), 0)
  })
}

///|
async test "scripted preparation failure is recovered before the next run" {
  @async.with_task_group(async fn(group) {
    let failed_transport = @dap_testkit.ScriptedTransport::new([
      @dap_testkit.ScriptedFailure("initialize unavailable"),
    ])
    let recovered_transport = @dap_testkit.ScriptedTransport::new([
      scripted_response(400, 1, "initialize", {}),
      scripted_event(401, "initialized", {}),
      scripted_response(402, 3, "configurationDone", {}),
      scripted_response(403, 2, "launch", {}),
      scripted_event(404, "stopped", { "reason": "breakpoint", "threadId": 1 }),
      scripted_response(405, 4, "stackTrace", scripted_stack_body(30, 4)),
    ])
    let transports = [failed_transport, recovered_transport]
    let mut factory_index = 0
    let lldb_session = LldbDapSession::start_with_dispatcher_factory(
      group,
      () => {
        let transport = transports[factory_index]
        factory_index += 1
        @dap.DapDispatcher::from_transport(transport.as_transport())
      },
      preparation_timeout_ms=10000,
    )
    let backend = LldbDapBackend::{
      session: lldb_session,
      imported_source_breakpoints: 0,
      imported_function_breakpoints: 0,
    }
    let session = @moondbg.DebugSession::new(
      "/tmp/moondbg-preparation-recovery-program", backend,
    )
    defer session.close()
    let failed = try {
      session.run() |> ignore
      false
    } catch {
      @moondbg.AdapterFailure(message) =>
        message.contains("initialize unavailable")
      _ => false
    }
    assert_true(failed)
    assert_true(session.state() is @moondbg.Ready)
    assert_true(failed_transport.is_closed())
    guard session.run() is @moondbg.Stopped(snapshot) else {
      fail("replacement preparation should produce a stopped execution")
    }
    assert_eq(snapshot.line(), Some(4))
    assert_eq(factory_index, 2)
    assert_eq(failed_transport.remaining_inputs(), 0)
    assert_eq(recovered_transport.remaining_inputs(), 0)
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
  let first = LogicalSourceBreakpoint::new(1, "/tmp/main.mbt", 4)
  let second = LogicalSourceBreakpoint::new(2, "/tmp/main.mbt", 9)
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
  let first_snapshot = state.source_snapshot(first)
  assert_eq(first_snapshot.id(), 1)
  assert_eq(first_snapshot.requested_line(), 4)
  assert_eq(first_snapshot.actual_line(), Some(5))
  assert_true(first_snapshot.status() is @moondbg.Verified)
  let second_snapshot = state.source_snapshot(second)
  assert_eq(second_snapshot.id(), 2)
  assert_true(
    second_snapshot.status()
    is @moondbg.Rejected("no executable code at this location"),
  )
}

///|
test "a failed setBreakpoints response rejects the complete source set" {
  let first = LogicalSourceBreakpoint::new(1, "/tmp/main.mbt", 4)
  let second = LogicalSourceBreakpoint::new(2, "/tmp/main.mbt", 9)
  let state = ExecutionBreakpointState::new()
  apply_breakpoint_response(
    state,
    [first, second],
    test_failed_response(41, 5, "setBreakpoints", "source is unavailable"),
  )
  assert_true(
    state.source_snapshot(first).status()
    is @moondbg.Rejected("source is unavailable"),
  )
  assert_true(
    state.source_snapshot(second).status()
    is @moondbg.Rejected("source is unavailable"),
  )
}

///|
test "adapter breakpoint outcomes are isolated per execution" {
  let breakpoint = LogicalSourceBreakpoint::new(1, "/tmp/main.mbt", 4)
  let first = ExecutionBreakpointState::new()
  let second = ExecutionBreakpointState::new()
  first.verify(breakpoint.id, Some(5), Some(17))
  assert_true(first.source_snapshot(breakpoint).status() is @moondbg.Verified)
  assert_true(second.source_snapshot(breakpoint).status() is @moondbg.Pending)
  assert_eq(second.source_snapshot(breakpoint).actual_line(), None)
}

///|
test "setBreakpoints arguments replace the complete set for one source" {
  let first = LogicalSourceBreakpoint::new(1, "/tmp/main.mbt", 4)
  let second = LogicalSourceBreakpoint::new(2, "/tmp/other.mbt", 7)
  let third = LogicalSourceBreakpoint::new(3, "/tmp/main.mbt", 9)
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
test "setFunctionBreakpoints uses exact resolved physical names" {
  let local_breakpoint = LogicalFunctionBreakpoint::new(
    1, "helper", "_M0FP37example3app4main6helper",
  )
  let entry = LogicalFunctionBreakpoint::new(2, "main", "moonbit_main")
  let family = LogicalFunctionBreakpoint::family(
    3, "identity", "_M0FP37example3lib4util8identity",
  )
  let arguments = set_function_breakpoints_arguments([
    local_breakpoint, family, entry,
  ])
  guard arguments is { "breakpoints": Array(breakpoints), .. } else {
    fail("expected function breakpoint arguments")
  }
  assert_eq(breakpoints.length(), 2)
  assert_true(
    breakpoints[0] is { "name": String("_M0FP37example3app4main6helper"), .. },
  )
  assert_true(breakpoints[1] is { "name": String("moonbit_main"), .. })
}

///|
test "function breakpoint responses preserve stable ids and verification" {
  let local_breakpoint = LogicalFunctionBreakpoint::new(
    1, "helper", "_M0FP37example3app4main6helper",
  )
  let missing = LogicalFunctionBreakpoint::new(
    2, "absent", "_M0FP37example3app4main6absent",
  )
  let state = ExecutionBreakpointState::new()
  apply_function_breakpoint_response(
    state,
    [local_breakpoint, missing],
    test_response(50, 6, "setFunctionBreakpoints", {
      "breakpoints": [
        { "id": 31, "verified": true },
        { "verified": false, "message": "no locations found" },
      ],
    }),
  )
  let verified = state.function_snapshot(local_breakpoint)
  assert_eq(verified.id(), 1)
  assert_eq(verified.display_name(), "helper")
  assert_true(verified.status() is @moondbg.Verified)
  let rejected = state.function_snapshot(missing)
  assert_eq(rejected.id(), 2)
  assert_true(rejected.status() is @moondbg.Rejected("no locations found"))
}

///|
test "function family regex keeps the MoonBit specialization boundary" {
  let base = "_M0FP37example3lib4util8identity"
  assert_eq(
    function_family_regex(base),
    "^_M0FP37example3lib4util8identity($|G|H)",
  )
  assert_eq(
    function_family_breakpoint_command(base),
    "breakpoint set --func-regex '^_M0FP37example3lib4util8identity($|G|H)'",
  )
}

///|
test "LLDB breakpoint command results preserve id and location count" {
  assert_true(
    LldbCreatedBreakpoint::parse("Breakpoint 7: 2 locations.\n")
    is Some({ id: 7, location_count: 2, }),
  )
  assert_true(
    LldbCreatedBreakpoint::parse(
      "Breakpoint 8: where = main.exe`function at main.mbt:3, address = 0x10\n",
    )
    is Some({ id: 8, location_count: 1, }),
  )
  assert_true(
    LldbCreatedBreakpoint::parse(
      "Breakpoint 9: no locations (pending).\nWARNING: unresolved\n",
    )
    is Some({ id: 9, location_count: 0, }),
  )
  assert_true(LldbCreatedBreakpoint::parse("unexpected output") is None)
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
test "lldb-dap variable lookup selects the available shadowed local" {
  guard parse_variables({
      "variables": [
        {
          "evaluateName": "arr",
          "name": "arr @ x19",
          "type": "moonbit.array_i32",
          "value": "moonbit.array_i32 @ 0x2000",
          "variablesReference": 4,
        },
        {
          "evaluateName": "arr",
          "name": "arr @ ",
          "type": "moonbit.array_i32",
          "value": "<error: variable not available>",
          "variablesReference": 7,
        },
      ],
    })
    is Some(first_stop) &&
    first_stop.select_root_variable("arr") is DapVariableSelected(first_arr) else {
    fail("the first arr should be available before its call")
  }
  assert_eq(first_arr.name, "arr")
  assert_eq(first_arr.value, "moonbit.array_i32 @ 0x2000")
  assert_eq(first_arr.variables_reference, 4)
  guard parse_variables({
      "variables": [
        {
          "evaluateName": "arr",
          "name": "arr @ ",
          "type": "moonbit.array_i32",
          "value": "<error: variable not available>",
          "variablesReference": 4,
        },
        {
          "evaluateName": "arr",
          "name": "arr @ x19",
          "type": "moonbit.array_i32",
          "value": "moonbit.array_i32 @ 0x3000",
          "variablesReference": 7,
        },
      ],
    })
    is Some(second_stop) &&
    second_stop.select_root_variable("arr") is DapVariableSelected(second_arr) else {
    fail("the shadowing arr should be available at its call")
  }
  assert_eq(second_arr.name, "arr")
  assert_eq(second_arr.value, "moonbit.array_i32 @ 0x3000")
  assert_eq(second_arr.variables_reference, 7)
  guard parse_variables({
      "variables": [
        {
          "evaluateName": "arr",
          "name": "arr @ ",
          "type": "moonbit.array_i32",
          "value": "<error: variable not available>",
          "variablesReference": 4,
        },
      ],
    })
    is Some(unavailable_only) else {
    fail("the unavailable arr should be parsed")
  }
  assert_true(
    unavailable_only.select_root_variable("arr") is DapVariableUnavailable,
  )
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
      evaluate_name: None,
      memory_reference: None,
    },
  ]
  cache.reset(1)
  cache.store_scopes(1, scopes)
  cache.store_variables(1, 1, variables)
  let snapshot = variables[0].snapshot()
  cache.store_snapshot(1, "10:1:answer", snapshot)
  assert_true(cache.cached_scopes(1) is Some(_))
  assert_true(cache.cached_variables(1, 1) is Some(_))
  assert_eq(cache.cached_snapshot(1, "10:1:answer"), Some(snapshot))
  cache.reset(2)
  assert_true(cache.cached_scopes(1) is None)
  assert_true(cache.cached_variables(1, 1) is None)
  assert_true(cache.cached_snapshot(1, "10:1:answer") is None)
  assert_true(cache.cached_scopes(2) is None)
  cache.store_variables(1, 1, variables)
  cache.store_snapshot(1, "10:1:answer", snapshot)
  assert_true(cache.cached_variables(2, 1) is None)
  assert_true(cache.cached_snapshot(2, "10:1:answer") is None)
}

///|
async test "lldb-dap materializes nested structs and leaves other aggregates opaque" {
  @async.with_task_group(async fn(group) {
    let transport = @dap_testkit.ScriptedTransport::new(
      struct_variable_script(),
    )
    let lldb_session = LldbDapSession::start_with_dispatcher_factory(
      group,
      () => @dap.DapDispatcher::from_transport(transport.as_transport()),
      preparation_timeout_ms=10000,
    )
    let backend = LldbDapBackend::{
      session: lldb_session,
      imported_source_breakpoints: 0,
      imported_function_breakpoints: 0,
    }
    let session = @moondbg.DebugSession::new("/tmp/struct-program", backend)
    defer session.close()
    guard session.run() is @moondbg.Stopped(_) else {
      fail("scripted struct execution should stop")
    }
    guard session.find_variable(@moondbg.VariablePath::root("line1"))
      is @moondbg.VariableFound(line) &&
      line.content() is @moondbg.VariableStructure(line_structure) &&
      line_structure.children() is [start, end] &&
      start.content() is @moondbg.VariableStructure(start_structure) &&
      start_structure.children() is [start_x, start_y] &&
      end.content() is @moondbg.VariableStructure(end_structure) &&
      end_structure.children() is [end_x, end_y] else {
      fail("line1 should be materialized through both nested points")
    }
    assert_eq(start.name(), "start")
    assert_eq(start_x.value(), "1")
    assert_eq(start_y.value(), "2")
    assert_eq(end.name(), "end")
    assert_eq(end_x.value(), "4")
    assert_eq(end_y.value(), "6")
    guard session.find_variable(@moondbg.VariablePath::root("line1"))
      is @moondbg.VariableFound(cached) else {
      fail("line1 should remain available from the stop cache")
    }
    assert_eq(cached, line)
    guard session.find_variable(@moondbg.VariablePath::root("arr"))
      is @moondbg.VariableFound(array) else {
      fail("array root should remain printable")
    }
    assert_true(array.content() is @moondbg.VariableLeaf)
    assert_eq(array.value(), "moonbit.array_i32 @ 0x2000")
    guard session.find_variable(@moondbg.VariablePath::root("choice"))
      is @moondbg.VariableFound(choice) else {
      fail("boxed enum root should remain printable")
    }
    assert_true(choice.content() is @moondbg.VariableLeaf)
    assert_eq(choice.value(), "0x3000")
    assert_eq(transport.remaining_inputs(), 0)
    assert_eq(transport.sent_messages().filter_map(sent_command), [
      "initialize", "launch", "configurationDone", "stackTrace", "scopes", "variables",
      "variables", "variables", "variables", "variables",
    ])
  })
}

///|
async test "lldb-dap resolves field paths lazily with precise failures and epoch caches" {
  @async.with_task_group(async fn(group) {
    let transport = @dap_testkit.ScriptedTransport::new(
      field_path_variable_script(),
    )
    let lldb_session = LldbDapSession::start_with_dispatcher_factory(
      group,
      () => @dap.DapDispatcher::from_transport(transport.as_transport()),
      preparation_timeout_ms=10000,
    )
    let backend = LldbDapBackend::{
      session: lldb_session,
      imported_source_breakpoints: 0,
      imported_function_breakpoints: 0,
    }
    let session = @moondbg.DebugSession::new("/tmp/field-path-program", backend)
    defer session.close()
    guard session.run() is @moondbg.Stopped(_) else {
      fail("scripted field-path execution should stop")
    }
    let x_path = @moondbg.VariablePath::with_fields("line1", ["start", "x"])
    guard session.find_variable(x_path) is @moondbg.VariableFound(x) else {
      fail("line1.start.x should resolve to a scalar")
    }
    assert_eq(x.name(), "line1.start.x")
    assert_eq(x.type_name(), Some("double"))
    assert_eq(x.value(), "1")
    assert_true(x.content() is @moondbg.VariableLeaf)
    guard session.find_variable(x_path) is @moondbg.VariableFound(cached_x) else {
      fail("the repeated path should remain cached")
    }
    assert_eq(cached_x, x)
    guard session.find_variable(
        @moondbg.VariablePath::with_fields("line1", ["start"]),
      )
      is @moondbg.VariableFound(start) &&
      start.content() is @moondbg.VariableStructure(structure) &&
      structure.children() is [start_x, start_y] else {
      fail("a final struct field should retain structured materialization")
    }
    assert_eq(start.name(), "line1.start")
    assert_eq(start_x.name(), "x")
    assert_eq(start_y.name(), "y")
    guard session.find_variable(
        @moondbg.VariablePath::with_fields("line1", ["values"]),
      )
      is @moondbg.VariableFound(values) &&
      values.content() is @moondbg.VariableIndexedCollection(collection) &&
      collection.preview_elements() is [first, _, third] &&
      first.value() is Some(first_value) &&
      third.value() is Some(third_value) else {
      fail("a final FixedArray field should retain its bounded preview")
    }
    assert_eq(values.name(), "line1.values")
    assert_eq(collection.total_length(), 3)
    assert_eq(first_value.value(), "1")
    assert_eq(third_value.value(), "3")
    assert_true(
      session.find_variable(
        @moondbg.VariablePath::with_fields("line1", ["missing"]),
      )
      is @moondbg.VariableLookupFailed(
        @moondbg.VariableFieldNotFound("line1", "missing")
      ),
    )
    assert_true(
      session.find_variable(
        @moondbg.VariablePath::with_fields("line1", ["start", "x", "more"]),
      )
      is @moondbg.VariableLookupFailed(
        @moondbg.VariableFieldAccessOnNonStruct(
          "line1.start.x",
          "more",
          Some("double")
        )
      ),
    )
    assert_true(
      session.find_variable(
        @moondbg.VariablePath::with_fields("line1", ["end", "x"]),
      )
      is @moondbg.VariableLookupFailed(
        @moondbg.VariableUnavailable("line1.end")
      ),
    )
    assert_true(
      session.find_variable(@moondbg.VariablePath::root("missing"))
      is @moondbg.VariableLookupFailed(@moondbg.VariableRootNotFound("missing")),
    )
    guard session.next() is @moondbg.Stopped(_) else {
      fail("next should establish a new stop epoch")
    }
    guard session.find_variable(x_path) is @moondbg.VariableFound(next_x) else {
      fail("the same path should be resolved again after resume")
    }
    assert_eq(next_x, x)
    assert_eq(transport.remaining_inputs(), 0)
    assert_eq(transport.sent_messages().filter_map(sent_command), [
      "initialize", "launch", "configurationDone", "stackTrace", "scopes", "variables",
      "variables", "variables", "variables", "readMemory", "readMemory", "next",
      "stackTrace", "scopes", "variables", "variables", "variables",
    ])
  })
}

///|
async test "lldb-dap materializes bounded FixedArray previews and caches the snapshot" {
  @async.with_task_group(async fn(group) {
    let transport = @dap_testkit.ScriptedTransport::new(
      fixed_array_variable_script(),
    )
    let lldb_session = LldbDapSession::start_with_dispatcher_factory(
      group,
      () => @dap.DapDispatcher::from_transport(transport.as_transport()),
      preparation_timeout_ms=10000,
    )
    let backend = LldbDapBackend::{
      session: lldb_session,
      imported_source_breakpoints: 0,
      imported_function_breakpoints: 0,
    }
    let session = @moondbg.DebugSession::new(
      "/tmp/fixed-array-program", backend,
    )
    defer session.close()
    guard session.run() is @moondbg.Stopped(_) else {
      fail("scripted FixedArray execution should stop")
    }
    guard session.find_variable(@moondbg.VariablePath::root("short"))
      is @moondbg.VariableFound(short) &&
      short.content() is @moondbg.VariableIndexedCollection(short_collection) &&
      short_collection.preview_elements() is [first, second, third] &&
      first.value() is Some(first_value) &&
      third.value() is Some(third_value) else {
      fail("short FixedArray should be materialized completely")
    }
    assert_eq(short_collection.total_length(), 3)
    assert_true(short_collection.is_complete())
    assert_eq(first_value.value(), "1")
    assert_eq(second.index(), 1)
    assert_eq(third_value.value(), "3")
    guard session.find_variable(@moondbg.VariablePath::root("long"))
      is @moondbg.VariableFound(long) &&
      long.content() is @moondbg.VariableIndexedCollection(long_collection) &&
      long_collection.preview_elements() is [first, .., last] &&
      first.value() is Some(first_value) &&
      last.value() is Some(last_value) else {
      fail("long FixedArray should retain its bounded head and true tail")
    }
    assert_eq(long_collection.total_length(), 100)
    assert_eq(long_collection.preview_elements().length(), 16)
    assert_eq(long_collection.omitted_count(), 84)
    assert_eq(first.index(), 0)
    assert_eq(first_value.value(), "1")
    assert_eq(last.index(), 99)
    assert_eq(last_value.value(), "100")
    guard session.find_variable(@moondbg.VariablePath::root("long"))
      is @moondbg.VariableFound(cached) else {
      fail("same-stop FixedArray lookup should use its snapshot cache")
    }
    assert_eq(cached, long)
    guard session.find_variable(@moondbg.VariablePath::root("points"))
      is @moondbg.VariableFound(points) &&
      points.content() is @moondbg.VariableIndexedCollection(point_collection) &&
      point_collection.preview_elements() is [point_first, .., point_last] else {
      fail("opaque FixedArray should retain only bounded type placeholders")
    }
    assert_eq(point_collection.element_type_name(), "Point")
    assert_eq(point_collection.total_length(), 100)
    assert_eq(point_first.index(), 0)
    assert_true(point_first.value() is None)
    assert_eq(point_last.index(), 99)
    assert_true(point_last.value() is None)
    guard session.find_variable(@moondbg.VariablePath::root("empty"))
      is @moondbg.VariableFound(empty) &&
      empty.content() is @moondbg.VariableIndexedCollection(empty_collection) else {
      fail("null FixedArray payload should represent an empty collection")
    }
    assert_eq(empty_collection.total_length(), 0)
    assert_true(empty_collection.preview_elements() is [])
    assert_eq(transport.remaining_inputs(), 0)
    let sent = transport.sent_messages()
    assert_eq(sent.filter_map(sent_command), [
      "initialize", "launch", "configurationDone", "stackTrace", "scopes", "variables",
      "variables", "readMemory", "readMemory", "variables", "readMemory", "readMemory",
      "readMemory", "variables", "readMemory", "variables",
    ])
    assert_true(
      sent[1] is { "arguments": Object(launch_arguments), .. } &&
      launch_arguments.get("initCommands") is None,
    )
    assert_true(
      sent[7]
      is {
        "arguments": {
          "memoryReference": String("0x2000"),
          "offset": Number(-8, ..),
          "count": Number(8, ..),
          ..
        },
        ..
      },
    )
    assert_true(
      sent[12]
      is {
        "arguments": {
          "memoryReference": String("0x3000"),
          "offset": Number(396, ..),
          "count": Number(4, ..),
          ..
        },
        ..
      },
    )
  })
}

///|
async test "lldb-dap variable materialization obeys depth and node budgets" {
  @async.with_task_group(async fn(group) {
    let transport = @dap_testkit.ScriptedTransport::new(
      truncated_struct_script(),
    )
    let lldb_session = LldbDapSession::start_with_dispatcher_factory(
      group,
      () => @dap.DapDispatcher::from_transport(transport.as_transport()),
      preparation_timeout_ms=10000,
    )
    let backend = LldbDapBackend::{
      session: lldb_session,
      imported_source_breakpoints: 0,
      imported_function_breakpoints: 0,
    }
    let session = @moondbg.DebugSession::new("/tmp/truncated-program", backend)
    defer session.close()
    session.run() |> ignore
    guard backend.session.execution is Some(execution) &&
      execution.machine.current_stop_epoch() is Some(epoch) else {
      fail("scripted execution should retain one stop epoch")
    }
    let line = DapVariable::{
      name: "line1",
      value: "0x1000",
      type_name: Some("example/geometry/Line &"),
      variables_reference: 101,
      evaluate_name: None,
      memory_reference: None,
    }
    let snapshot = execution.materialize_variable_with_limits(epoch, line, 8, 2)
    guard snapshot.content() is @moondbg.VariableStructure(line_structure) &&
      line_structure.is_truncated() &&
      line_structure.children() is [start] &&
      start.content() is @moondbg.VariableStructure(start_structure) &&
      start_structure.is_truncated() &&
      start_structure.children() is [] else {
      fail(
        "node budget should preserve materialized children and mark truncation",
      )
    }
    assert_eq(start.name(), "start")
    let depth_limited = execution.materialize_variable_with_limits(
      epoch, line, 0, 10,
    )
    assert_true(
      depth_limited.content() is @moondbg.VariableStructure(structure) &&
      structure.is_truncated() &&
      structure.children() is [],
    )
    assert_eq(transport.remaining_inputs(), 0)
    assert_eq(transport.sent_messages().filter_map(sent_command), [
      "initialize", "launch", "configurationDone", "stackTrace", "variables",
    ])
  })
}

///|
async test "lldb-dap variable materialization truncates recursive references" {
  @async.with_task_group(async fn(group) {
    let transport = @dap_testkit.ScriptedTransport::new(cyclic_struct_script())
    let lldb_session = LldbDapSession::start_with_dispatcher_factory(
      group,
      () => @dap.DapDispatcher::from_transport(transport.as_transport()),
      preparation_timeout_ms=10000,
    )
    let backend = LldbDapBackend::{
      session: lldb_session,
      imported_source_breakpoints: 0,
      imported_function_breakpoints: 0,
    }
    let session = @moondbg.DebugSession::new("/tmp/cyclic-program", backend)
    defer session.close()
    session.run() |> ignore
    guard backend.session.execution is Some(execution) &&
      execution.machine.current_stop_epoch() is Some(epoch) else {
      fail("scripted execution should retain one stop epoch")
    }
    let node = DapVariable::{
      name: "node",
      value: "0x1000",
      type_name: Some("example/Node &"),
      variables_reference: 101,
      evaluate_name: None,
      memory_reference: None,
    }
    let snapshot = execution.materialize_variable_with_limits(
      epoch, node, 8, 10,
    )
    guard snapshot.content() is @moondbg.VariableStructure(node_structure) &&
      !node_structure.is_truncated() &&
      node_structure.children() is [next] &&
      next.content() is @moondbg.VariableStructure(next_structure) &&
      next_structure.is_truncated() &&
      next_structure.children() is [] else {
      fail("recursive reference should stop at the active DAP reference")
    }
    assert_eq(transport.remaining_inputs(), 0)
    assert_eq(transport.sent_messages().filter_map(sent_command), [
      "initialize", "launch", "configurationDone", "stackTrace", "variables",
    ])
  })
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
