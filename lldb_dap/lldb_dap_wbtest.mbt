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
fn scripted_stack_body_with_runtime(frame_id : Int, line : Int) -> Json {
  {
    "stackFrames": [
      {
        "id": frame_id - 1,
        "name": "runtime_entry",
        "source": { "path": "/tmp/runtime.c" },
        "line": 20,
        "column": 1,
      },
      {
        "id": frame_id,
        "name": "main.inspect_value",
        "source": { "path": "/tmp/main.mbt" },
        "line": line,
        "column": 3,
      },
    ],
    "totalFrames": 2,
  }
}

///|
fn scripted_user_frame(id : Int, physical_index : Int) -> Json {
  {
    "id": id,
    "name": "user.frame.\{physical_index}",
    "source": { "path": "/tmp/frame_\{physical_index}.mbt" },
    "line": physical_index + 1,
    "column": 1,
  }
}

///|
fn scripted_native_frame(id : Int, physical_index : Int) -> Json {
  {
    "id": id,
    "name": "native.frame.\{physical_index}",
    "source": { "path": "/tmp/frame_\{physical_index}.c" },
    "line": physical_index + 1,
    "column": 1,
  }
}

///|
fn scripted_unknown_frame(id : Int, physical_index : Int) -> Json {
  {
    "id": id,
    "name": "unknown.frame.\{physical_index}",
    "line": physical_index + 1,
    "column": 1,
  }
}

///|
fn scripted_stack_page(frames : Array[Json], total_frames : Int) -> Json {
  { "stackFrames": frames, "totalFrames": total_frames }
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
    scripted_response(
      108,
      5,
      "stackTrace",
      scripted_stack_body_with_runtime(10, 4),
    ),
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
    scripted_response(207, 4, "evaluate", { "result": "details unavailable" }),
    scripted_response(203, 5, "configurationDone", {}),
    scripted_response(204, 2, "launch", {}),
    scripted_event(205, "stopped", {
      "reason": "breakpoint",
      "threadId": 1,
      "hitBreakpointIds": [7],
    }),
    scripted_response(206, 6, "stackTrace", scripted_stack_body(20, 8)),
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
    scripted_response(313, 10, "evaluate", { "result": "details unavailable" }),
    scripted_response(311, 11, "evaluate", {
      "result": "Breakpoint 58: no locations (pending).\n",
      "variablesReference": 0,
    }),
    scripted_response(314, 12, "evaluate", {
      "result": "58: name = missing, locations = 0",
    }),
    scripted_response(312, 13, "setBreakpoints", {
      "breakpoints": [{ "verified": false, "message": "source is unavailable" }],
    }),
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
      "supportsReadMemoryRequest": true,
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
          "name": "opaque",
          "type": "example/OpaqueChild",
          "value": "opaque",
          "variablesReference": 0,
        },
      ],
    }),
    scripted_response(1312, 11, "variables", {
      "variables": [
        {
          "name": "__moonbit_enum_marker",
          "type": "moonbit.enum",
          "value": "0",
          "variablesReference": 0,
        },
        {
          "name": "None_0",
          "type": "example/geometry/Choice.None *",
          "value": "0x0000000000003000",
          "variablesReference": 113,
        },
        {
          "name": "Some_1",
          "type": "example/geometry/Choice.Some *",
          "value": "0x0000000000003000",
          "memoryReference": "0xdead3000",
          "variablesReference": 114,
        },
      ],
    }),
    scripted_response(1313, 12, "readMemory", { "data": "AQAAQA==" }),
    scripted_response(1314, 13, "variables", {
      "variables": [
        { "name": ".0", "type": "int", "value": "9", "variablesReference": 0 },
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
          "memoryReference": "0xdead3300",
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
          "memoryReference": "0xdead2000",
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
          "memoryReference": "0xdead3000",
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
          "memoryReference": "0xdead4000",
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
fn array_double_variable_script() -> Array[@dap_testkit.ScriptedInput] {
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
        "name": "arr",
        "type": "moonbitlang/core/builtin/Array[Double] &",
        "value": "0x5000",
        "variablesReference": 301,
      },
      {
        "name": "empty",
        "type": "moonbitlang/core/builtin/Array[Double] &",
        "value": "0x7000",
        "variablesReference": 302,
      },
      {
        "name": "invalid",
        "type": "moonbitlang/core/builtin/Array[Double] &",
        "value": "0x8000",
        "variablesReference": 303,
      },
    ],
  }
  [
    scripted_response(1800, 1, "initialize", {
      "supportsConfigurationDoneRequest": true,
      "supportsReadMemoryRequest": true,
      "supportsSteppingGranularity": true,
    }),
    scripted_event(1801, "initialized", {}),
    scripted_response(1802, 3, "configurationDone", {}),
    scripted_response(1803, 2, "launch", {}),
    scripted_event(1804, "stopped", { "reason": "breakpoint", "threadId": 1 }),
    scripted_response(1805, 4, "stackTrace", scripted_stack_body(120, 20)),
    scripted_response(1806, 5, "scopes", scopes),
    scripted_response(1807, 6, "variables", roots),
    scripted_response(1808, 7, "variables", {
      "variables": [
        {
          "name": "buf",
          "type": "moonbit.array_f64",
          "value": "moonbit.array_f64 @ 0x5000",
          "variablesReference": 311,
        },
        { "name": "len", "type": "int", "value": "10", "variablesReference": 0 },
      ],
    }),
    scripted_response(1809, 8, "variables", {
      "variables": [
        {
          "name": "body",
          "type": "double *",
          "value": "0x5000",
          "evaluateName": "arr.buf.body",
          "memoryReference": "0xdead5000",
          "variablesReference": 0,
        },
      ],
    }),
    scripted_response(1810, 9, "readMemory", { "data": "AAAAAAoAAAA=" }),
    scripted_response(1811, 10, "readMemory", {
      "data": "AAAAAAAA8D8AAAAAAAAAQAAAAAAAAAhAAAAAAAAAEEAAAAAAAAAUQAAAAAAAABhAAAAAAAAAHEAAAAAAAAAgQAAAAAAAACJAAAAAAAAAJEA=",
    }),
    scripted_response(1812, 11, "variables", {
      "variables": [
        {
          "name": "buf",
          "type": "moonbit.array_f64",
          "value": "moonbit.array_f64 @ 0x0",
          "variablesReference": 312,
        },
        { "name": "len", "type": "int", "value": "0", "variablesReference": 0 },
      ],
    }),
    scripted_response(1813, 12, "variables", {
      "variables": [
        {
          "name": "body",
          "type": "double *",
          "value": "0x0000000000000000",
          "memoryReference": "0xdead7000",
          "variablesReference": 0,
        },
      ],
    }),
    scripted_event(1814, "stopped", { "reason": "step", "threadId": 1 }),
    scripted_response(1815, 13, "next", {}),
    scripted_response(1816, 14, "stackTrace", scripted_stack_body(121, 21)),
    scripted_response(1817, 15, "scopes", scopes),
    scripted_response(1818, 16, "variables", roots),
    scripted_response(1819, 17, "variables", {
      "variables": [
        {
          "name": "buf",
          "type": "moonbit.array_f64",
          "value": "moonbit.array_f64 @ 0x6000",
          "variablesReference": 321,
        },
        {
          "name": "len",
          "type": "int",
          "value": "100",
          "variablesReference": 0,
        },
      ],
    }),
    scripted_response(1820, 18, "variables", {
      "variables": [
        {
          "name": "body",
          "type": "double *",
          "value": "0x6000",
          "evaluateName": "arr.buf.body",
          "memoryReference": "0xdead6000",
          "variablesReference": 0,
        },
      ],
    }),
    scripted_response(1821, 19, "readMemory", { "data": "AAAAAIAAAAA=" }),
    scripted_response(1822, 20, "readMemory", {
      "data": "AAAAAAAA8D8AAAAAAAAAQAAAAAAAAAhAAAAAAAAAEEAAAAAAAAAUQAAAAAAAABhAAAAAAAAAHEAAAAAAAAAgQAAAAAAAACJAAAAAAAAAJEAAAAAAAAAmQAAAAAAAAChAAAAAAAAAKkAAAAAAAAAsQAAAAAAAAC5A",
    }),
    scripted_response(1823, 21, "readMemory", { "data": "AAAAAAAAWUA=" }),
    scripted_response(1824, 22, "variables", {
      "variables": [
        {
          "name": "buf",
          "type": "moonbit.array_f64",
          "value": "moonbit.array_f64 @ 0x8000",
          "variablesReference": 322,
        },
        {
          "name": "len",
          "type": "int",
          "value": "129",
          "variablesReference": 0,
        },
      ],
    }),
    scripted_response(1825, 23, "variables", {
      "variables": [
        {
          "name": "body",
          "type": "double *",
          "value": "0x8000",
          "memoryReference": "0xdead8000",
          "variablesReference": 0,
        },
      ],
    }),
    scripted_response(1826, 24, "readMemory", { "data": "AAAAAIAAAAA=" }),
  ]
}

///|
fn indexed_path_variable_script() -> Array[@dap_testkit.ScriptedInput] {
  let scopes : Json = {
    "scopes": [
      {
        "name": "Locals",
        "presentationHint": "locals",
        "variablesReference": 500,
      },
    ],
  }
  let roots : Json = {
    "variables": [
      {
        "name": "arr",
        "type": "moonbitlang/core/builtin/Array[example/geometry/Point] &",
        "value": "0x5000",
        "variablesReference": 501,
      },
      {
        "name": "lines",
        "type": "moonbitlang/core/builtin/Array[example/geometry/Line] &",
        "value": "0x6000",
        "variablesReference": 502,
      },
      {
        "name": "ints",
        "type": "FixedArray[Int]",
        "value": "FixedArray[Int] @ 0x7000",
        "variablesReference": 503,
      },
      {
        "name": "point",
        "type": "example/geometry/Point &",
        "value": "0x8000",
        "variablesReference": 504,
      },
      {
        "name": "box",
        "type": "example/geometry/PointBox &",
        "value": "0x9000",
        "variablesReference": 505,
      },
      {
        "name": "empty",
        "type": "moonbitlang/core/builtin/Array[example/geometry/Point] &",
        "value": "0xa000",
        "variablesReference": 506,
      },
    ],
  }
  let arr_children : Json = {
    "variables": [
      {
        "name": "buf",
        "type": "FixedArray[UnsafeMaybeUninit[Point]]",
        "value": "FixedArray @ 0x1000",
        "variablesReference": 511,
      },
      { "name": "len", "type": "int", "value": "3", "variablesReference": 0 },
    ],
  }
  let arr_buffer : Json = {
    "variables": [
      {
        "name": "body",
        "type": "example/geometry/Point **",
        "value": "0x1000",
        "evaluateName": "adapter.arr.body",
        "memoryReference": "0xdead1000",
        "variablesReference": 0,
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
    scripted_response(2000, 1, "initialize", {
      "supportsConfigurationDoneRequest": true,
      "supportsReadMemoryRequest": true,
      "supportsSteppingGranularity": true,
    }),
    scripted_event(2001, "initialized", {}),
    scripted_response(2002, 3, "configurationDone", {}),
    scripted_response(2003, 2, "launch", {}),
    scripted_event(2004, "stopped", { "reason": "breakpoint", "threadId": 1 }),
    scripted_response(2005, 4, "stackTrace", scripted_stack_body(140, 25)),
    scripted_response(2006, 5, "scopes", scopes),
    scripted_response(2007, 6, "variables", roots),
    scripted_response(2008, 7, "variables", arr_children),
    scripted_response(2009, 8, "variables", arr_buffer),
    scripted_response(2010, 9, "readMemory", { "data": "AAAAAAMAAAA=" }),
    scripted_response(2011, 10, "evaluate", {
      "result": "0x1010",
      "type": "example/geometry/Point *",
      "variablesReference": 520,
      "memoryReference": "0x1010",
    }),
    scripted_response(2012, 11, "variables", point_fields),
    scripted_response(2013, 12, "variables", {
      "variables": [
        {
          "name": "buf",
          "type": "FixedArray[UnsafeMaybeUninit[Line]]",
          "value": "FixedArray @ 0x2000",
          "variablesReference": 521,
        },
        { "name": "len", "type": "int", "value": "1", "variablesReference": 0 },
      ],
    }),
    scripted_response(2014, 13, "variables", {
      "variables": [
        {
          "name": "body",
          "type": "example/geometry/Line **",
          "value": "0x2000",
          "evaluateName": "adapter.lines.body",
          "memoryReference": "0xdead2000",
          "variablesReference": 0,
        },
      ],
    }),
    scripted_response(2015, 14, "readMemory", { "data": "AAAAAAEAAAA=" }),
    scripted_response(2016, 15, "evaluate", {
      "result": "0x2020",
      "type": "example/geometry/Line *",
      "variablesReference": 530,
      "memoryReference": "0x2020",
    }),
    scripted_response(2017, 16, "variables", {
      "variables": [
        {
          "name": "start",
          "type": "example/geometry/Point &",
          "value": "0x2030",
          "variablesReference": 531,
        },
      ],
    }),
    scripted_response(2018, 17, "variables", point_fields),
    scripted_response(2019, 18, "variables", {
      "variables": [
        {
          "name": "points",
          "type": "moonbitlang/core/builtin/Array[example/geometry/Point] &",
          "value": "0x3000",
          "variablesReference": 541,
        },
      ],
    }),
    scripted_response(2020, 19, "variables", {
      "variables": [
        {
          "name": "buf",
          "type": "FixedArray[UnsafeMaybeUninit[Point]]",
          "value": "FixedArray @ 0x3000",
          "variablesReference": 542,
        },
        { "name": "len", "type": "int", "value": "1", "variablesReference": 0 },
      ],
    }),
    scripted_response(2021, 20, "variables", {
      "variables": [
        {
          "name": "body",
          "type": "example/geometry/Point **",
          "value": "0x3000",
          "evaluateName": "trusted.box.body",
          "memoryReference": "0xdead3000",
          "variablesReference": 0,
        },
      ],
    }),
    scripted_response(2022, 21, "readMemory", { "data": "AAAAAAEAAAA=" }),
    scripted_response(2023, 22, "evaluate", {
      "result": "0x3030",
      "type": "example/geometry/Point *",
      "variablesReference": 543,
      "memoryReference": "0x3030",
    }),
    scripted_response(2024, 23, "variables", point_fields),
    scripted_response(2025, 24, "variables", {
      "variables": [
        {
          "name": "body",
          "type": "int *",
          "value": "0x4000",
          "evaluateName": "trusted.ints.body",
          "memoryReference": "0xdead4000",
          "variablesReference": 0,
        },
      ],
    }),
    scripted_response(2026, 25, "readMemory", { "data": "AAAAAAMAAAA=" }),
    scripted_response(2027, 26, "evaluate", {
      "result": "30",
      "type": "int",
      "variablesReference": 0,
      "memoryReference": "0x4008",
    }),
    scripted_response(2028, 27, "readMemory", { "data": "AAAAAAMAAAA=" }),
    scripted_response(2029, 28, "variables", {
      "variables": [
        {
          "name": "buf",
          "type": "FixedArray[UnsafeMaybeUninit[Point]]",
          "value": "FixedArray @ 0x0",
          "variablesReference": 551,
        },
        { "name": "len", "type": "int", "value": "0", "variablesReference": 0 },
      ],
    }),
    scripted_response(2030, 29, "variables", {
      "variables": [
        {
          "name": "body",
          "type": "example/geometry/Point **",
          "value": "0x0000000000000000",
          "variablesReference": 0,
        },
      ],
    }),
    scripted_event(2031, "stopped", { "reason": "step", "threadId": 1 }),
    scripted_response(2032, 30, "next", {}),
    scripted_response(2033, 31, "stackTrace", scripted_stack_body(141, 26)),
    scripted_response(2034, 32, "scopes", scopes),
    scripted_response(2035, 33, "variables", roots),
    scripted_response(2036, 34, "variables", arr_children),
    scripted_response(2037, 35, "variables", arr_buffer),
    scripted_response(2038, 36, "readMemory", { "data": "AAAAAAMAAAA=" }),
    scripted_response(2039, 37, "evaluate", {
      "result": "0x1010",
      "type": "example/geometry/Point *",
      "variablesReference": 620,
      "memoryReference": "0x1010",
    }),
    scripted_response(2040, 38, "variables", point_fields),
  ]
}

///|
priv enum IndexedPathFailureMode {
  MissingEvaluateName
  FailedEvaluate
  MalformedEvaluate
  MalformedEvaluateMemoryReference
  UnavailableEvaluate
  UnexpandableEvaluate
}

///|
fn indexed_path_failure_script(
  mode : IndexedPathFailureMode,
) -> Array[@dap_testkit.ScriptedInput] {
  let script = [
    scripted_response(2100, 1, "initialize", {
      "supportsConfigurationDoneRequest": true,
      "supportsReadMemoryRequest": true,
    }),
    scripted_event(2101, "initialized", {}),
    scripted_response(2102, 3, "configurationDone", {}),
    scripted_response(2103, 2, "launch", {}),
    scripted_event(2104, "stopped", { "reason": "breakpoint", "threadId": 1 }),
    scripted_response(2105, 4, "stackTrace", scripted_stack_body(150, 25)),
    scripted_response(2106, 5, "scopes", {
      "scopes": [
        {
          "name": "Locals",
          "presentationHint": "locals",
          "variablesReference": 700,
        },
      ],
    }),
    scripted_response(2107, 6, "variables", {
      "variables": [
        {
          "name": "arr",
          "type": "moonbitlang/core/builtin/Array[example/Point] &",
          "value": "0x5000",
          "variablesReference": 701,
        },
      ],
    }),
    scripted_response(2108, 7, "variables", {
      "variables": [
        {
          "name": "buf",
          "type": "FixedArray[UnsafeMaybeUninit[Point]]",
          "value": "FixedArray @ 0x5000",
          "variablesReference": 702,
        },
        { "name": "len", "type": "int", "value": "1", "variablesReference": 0 },
      ],
    }),
  ]
  let body : Json = match mode {
    MissingEvaluateName =>
      {
        "variables": [
          {
            "name": "body",
            "type": "example/Point **",
            "value": "0x5000",
            "variablesReference": 0,
          },
        ],
      }
    _ =>
      {
        "variables": [
          {
            "name": "body",
            "type": "example/Point **",
            "value": "0x5000",
            "evaluateName": "adapter.failure.body",
            "variablesReference": 0,
          },
        ],
      }
  }
  script.push(scripted_response(2109, 8, "variables", body))
  script.push(
    scripted_response(2110, 9, "readMemory", { "data": "AAAAAAEAAAA=" }),
  )
  match mode {
    MissingEvaluateName => ()
    FailedEvaluate =>
      script.push(
        scripted_failed_response(
          2111, 10, "evaluate", "expression is unavailable",
        ),
      )
    MalformedEvaluate =>
      script.push(
        scripted_response(2111, 10, "evaluate", {
          "result": "0x5010",
          "variablesReference": 710,
        }),
      )
    MalformedEvaluateMemoryReference =>
      script.push(
        scripted_response(2111, 10, "evaluate", {
          "result": "0x5010",
          "type": "example/Point *",
          "variablesReference": 710,
          "memoryReference": 42,
        }),
      )
    UnavailableEvaluate =>
      script.push(
        scripted_response(2111, 10, "evaluate", {
          "result": "<variable not available>",
          "type": "example/Point *",
          "variablesReference": 0,
        }),
      )
    UnexpandableEvaluate =>
      script.push(
        scripted_response(2111, 10, "evaluate", {
          "result": "0x5010",
          "type": "example/Point *",
          "variablesReference": 0,
        }),
      )
  }
  script
}

///|
fn boxed_enum_variable_script() -> Array[@dap_testkit.ScriptedInput] {
  [
    scripted_response(1900, 1, "initialize", {
      "supportsConfigurationDoneRequest": true,
      "supportsReadMemoryRequest": true,
    }),
    scripted_event(1901, "initialized", {}),
    scripted_response(1902, 3, "configurationDone", {}),
    scripted_response(1903, 2, "launch", {}),
    scripted_event(1904, "stopped", { "reason": "breakpoint", "threadId": 1 }),
    scripted_response(1905, 4, "stackTrace", scripted_stack_body(130, 34)),
    scripted_response(1906, 5, "scopes", {
      "scopes": [
        {
          "name": "Locals",
          "presentationHint": "locals",
          "variablesReference": 400,
        },
      ],
    }),
    scripted_response(1907, 6, "variables", {
      "variables": [
        {
          "name": "empty",
          "type": "example/E",
          "value": "example/E @ 0x1000",
          "variablesReference": 401,
        },
        {
          "name": "scalar",
          "type": "example/E",
          "value": "example/E @ 0x2000",
          "variablesReference": 402,
        },
        {
          "name": "list",
          "type": "example/List",
          "value": "example/List @ 0x3000",
          "variablesReference": 403,
        },
        {
          "name": "pair",
          "type": "example/E",
          "value": "example/E @ 0x4000",
          "variablesReference": 404,
        },
        {
          "name": "unknown",
          "type": "example/Opaque",
          "value": "opaque",
          "variablesReference": 405,
        },
      ],
    }),
    scripted_response(1908, 7, "variables", {
      "variables": [
        {
          "name": "__moonbit_enum_marker",
          "type": "moonbit.enum",
          "value": "moonbit.enum @ 0x1000",
          "variablesReference": 499,
        },
        {
          "name": "Empty_0",
          "type": "example/E.Empty *",
          "value": "0x0000000000001000",
          "memoryReference": "0xdead1000",
          "variablesReference": 411,
        },
      ],
    }),
    scripted_response(1909, 8, "readMemory", { "data": "AAAAQA==" }),
    scripted_response(1910, 9, "variables", { "variables": [] }),
    scripted_response(1911, 10, "variables", {
      "variables": [
        {
          "name": "__moonbit_enum_marker",
          "type": "moonbit.enum",
          "value": "moonbit.enum @ 0x2000",
          "variablesReference": 0,
        },
        {
          "name": "A_0",
          "type": "example/E.A *",
          "value": "0x0000000000002000",
          "variablesReference": 421,
        },
        {
          "name": "B_1",
          "type": "example/E.B *",
          "value": "0x0000000000002000",
          "memoryReference": "0xdead2000",
          "variablesReference": 422,
        },
      ],
    }),
    scripted_response(1912, 11, "readMemory", { "data": "AQAAQA==" }),
    scripted_response(1913, 12, "variables", {
      "variables": [
        { "name": ".0", "type": "int", "value": "7", "variablesReference": 0 },
      ],
    }),
    scripted_response(1914, 13, "variables", {
      "variables": [
        {
          "name": "__moonbit_enum_marker",
          "type": "moonbit.enum",
          "value": "moonbit.enum @ 0x3000",
          "variablesReference": 0,
        },
        {
          "name": "Empty_0",
          "type": "example/List.Empty *",
          "value": "0x0000000000003000",
          "variablesReference": 431,
        },
        {
          "name": "Cons_1",
          "type": "example/List.Cons *",
          "value": "0x0000000000003000",
          "memoryReference": "0xdead3000",
          "variablesReference": 432,
        },
      ],
    }),
    scripted_response(1915, 14, "readMemory", { "data": "AQAAQA==" }),
    scripted_response(1916, 15, "variables", {
      "variables": [
        { "name": ".0", "type": "int", "value": "3", "variablesReference": 0 },
        {
          "name": ".1",
          "type": "example/List",
          "value": "example/List @ 0x3010",
          "memoryReference": "0xdead3010",
          "variablesReference": 439,
        },
      ],
    }),
    scripted_response(1917, 16, "variables", {
      "variables": [
        {
          "name": "__moonbit_enum_marker",
          "type": "moonbit.enum",
          "value": "moonbit.enum @ 0x4000",
          "variablesReference": 0,
        },
        {
          "name": "A_0",
          "type": "example/E.A *",
          "value": "0x0000000000004000",
          "variablesReference": 441,
        },
        {
          "name": "B_1",
          "type": "example/E.B *",
          "value": "0x0000000000004000",
          "variablesReference": 442,
        },
        {
          "name": "C_2",
          "type": "example/E.C *",
          "value": "0x0000000000004000",
          "memoryReference": "0xdead4000",
          "variablesReference": 443,
        },
      ],
    }),
    scripted_response(1918, 17, "readMemory", { "data": "AgAAQA==" }),
    scripted_response(1919, 18, "variables", {
      "variables": [
        { "name": ".1", "type": "int", "value": "2", "variablesReference": 0 },
        {
          "name": ".0",
          "type": "double",
          "value": "1.5",
          "variablesReference": 0,
        },
      ],
    }),
    scripted_response(1920, 19, "variables", {
      "variables": [
        {
          "name": "opaque",
          "type": "example/OpaqueChild",
          "value": "opaque",
          "variablesReference": 0,
        },
      ],
    }),
  ]
}

///|
fn malformed_boxed_enum_script() -> Array[@dap_testkit.ScriptedInput] {
  [
    scripted_response(1950, 1, "initialize", {
      "supportsConfigurationDoneRequest": true,
      "supportsReadMemoryRequest": true,
    }),
    scripted_event(1951, "initialized", {}),
    scripted_response(1952, 3, "configurationDone", {}),
    scripted_response(1953, 2, "launch", {}),
    scripted_event(1954, "stopped", { "reason": "breakpoint", "threadId": 1 }),
    scripted_response(1955, 4, "stackTrace", scripted_stack_body(140, 34)),
    scripted_response(1956, 5, "scopes", {
      "scopes": [
        {
          "name": "Locals",
          "presentationHint": "locals",
          "variablesReference": 500,
        },
      ],
    }),
    scripted_response(1957, 6, "variables", {
      "variables": [
        {
          "name": "unknown_tag",
          "type": "example/E",
          "value": "example/E @ 0x5000",
          "variablesReference": 501,
        },
        {
          "name": "duplicate_tag",
          "type": "example/E",
          "value": "example/E @ 0x5100",
          "variablesReference": 502,
        },
        {
          "name": "illegal_tag",
          "type": "example/E",
          "value": "example/E @ 0x5200",
          "variablesReference": 503,
        },
        {
          "name": "bad_pointer",
          "type": "example/E",
          "value": "example/E @ 0x5300",
          "variablesReference": 504,
        },
        {
          "name": "duplicate_marker",
          "type": "example/E",
          "value": "example/E @ 0x5400",
          "variablesReference": 505,
        },
        {
          "name": "unreadable",
          "type": "example/E",
          "value": "example/E @ 0x5500",
          "variablesReference": 506,
        },
      ],
    }),
    scripted_response(1958, 7, "variables", {
      "variables": [
        {
          "name": "__moonbit_enum_marker",
          "type": "moonbit.enum",
          "value": "marker",
          "variablesReference": 0,
        },
        {
          "name": "A_0",
          "type": "example/E.A *",
          "value": "0x5000",
          "variablesReference": 511,
        },
      ],
    }),
    scripted_response(1959, 8, "readMemory", { "data": "AQAAQA==" }),
    scripted_response(1960, 9, "variables", {
      "variables": [
        {
          "name": "__moonbit_enum_marker",
          "type": "moonbit.enum",
          "value": "marker",
          "variablesReference": 0,
        },
        {
          "name": "A_0",
          "type": "example/E.A *",
          "value": "0x5100",
          "variablesReference": 521,
        },
        {
          "name": "B_0",
          "type": "example/E.B *",
          "value": "0x5100",
          "variablesReference": 522,
        },
      ],
    }),
    scripted_response(1961, 10, "variables", {
      "variables": [
        {
          "name": "__moonbit_enum_marker",
          "type": "moonbit.enum",
          "value": "marker",
          "variablesReference": 0,
        },
        {
          "name": "A_tag",
          "type": "example/E.A *",
          "value": "0x5200",
          "variablesReference": 531,
        },
      ],
    }),
    scripted_response(1962, 11, "variables", {
      "variables": [
        {
          "name": "__moonbit_enum_marker",
          "type": "moonbit.enum",
          "value": "marker",
          "variablesReference": 0,
        },
        {
          "name": "A_0",
          "type": "example/E.A *",
          "value": "(example/E.A *) 0x5300",
          "memoryReference": "0x5300",
          "variablesReference": 541,
        },
      ],
    }),
    scripted_response(1963, 12, "variables", {
      "variables": [
        {
          "name": "__moonbit_enum_marker",
          "type": "moonbit.enum",
          "value": "marker",
          "variablesReference": 0,
        },
        {
          "name": "__moonbit_enum_marker",
          "type": "moonbit.enum",
          "value": "marker",
          "variablesReference": 0,
        },
        {
          "name": "A_0",
          "type": "example/E.A *",
          "value": "0x5400",
          "variablesReference": 551,
        },
      ],
    }),
    scripted_response(1964, 13, "variables", {
      "variables": [
        {
          "name": "__moonbit_enum_marker",
          "type": "moonbit.enum",
          "value": "marker",
          "variablesReference": 0,
        },
        {
          "name": "A_0",
          "type": "example/E.A *",
          "value": "0x5500",
          "variablesReference": 561,
        },
      ],
    }),
    scripted_response(1965, 14, "readMemory", {
      "data": "",
      "unreadableBytes": 4,
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
async test "P3 scripted stack pagination keeps a cumulative physical prefix" {
  @async.with_task_group(async fn(_group) {
    let transport = @dap_testkit.ScriptedTransport::new([
      scripted_response(4000, 1, "initialize", {}),
      scripted_response(
        4001,
        2,
        "stackTrace",
        scripted_stack_page(
          [
            scripted_native_frame(100, 0),
            scripted_unknown_frame(101, 1),
            scripted_user_frame(102, 2),
          ],
          99,
        ),
      ),
      scripted_response(
        4002,
        3,
        "stackTrace",
        scripted_stack_page(
          [
            scripted_user_frame(103, 3),
            scripted_user_frame(104, 4),
            scripted_user_frame(105, 5),
          ],
          6,
        ),
      ),
      scripted_response(
        4003,
        4,
        "stackTrace",
        scripted_stack_page([scripted_user_frame(106, 6)], 7),
      ),
    ])
    let execution = DebugExecution::prepare_with_dispatcher(
      @dap.DapDispatcher::from_transport(transport.as_transport()),
    )
    defer execution.close()
    execution.machine.begin_execution()
    execution.accept_event(
      test_event("stopped", { "reason": "breakpoint", "threadId": 7 }),
    )
    let thread = @moondbg.ThreadSelection::initial()
    let first = execution.load_stack_window(
      thread,
      @moondbg.StackWindow::new(0, 3),
    )
    assert_eq(first.loaded_count(), 3)
    assert_eq(first.total_frames_hint(), Some(99))
    assert_false(first.is_complete())
    assert_true(
      first.frame(0).map(frame => frame.kind()) is Some(@moondbg.NativeFrame),
    )
    assert_true(
      first.frame(1).map(frame => frame.kind()) is Some(@moondbg.UnknownFrame),
    )
    assert_true(
      first.frame(2).map(frame => frame.kind())
      is Some(@moondbg.MoonBitUserFrame),
    )
    let second = execution.load_stack_window(
      thread,
      @moondbg.StackWindow::new(3, 3),
    )
    assert_eq(second.loaded_count(), 6)
    assert_eq(second.total_frames_hint(), Some(6))
    assert_false(second.is_complete())
    let complete_stack = execution.load_stack_window(
      thread,
      @moondbg.StackWindow::new(6, 3),
    )
    assert_eq(complete_stack.loaded_count(), 7)
    assert_eq(complete_stack.total_frames_hint(), Some(7))
    assert_true(complete_stack.is_complete())
    assert_eq(complete_stack.frames().map(frame => frame.physical_index()), [
      0, 1, 2, 3, 4, 5, 6,
    ])
    assert_eq(execution.machine.frame_id(0), Some(100))
    assert_eq(execution.machine.frame_id(6), Some(106))
    assert_eq(execution.machine.frame_index(104), Some(4))
    assert_eq(transport.remaining_inputs(), 0)
    let stack_requests = transport
      .sent_messages()
      .filter(message => sent_command(message) == Some("stackTrace"))
    assert_true(
      stack_requests
      is [
        {
          "arguments": {
            "startFrame": Number(0, ..),
            "levels": Number(3, ..),
            ..
          },
          ..
        },
        {
          "arguments": {
            "startFrame": Number(3, ..),
            "levels": Number(3, ..),
            ..
          },
          ..
        },
        {
          "arguments": {
            "startFrame": Number(6, ..),
            "levels": Number(3, ..),
            ..
          },
          ..
        },
      ],
    )
  })
}

///|
async test "P3 an exact page multiple requires a confirming empty page" {
  @async.with_task_group(async fn(_group) {
    let transport = @dap_testkit.ScriptedTransport::new([
      scripted_response(4100, 1, "initialize", {}),
      scripted_response(
        4101,
        2,
        "stackTrace",
        scripted_stack_page(
          [
            scripted_user_frame(200, 0),
            scripted_user_frame(201, 1),
            scripted_user_frame(202, 2),
          ],
          6,
        ),
      ),
      scripted_response(
        4102,
        3,
        "stackTrace",
        scripted_stack_page(
          [
            scripted_user_frame(203, 3),
            scripted_user_frame(204, 4),
            scripted_user_frame(205, 5),
          ],
          6,
        ),
      ),
      scripted_response(4103, 4, "stackTrace", scripted_stack_page([], 6)),
    ])
    let execution = DebugExecution::prepare_with_dispatcher(
      @dap.DapDispatcher::from_transport(transport.as_transport()),
    )
    defer execution.close()
    execution.machine.begin_execution()
    execution.accept_event(
      test_event("stopped", { "reason": "entry", "threadId": 1 }),
    )
    let thread = @moondbg.ThreadSelection::initial()
    execution.load_stack_window(thread, @moondbg.StackWindow::new(0, 3))
    |> ignore
    let full_page = execution.load_stack_window(
      thread,
      @moondbg.StackWindow::new(3, 3),
    )
    assert_eq(full_page.loaded_count(), 6)
    assert_false(full_page.is_complete())
    let confirmed = execution.load_stack_window(
      thread,
      @moondbg.StackWindow::new(6, 3),
    )
    assert_eq(confirmed.loaded_count(), 6)
    assert_true(confirmed.is_complete())
    assert_eq(transport.remaining_inputs(), 0)
  })
}

///|
async test "P3 initial selection pages past native frames without renumbering" {
  @async.with_task_group(async fn(group) {
    let first_page : Array[Json] = []
    for physical_index in 0..<20 {
      first_page.push(
        scripted_native_frame(300 + physical_index, physical_index),
      )
    }
    let script = [
      scripted_response(4200, 1, "initialize", {
        "supportsConfigurationDoneRequest": true,
      }),
      scripted_event(4201, "initialized", {}),
      scripted_response(4202, 3, "configurationDone", {}),
      scripted_response(4203, 2, "launch", {}),
      scripted_event(4204, "stopped", { "reason": "breakpoint", "threadId": 1 }),
      scripted_response(
        4205,
        4,
        "stackTrace",
        scripted_stack_page(first_page, 21),
      ),
      scripted_response(
        4206,
        5,
        "stackTrace",
        scripted_stack_page([scripted_user_frame(320, 20)], 21),
      ),
      scripted_response(4207, 6, "scopes", {
        "scopes": [
          {
            "name": "Locals",
            "presentationHint": "locals",
            "variablesReference": 1,
          },
        ],
      }),
      scripted_response(4208, 7, "variables", {
        "variables": [
          {
            "name": "native_answer",
            "type": "Int",
            "value": "300",
            "variablesReference": 0,
          },
        ],
      }),
    ]
    let transport = @dap_testkit.ScriptedTransport::new(script)
    let lldb_session = LldbDapSession::start_with_dispatcher_factory(
      group,
      () => @dap.DapDispatcher::from_transport(transport.as_transport()),
      preparation_timeout_ms=10000,
    )
    let backend = LldbDapBackend::{ session: lldb_session, }
    let session = @moondbg.DebugSession::new("/tmp/paged-program", backend)
    defer session.close()
    guard session.run() is @moondbg.Stopped(initial_stop) else {
      fail("the paged execution should stop")
    }
    assert_eq(initial_stop.function_name(), "user.frame.20")
    assert_eq(initial_stop.source_path(), Some("/tmp/frame_20.mbt"))
    assert_eq(initial_stop.line(), Some(21))
    guard session.last_stop_snapshot() is Some(retained_stop) else {
      fail("the initial stop snapshot should be retained")
    }
    assert_eq(retained_stop.function_name(), initial_stop.function_name())
    assert_eq(retained_stop.source_path(), initial_stop.source_path())
    assert_eq(retained_stop.line(), initial_stop.line())
    assert_eq(session.selected_frame().map(frame => frame.index()), Some(20))
    guard session.selected_frame_snapshot() is Some(selected_user) else {
      fail("the selected user frame should have a domain snapshot")
    }
    assert_eq(selected_user.physical_index(), 20)
    assert_eq(selected_user.source_path(), Some("/tmp/frame_20.mbt"))
    assert_eq(selected_user.line(), Some(21))
    guard session.stack_snapshot() is Some(stack) else {
      fail("the complete cumulative stack should be retained")
    }
    assert_eq(stack.loaded_count(), 21)
    assert_true(stack.is_complete())
    assert_eq(stack.visible_frames().map(frame => frame.physical_index()), [20])
    guard backend.session.execution is Some(execution) else {
      fail("the stopped execution should retain private frame mappings")
    }
    assert_eq(execution.machine.frame_id(20), Some(320))
    session.select_frame(0) |> ignore
    guard session.last_stop_snapshot() is Some(after_selection) else {
      fail("explicit selection should retain the normalized initial stop")
    }
    assert_eq(after_selection.function_name(), "user.frame.20")
    guard session.selected_frame_snapshot() is Some(selected_native) else {
      fail("the selected native frame should have a domain snapshot")
    }
    assert_eq(selected_native.physical_index(), 0)
    assert_eq(selected_native.source_path(), Some("/tmp/frame_0.c"))
    guard session.find_variable(@moondbg.VariablePath::root("native_answer"))
      is @moondbg.VariableFound(native_answer) else {
      fail("variable lookup should use the explicitly selected native frame")
    }
    assert_eq(native_answer.value(), "300")
    assert_eq(transport.remaining_inputs(), 0)
    let sent = transport.sent_messages()
    assert_eq(sent.filter_map(sent_command), [
      "initialize", "launch", "configurationDone", "stackTrace", "stackTrace", "scopes",
      "variables",
    ])
    let stack_requests = sent.filter(message => {
      sent_command(message) == Some("stackTrace")
    })
    assert_true(
      stack_requests
      is [
        {
          "arguments": {
            "startFrame": Number(0, ..),
            "levels": Number(20, ..),
            ..
          },
          ..
        },
        {
          "arguments": {
            "startFrame": Number(20, ..),
            "levels": Number(20, ..),
            ..
          },
          ..
        },
      ],
    )
  })
}

///|
async test "P3 stack pagination rejects oversized duplicate and invalid windows" {
  @async.with_task_group(async fn(_group) {
    let oversized_transport = @dap_testkit.ScriptedTransport::new([
      scripted_response(4300, 1, "initialize", {}),
      scripted_response(
        4301,
        2,
        "stackTrace",
        scripted_stack_page(
          [
            scripted_user_frame(400, 0),
            scripted_user_frame(401, 1),
            scripted_user_frame(402, 2),
          ],
          3,
        ),
      ),
    ])
    let oversized = DebugExecution::prepare_with_dispatcher(
      @dap.DapDispatcher::from_transport(oversized_transport.as_transport()),
    )
    defer oversized.close()
    oversized.machine.begin_execution()
    oversized.accept_event(
      test_event("stopped", { "reason": "entry", "threadId": 1 }),
    )
    assert_true(
      try {
        oversized.load_stack_window(
          @moondbg.ThreadSelection::initial(),
          @moondbg.StackWindow::new(0, 2),
        )
        |> ignore
        false
      } catch {
        StackPageTooLarge(requested=2, actual=3) => true
        _ => false
      },
    )
    assert_eq(oversized.stack_snapshot, None)
    assert_eq(oversized.machine.frame_id(0), None)

    let duplicate_transport = @dap_testkit.ScriptedTransport::new([
      scripted_response(4310, 1, "initialize", {}),
      scripted_response(
        4311,
        2,
        "stackTrace",
        scripted_stack_page(
          [scripted_user_frame(410, 0), scripted_user_frame(410, 1)],
          2,
        ),
      ),
    ])
    let duplicate = DebugExecution::prepare_with_dispatcher(
      @dap.DapDispatcher::from_transport(duplicate_transport.as_transport()),
    )
    defer duplicate.close()
    duplicate.machine.begin_execution()
    duplicate.accept_event(
      test_event("stopped", { "reason": "entry", "threadId": 1 }),
    )
    assert_true(
      try {
        duplicate.load_stack_window(
          @moondbg.ThreadSelection::initial(),
          @moondbg.StackWindow::new(0, 2),
        )
        |> ignore
        false
      } catch {
        DuplicateStackFrameId(410) => true
        _ => false
      },
    )
    assert_eq(duplicate.stack_snapshot, None)

    let window_transport = @dap_testkit.ScriptedTransport::new([
      scripted_response(4320, 1, "initialize", {}),
      scripted_response(
        4321,
        2,
        "stackTrace",
        scripted_stack_page([scripted_user_frame(420, 0)], 3),
      ),
    ])
    let windowed = DebugExecution::prepare_with_dispatcher(
      @dap.DapDispatcher::from_transport(window_transport.as_transport()),
    )
    defer windowed.close()
    windowed.machine.begin_execution()
    windowed.accept_event(
      test_event("stopped", { "reason": "entry", "threadId": 1 }),
    )
    windowed.load_stack_window(
      @moondbg.ThreadSelection::initial(),
      @moondbg.StackWindow::new(0, 1),
    )
    |> ignore
    assert_true(
      try {
        windowed.load_stack_window(
          @moondbg.ThreadSelection::initial(),
          @moondbg.StackWindow::new(2, 1),
        )
        |> ignore
        false
      } catch {
        NonContiguousStackRequest(expected=1, actual=2) => true
        _ => false
      },
    )
    assert_true(
      try {
        windowed.load_stack_window(
          @moondbg.ThreadSelection::initial(),
          @moondbg.StackWindow::new(0, 2),
        )
        |> ignore
        false
      } catch {
        OverlappingStackRequest(loaded_end=1, requested_end=2) => true
        _ => false
      },
    )
    assert_eq(window_transport.remaining_inputs(), 0)
  })
}

///|
async test "P3 duplicate frame ids across pages are rejected before cache mutation" {
  @async.with_task_group(async fn(_group) {
    let transport = @dap_testkit.ScriptedTransport::new([
      scripted_response(4400, 1, "initialize", {}),
      scripted_response(
        4401,
        2,
        "stackTrace",
        scripted_stack_page([scripted_user_frame(500, 0)], 2),
      ),
      scripted_response(
        4402,
        3,
        "stackTrace",
        scripted_stack_page([scripted_user_frame(500, 1)], 2),
      ),
    ])
    let execution = DebugExecution::prepare_with_dispatcher(
      @dap.DapDispatcher::from_transport(transport.as_transport()),
    )
    defer execution.close()
    execution.machine.begin_execution()
    execution.accept_event(
      test_event("stopped", { "reason": "entry", "threadId": 1 }),
    )
    execution.load_stack_window(
      @moondbg.ThreadSelection::initial(),
      @moondbg.StackWindow::new(0, 1),
    )
    |> ignore
    assert_true(
      try {
        execution.load_stack_window(
          @moondbg.ThreadSelection::initial(),
          @moondbg.StackWindow::new(1, 1),
        )
        |> ignore
        false
      } catch {
        DuplicateStackFrameId(500) => true
        _ => false
      },
    )
    assert_eq(
      execution.stack_snapshot.map(stack => stack.loaded_count()),
      Some(1),
    )
    assert_eq(execution.machine.frame_id(1), None)
  })
}

///|
async test "P3 frame-scoped raw caches coexist with reusable domain snapshots" {
  @async.with_task_group(async fn(group) {
    let transport = @dap_testkit.ScriptedTransport::new([
      scripted_response(4500, 1, "initialize", {
        "supportsConfigurationDoneRequest": true,
      }),
      scripted_event(4501, "initialized", {}),
      scripted_response(4502, 3, "configurationDone", {}),
      scripted_response(4503, 2, "launch", {}),
      scripted_event(4504, "stopped", { "reason": "breakpoint", "threadId": 1 }),
      scripted_response(
        4505,
        4,
        "stackTrace",
        scripted_stack_page(
          [scripted_user_frame(600, 0), scripted_user_frame(601, 1)],
          2,
        ),
      ),
      scripted_response(4506, 5, "scopes", {
        "scopes": [
          {
            "name": "Locals",
            "presentationHint": "locals",
            "variablesReference": 1,
          },
        ],
      }),
      scripted_response(4507, 6, "variables", {
        "variables": [
          {
            "name": "answer",
            "type": "Int",
            "value": "10",
            "variablesReference": 0,
          },
        ],
      }),
      scripted_response(4508, 7, "scopes", {
        "scopes": [
          {
            "name": "Locals",
            "presentationHint": "locals",
            "variablesReference": 1,
          },
        ],
      }),
      scripted_response(4509, 8, "variables", {
        "variables": [
          {
            "name": "answer",
            "type": "Int",
            "value": "20",
            "variablesReference": 0,
          },
        ],
      }),
    ])
    let lldb_session = LldbDapSession::start_with_dispatcher_factory(
      group,
      () => @dap.DapDispatcher::from_transport(transport.as_transport()),
      preparation_timeout_ms=10000,
    )
    let backend = LldbDapBackend::{ session: lldb_session, }
    let session = @moondbg.DebugSession::new(
      "/tmp/frame-cache-program", backend,
    )
    defer session.close()
    session.run() |> ignore
    let answer = @moondbg.VariablePath::root("answer")
    guard session.find_variable(answer) is @moondbg.VariableFound(top) else {
      fail("the top frame should expose answer")
    }
    assert_eq(top.value(), "10")
    session.select_frame(1) |> ignore
    guard session.find_variable(answer) is @moondbg.VariableFound(caller) else {
      fail("the caller frame should expose its own answer")
    }
    assert_eq(caller.value(), "20")
    session.select_frame(0) |> ignore
    guard session.find_variable(answer) is @moondbg.VariableFound(cached_top) else {
      fail("the materialized top-frame answer should remain reusable")
    }
    assert_eq(cached_top.value(), "10")
    assert_eq(transport.remaining_inputs(), 0)
    assert_eq(transport.sent_messages().filter_map(sent_command), [
      "initialize", "launch", "configurationDone", "stackTrace", "scopes", "variables",
      "scopes", "variables",
    ])
  })
}

///|
async test "P5 locals isolate reused references by frame and cache materialized summaries" {
  @async.with_task_group(async fn(group) {
    let first_frame_variables : Json = {
      "variables": [
        {
          "name": "answer",
          "type": "int",
          "value": "10",
          "variablesReference": 0,
          "evaluateName": "answer",
        },
        {
          "name": "future",
          "type": "int",
          "value": "<variable not available>",
          "variablesReference": 0,
          "evaluateName": "future",
        },
        {
          "name": "shadowed_value @ x19",
          "type": "int",
          "value": "3",
          "variablesReference": 0,
          "evaluateName": "shadowed_value",
        },
        {
          "name": "shadowed_value @ ",
          "type": "int",
          "value": "<error: variable not available>",
          "variablesReference": 0,
          "evaluateName": "shadowed_value",
        },
      ],
    }
    let transport = @dap_testkit.ScriptedTransport::new([
      scripted_response(4600, 1, "initialize", {
        "supportsConfigurationDoneRequest": true,
      }),
      scripted_event(4601, "initialized", {}),
      scripted_response(4602, 3, "configurationDone", {}),
      scripted_response(4603, 2, "launch", {}),
      scripted_event(4604, "stopped", { "reason": "breakpoint", "threadId": 1 }),
      scripted_response(
        4605,
        4,
        "stackTrace",
        scripted_stack_page(
          [scripted_user_frame(700, 0), scripted_user_frame(701, 1)],
          2,
        ),
      ),
      scripted_response(4606, 5, "scopes", {
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
      }),
      scripted_response(4607, 6, "variables", first_frame_variables),
      scripted_response(4608, 7, "evaluate", {
        "result": "340",
        "type": "int",
        "variablesReference": 0,
      }),
      scripted_response(4609, 8, "scopes", {
        "scopes": [
          {
            "name": "Locals",
            "presentationHint": "locals",
            "variablesReference": 1,
          },
        ],
      }),
      scripted_response(4610, 9, "variables", {
        "variables": [
          {
            "name": "answer",
            "type": "int",
            "value": "20",
            "variablesReference": 0,
          },
        ],
      }),
      scripted_event(4611, "stopped", { "reason": "step", "threadId": 1 }),
      scripted_response(4612, 10, "next", {}),
      scripted_response(
        4613,
        11,
        "stackTrace",
        scripted_stack_page([scripted_user_frame(702, 0)], 1),
      ),
      scripted_response(4614, 12, "scopes", {
        "scopes": [
          {
            "name": "Locals",
            "presentationHint": "locals",
            "variablesReference": 1,
          },
        ],
      }),
      scripted_response(4615, 13, "variables", {
        "variables": [
          {
            "name": "answer",
            "type": "int",
            "value": "30",
            "variablesReference": 0,
          },
        ],
      }),
    ])
    let lldb_session = LldbDapSession::start_with_dispatcher_factory(
      group,
      () => @dap.DapDispatcher::from_transport(transport.as_transport()),
      preparation_timeout_ms=10000,
    )
    let backend = LldbDapBackend::{ session: lldb_session, }
    let session = @moondbg.DebugSession::new("/tmp/locals-cache", backend)
    defer session.close()
    session.run() |> ignore
    let first_locals = session.local_variables()
    assert_eq(first_locals.thread().index(), 0)
    assert_eq(first_locals.frame().index(), 0)
    guard first_locals.variables() is [answer, future, shadowed] else {
      fail("first frame should expose deterministic compact local summaries")
    }
    assert_eq(answer.name(), "answer")
    assert_eq(
      answer.availability(),
      @moondbg.LocalVariableAvailable(@moondbg.LocalScalar("10")),
    )
    assert_true(future.availability() is @moondbg.LocalVariableUnavailable)
    assert_eq(shadowed.name(), "shadowed_value")
    assert_eq(
      shadowed.availability(),
      @moondbg.LocalVariableAvailable(@moondbg.LocalScalar("340")),
    )
    guard session.find_variable(@moondbg.VariablePath::root("answer"))
      is @moondbg.VariableFound(first_print) else {
      fail("print should reuse raw locals for the selected frame")
    }
    assert_eq(first_print.value(), "10")
    guard session.find_variable(@moondbg.VariablePath::root("shadowed_value"))
      is @moondbg.VariableFound(shadowed_print) else {
      fail("print should reuse the exact evaluated shadow binding")
    }
    assert_eq(shadowed_print.value(), "340")

    session.select_frame(1) |> ignore
    let caller_locals = session.local_variables()
    assert_eq(caller_locals.thread().index(), 0)
    assert_eq(caller_locals.frame().index(), 1)
    guard caller_locals.variables() is [caller] else {
      fail("caller should use its own reused variablesReference")
    }
    assert_eq(
      caller.availability(),
      @moondbg.LocalVariableAvailable(@moondbg.LocalScalar("20")),
    )
    guard session.find_variable(@moondbg.VariablePath::root("answer"))
      is @moondbg.VariableFound(caller_print) else {
      fail("caller print should share only caller-scoped raw variables")
    }
    assert_eq(caller_print.value(), "20")

    session.select_frame(0) |> ignore
    let cached_locals = session.local_variables()
    assert_eq(cached_locals.frame().index(), 0)
    guard cached_locals.variables() is [cached, _, _] else {
      fail("switching back should reuse the materialized frame summary")
    }
    assert_eq(cached.availability(), answer.availability())
    guard session.find_variable(@moondbg.VariablePath::root("answer"))
      is @moondbg.VariableFound(cached_print) else {
      fail("switching back should retain the materialized print snapshot")
    }
    assert_eq(cached_print.value(), "10")

    session.next() |> ignore
    let resumed_locals = session.local_variables()
    assert_eq(resumed_locals.frame().index(), 0)
    guard resumed_locals.variables() is [after_resume] else {
      fail("a resumed stop should rebuild local summaries")
    }
    assert_eq(
      after_resume.availability(),
      @moondbg.LocalVariableAvailable(@moondbg.LocalScalar("30")),
    )
    assert_eq(transport.remaining_inputs(), 0)
    assert_eq(transport.sent_messages().filter_map(sent_command), [
      "initialize", "launch", "configurationDone", "stackTrace", "scopes", "variables",
      "evaluate", "scopes", "variables", "next", "stackTrace", "scopes", "variables",
    ])
  })
}

///|
async test "P5 locals reports a missing Locals scope without loading globals" {
  @async.with_task_group(async fn(group) {
    let transport = @dap_testkit.ScriptedTransport::new([
      scripted_response(4650, 1, "initialize", {
        "supportsConfigurationDoneRequest": true,
      }),
      scripted_event(4651, "initialized", {}),
      scripted_response(4652, 3, "configurationDone", {}),
      scripted_response(4653, 2, "launch", {}),
      scripted_event(4654, "stopped", { "reason": "breakpoint", "threadId": 1 }),
      scripted_response(4655, 4, "stackTrace", scripted_stack_body(710, 3)),
      scripted_response(4656, 5, "scopes", {
        "scopes": [
          { "name": "Globals", "variablesReference": 1 },
          {
            "name": "Registers",
            "presentationHint": "registers",
            "variablesReference": 2,
          },
        ],
      }),
    ])
    let lldb_session = LldbDapSession::start_with_dispatcher_factory(
      group,
      () => @dap.DapDispatcher::from_transport(transport.as_transport()),
      preparation_timeout_ms=10000,
    )
    let backend = LldbDapBackend::{ session: lldb_session, }
    let session = @moondbg.DebugSession::new("/tmp/no-locals", backend)
    defer session.close()
    session.run() |> ignore
    let snapshot = session.local_variables()
    assert_true(snapshot.scope_availability() is @moondbg.LocalScopeUnavailable)
    assert_eq(snapshot.variables().length(), 0)
    assert_eq(transport.remaining_inputs(), 0)
    assert_eq(transport.sent_messages().filter_map(sent_command), [
      "initialize", "launch", "configurationDone", "stackTrace", "scopes",
    ])
  })
}

///|
async test "P5 locals summarize collections structs and enums without recursive rendering" {
  @async.with_task_group(async fn(group) {
    let transport = @dap_testkit.ScriptedTransport::new([
      scripted_response(4700, 1, "initialize", {
        "supportsConfigurationDoneRequest": true,
        "supportsReadMemoryRequest": true,
      }),
      scripted_event(4701, "initialized", {}),
      scripted_response(4702, 3, "configurationDone", {}),
      scripted_response(4703, 2, "launch", {}),
      scripted_event(4704, "stopped", { "reason": "breakpoint", "threadId": 1 }),
      scripted_response(4705, 4, "stackTrace", scripted_stack_body(720, 9)),
      scripted_response(4706, 5, "scopes", {
        "scopes": [
          {
            "name": "Locals",
            "presentationHint": "locals",
            "variablesReference": 1,
          },
        ],
      }),
      scripted_response(4707, 6, "variables", {
        "variables": [
          {
            "name": "count",
            "type": "int",
            "value": "3",
            "variablesReference": 0,
          },
          {
            "name": "fixed",
            "type": "moonbit.array_i32",
            "value": "moonbit.array_i32 @ 0x1000",
            "variablesReference": 10,
          },
          {
            "name": "broken",
            "type": "moonbit.array_i32",
            "value": "moonbit.array_i32 @ 0x5000",
            "variablesReference": 50,
          },
          {
            "name": "items",
            "type": "moonbitlang/core/builtin/Array[double] &",
            "value": "0x4000",
            "variablesReference": 40,
          },
          {
            "name": "point",
            "type": "example/Point &",
            "value": "0x2000",
            "variablesReference": 20,
          },
          {
            "name": "list",
            "type": "example/List",
            "value": "example/List @ 0x3000",
            "variablesReference": 30,
          },
        ],
      }),
      scripted_response(4708, 7, "variables", {
        "variables": [
          {
            "name": "body",
            "type": "int *",
            "value": "0x1000",
            "variablesReference": 0,
          },
        ],
      }),
      scripted_response(4709, 8, "readMemory", { "data": "AAAAAAoAAAA=" }),
      scripted_response(4710, 9, "variables", {
        "variables": [
          {
            "name": "unexpected",
            "type": "int",
            "value": "1",
            "variablesReference": 0,
          },
        ],
      }),
      scripted_response(4711, 10, "variables", {
        "variables": [
          {
            "name": "buf",
            "type": "FixedArray[UnsafeMaybeUninit[Double]]",
            "value": "FixedArray @ 0x4000",
            "variablesReference": 41,
          },
          {
            "name": "len",
            "type": "int",
            "value": "4",
            "variablesReference": 0,
          },
        ],
      }),
      scripted_response(4712, 11, "variables", {
        "variables": [
          {
            "name": "body",
            "type": "double *",
            "value": "0x4000",
            "variablesReference": 0,
          },
        ],
      }),
      scripted_response(4713, 12, "readMemory", { "data": "AAAAAAgAAAA=" }),
      scripted_response(4714, 13, "variables", {
        "variables": [
          {
            "name": "__moonbit_enum_marker",
            "type": "moonbit.enum",
            "value": "moonbit.enum @ 0x3000",
            "variablesReference": 0,
          },
          {
            "name": "Empty_0",
            "type": "example/List.Empty *",
            "value": "0x0000000000003000",
            "variablesReference": 31,
          },
          {
            "name": "Cons_1",
            "type": "example/List.Cons *",
            "value": "0x0000000000003000",
            "variablesReference": 32,
          },
        ],
      }),
      scripted_response(4715, 14, "readMemory", { "data": "AQAAQA==" }),
    ])
    let lldb_session = LldbDapSession::start_with_dispatcher_factory(
      group,
      () => @dap.DapDispatcher::from_transport(transport.as_transport()),
      preparation_timeout_ms=10000,
    )
    let backend = LldbDapBackend::{ session: lldb_session, }
    let session = @moondbg.DebugSession::new("/tmp/compact-locals", backend)
    defer session.close()
    session.run() |> ignore
    guard session.local_variables().variables()
      is [count, fixed, broken, items, point, list] else {
      fail("compact locals should preserve root order")
    }
    assert_eq(count.type_name(), Some("Int"))
    assert_eq(
      count.availability(),
      @moondbg.LocalVariableAvailable(@moondbg.LocalScalar("3")),
    )
    assert_eq(fixed.type_name(), Some("FixedArray[Int]"))
    assert_eq(
      fixed.availability(),
      @moondbg.LocalVariableAvailable(
        @moondbg.LocalCollection(@moondbg.FixedArrayCollection, 10),
      ),
    )
    assert_eq(broken.type_name(), Some("FixedArray[Int]"))
    assert_eq(
      broken.availability(),
      @moondbg.LocalVariableAvailable(@moondbg.LocalOpaque),
    )
    assert_eq(point.type_name(), Some("Point"))
    assert_eq(
      point.availability(),
      @moondbg.LocalVariableAvailable(@moondbg.LocalStructure),
    )
    assert_eq(items.type_name(), Some("Array[Double]"))
    assert_eq(
      items.availability(),
      @moondbg.LocalVariableAvailable(
        @moondbg.LocalCollection(@moondbg.ArrayCollection, 4),
      ),
    )
    assert_eq(list.type_name(), Some("List"))
    assert_eq(
      list.availability(),
      @moondbg.LocalVariableAvailable(@moondbg.LocalEnumConstructor("Cons")),
    )
    assert_eq(transport.remaining_inputs(), 0)
    let sent = transport.sent_messages()
    assert_eq(sent.filter_map(sent_command), [
      "initialize", "launch", "configurationDone", "stackTrace", "scopes", "variables",
      "variables", "readMemory", "variables", "variables", "variables", "readMemory",
      "variables", "readMemory",
    ])
    assert_false(
      sent.any(message => {
        message
        is { "arguments": { "variablesReference": Number(20, ..), .. }, .. }
      }),
    )
  })
}

///|
async test "P5 compact aggregate summaries do not hide adapter request failures" {
  @async.with_task_group(async fn(group) {
    let transport = @dap_testkit.ScriptedTransport::new([
      scripted_response(4750, 1, "initialize", {
        "supportsConfigurationDoneRequest": true,
      }),
      scripted_event(4751, "initialized", {}),
      scripted_response(4752, 3, "configurationDone", {}),
      scripted_response(4753, 2, "launch", {}),
      scripted_event(4754, "stopped", { "reason": "breakpoint", "threadId": 1 }),
      scripted_response(4755, 4, "stackTrace", scripted_stack_body(730, 10)),
      scripted_failed_response(4756, 5, "variables", "layout request failed"),
    ])
    let lldb_session = LldbDapSession::start_with_dispatcher_factory(
      group,
      () => @dap.DapDispatcher::from_transport(transport.as_transport()),
      preparation_timeout_ms=10000,
    )
    let backend = LldbDapBackend::{ session: lldb_session, }
    let session = @moondbg.DebugSession::new(
      "/tmp/failed-local-layout", backend,
    )
    defer session.close()
    session.run() |> ignore
    guard backend.session.execution is Some(execution) &&
      execution.machine.current_stop_epoch() is Some(epoch) else {
      fail("scripted aggregate failure should retain a stopped execution")
    }
    execution.variable_cache.select_frame(epoch, 0)
    let failed = try {
      execution
      .variable_inspector()
      .compact_local_variable(
        VariableCacheIdentity::{ epoch, frame_index: 0, },
        DapVariable::{
          name: "broken",
          value: "moonbit.array_i32 @ 0x5000",
          type_name: Some("moonbit.array_i32"),
          variables_reference: 50,
          evaluate_name: Some("broken"),
        },
      )
      |> ignore
      false
    } catch {
      RequestFailed(command="variables", message="layout request failed") =>
        true
      _ => false
    }
    assert_true(failed)
    assert_eq(transport.remaining_inputs(), 0)
  })
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
    let backend = LldbDapBackend::{ session: lldb_session, }
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
    guard session.stack_snapshot() is Some(stack) else {
      fail("the stable stop should retain the parsed stack window")
    }
    assert_eq(stack.loaded_start(), 0)
    assert_eq(stack.loaded_count(), 2)
    assert_eq(stack.total_frames_hint(), Some(2))
    assert_true(stack.is_complete())
    assert_eq(stack.frames().map(frame => frame.physical_index()), [0, 1])
    assert_eq(session.selected_frame().map(frame => frame.index()), Some(1))
    assert_eq(execution.machine.frame_id(1), Some(10))
    assert_eq(execution.machine.frame_index(10), Some(1))
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
    let first_frame_identity = VariableCacheIdentity::{
      epoch: 1,
      frame_index: 1,
    }
    assert_true(
      execution.variable_cache.cached_scopes(first_frame_identity) is Some(_),
    )
    guard session.next() is @moondbg.Stopped(after_next) else {
      fail("next should stop again")
    }
    assert_eq(after_next.reason(), "step")
    assert_eq(execution.machine.stop_epoch, 2)
    assert_eq(execution.machine.frame_index(10), None)
    assert_eq(execution.machine.frame_id(0), Some(11))
    assert_true(
      execution.variable_cache.cached_scopes(first_frame_identity) is None,
    )
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
    let backend = LldbDapBackend::{ session: lldb_session, }
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
    assert_eq(outcome.dap_id, None)
    assert_true(
      execution.breakpoint_state.families.get(pending.id())
      is Some({ id: LldbBreakpointId(7), .. }),
    )
    assert_eq(outcome.location_count, Some(2))
    let sent = transport.sent_messages()
    assert_eq(sent.filter_map(sent_command), [
      "initialize", "launch", "evaluate", "evaluate", "configurationDone", "stackTrace",
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
    assert_eq(family_outcome.dap_id, None)
    assert_true(
      execution.breakpoint_state.families.get(5)
      is Some({ id: LldbBreakpointId(57), .. }),
    )
    assert_eq(family_outcome.location_count, Some(2))
    assert_eq(session.source_breakpoints.length(), 3)
    assert_eq(session.function_breakpoints.length(), 4)

    let sent = transport.sent_messages()
    assert_eq(sent.filter_map(sent_command), [
      "initialize", "launch", "configurationDone", "stackTrace", "setBreakpoints",
      "setBreakpoints", "setFunctionBreakpoints", "setFunctionBreakpoints", "evaluate",
      "evaluate", "evaluate", "evaluate", "setBreakpoints",
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
    assert_eq(session.source_breakpoints.length(), 0)
    // This is the execution's applied copy, not authoritative configuration.
    // The application-level recovery test separately retains the logical ID.
    assert_eq(session.source_breakpoints().length(), 0)
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
    let backend = LldbDapBackend::{ session: lldb_session, }
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
    let backend = LldbDapBackend::{ session: lldb_session, }
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
  machine.remember_frame(0, 42)
  machine.fail("adapter closed")
  assert_true(machine.state is Failed)
  assert_eq(machine.failure_message, Some("adapter closed"))
  assert_eq(machine.frame_id(0), None)
  assert_eq(machine.frame_index(42), None)
  machine.accept_event(test_event("terminated", {}))
  assert_true(machine.state is Failed)
}

///|
test "resuming invalidates frame and variable references from the stop epoch" {
  let machine = DapSessionMachine::new()
  machine.begin_execution()
  machine.mark_running()
  machine.accept_event(test_event("stopped", { "threadId": 7 }))
  machine.remember_frame(0, 42)
  machine.remember_variable_reference(99)
  assert_eq(machine.frame_id(0), Some(42))
  assert_eq(machine.frame_index(42), Some(0))
  assert_true(machine.has_current_variable_reference(99))
  machine.mark_resumed()
  assert_true(machine.state is Running)
  assert_eq(machine.frame_id(0), None)
  assert_eq(machine.frame_index(42), None)
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
test "a failed setBreakpoints response is uncertain and cannot replace outcomes" {
  let first = LogicalSourceBreakpoint::new(1, "/tmp/main.mbt", 4)
  let second = LogicalSourceBreakpoint::new(2, "/tmp/main.mbt", 9)
  let state = ExecutionBreakpointState::new()
  try {
    apply_breakpoint_response(
      state,
      [first, second],
      test_failed_response(41, 5, "setBreakpoints", "source is unavailable"),
    )
    fail("request failure is not an ordinary rejected location")
  } catch {
    @moondbg.BreakpointSyncError::BreakpointSyncUncertain(
      "source is unavailable"
    ) => ()
    error => raise error
  }
  assert_true(state.source_snapshot(first).status() is @moondbg.Pending)
  assert_true(state.source_snapshot(second).status() is @moondbg.Pending)
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
  let frames = parse_stack_frames(
    {
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
    },
    0,
  )
  assert_eq(frames.length(), 2)
  guard select_parsed_stack_frame(frames) is Some(frame) else {
    fail("expected a stack frame")
  }
  assert_eq(frame.physical_index, 1)
  assert_eq(frame.id, 11)
  assert_eq(frame.name, "main.inspect_value")
  assert_eq(frame.source_path, Some("/tmp/main.mbt"))
  assert_eq(frame.line, Some(4))
  assert_eq(frame.column, Some(3))
}

///|
test "MoonBit stack identity keeps raw linkage and decodes a source display name" {
  let parsed = parse_stack_frames(
    {
      "stackFrames": [
        {
          "id": 12,
          "name": "_M0FP14demo13generic__leafGiE",
          "source": { "path": "/tmp/main.mbt" },
          "line": 8,
          "column": 3,
        },
        {
          "id": 13,
          "name": "moonbit_main",
          "source": { "path": "/tmp/main.mbt" },
          "line": 12,
          "column": 1,
        },
      ],
    },
    0,
  )
  let generic = parsed[0].snapshot()
  assert_eq(generic.raw_name(), "_M0FP14demo13generic__leafGiE")
  assert_eq(generic.display_name(), "@demo.generic_leaf[Int]")
  assert_eq(generic.linkage_name(), Some("_M0FP14demo13generic__leafGiE"))
  let main = parsed[1].snapshot()
  assert_eq(main.raw_name(), "moonbit_main")
  assert_eq(main.display_name(), "main")
  assert_eq(main.linkage_name(), Some("moonbit_main"))
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
  assert_true(locals.is_locals())
  assert_true(globals.is_relevant())
  assert_false(globals.is_locals())
  assert_false(registers.is_relevant())
  assert_false(registers.is_locals())
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
test "local source names discard adapter location suffixes without selecting a shadow" {
  let with_evaluate_name = DapVariable::{
    name: "shadowed_value @ x19",
    value: "3",
    type_name: Some("int"),
    variables_reference: 0,
    evaluate_name: Some("shadowed_value"),
  }
  assert_eq(with_evaluate_name.source_local_name(), "shadowed_value")
  let without_evaluate_name = {
    ..with_evaluate_name,
    name: "fallback @ ",
    evaluate_name: None,
  }
  assert_eq(without_evaluate_name.source_local_name(), "fallback")
}

///|
test "indexed evaluate responses normalize struct pointers and reject malformed protocol" {
  let evaluated = parse_indexed_element_evaluate_response(
    {
      "result": "0x1010",
      "type": "example/geometry/Point *",
      "variablesReference": 9,
      "memoryReference": "0x1010",
    },
    "arr[0]",
  )
  assert_eq(evaluated.name, "arr[0]")
  assert_eq(evaluated.value, "0x1010")
  assert_eq(evaluated.type_name, Some("example/geometry/Point &"))
  assert_eq(evaluated.variables_reference, 9)
  assert_eq(evaluated.evaluate_name, None)
  let missing_reference_rejected = try {
    parse_indexed_element_evaluate_response(
      { "result": "1", "type": "int" },
      "arr[0]",
    )
    |> ignore
    false
  } catch {
    InvalidIndexedElementValue(message) => message.contains("incomplete")
    _ => false
  }
  assert_true(missing_reference_rejected)
  let malformed_memory_rejected = try {
    parse_indexed_element_evaluate_response(
      {
        "result": "1",
        "type": "int",
        "variablesReference": 0,
        "memoryReference": 7,
      },
      "arr[0]",
    )
    |> ignore
    false
  } catch {
    InvalidIndexedElementValue(message) => message.contains("memory reference")
    _ => false
  }
  assert_true(malformed_memory_rejected)
}

///|
test "lldb-dap variable lookup defers duplicate shadow bindings to evaluation" {
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
    is Some(first_stop) else {
    fail("the first shadow pair should be parsed")
  }
  assert_true(first_stop.select_root_variable("arr") is DapVariableAmbiguous)
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
    is Some(second_stop) else {
    fail("the second shadow pair should be parsed")
  }
  assert_true(second_stop.select_root_variable("arr") is DapVariableAmbiguous)
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
    },
  ]
  cache.reset(1)
  cache.select_frame(1, 10)
  let first_identity = VariableCacheIdentity::{ epoch: 1, frame_index: 10, }
  cache.store_scopes(first_identity, scopes)
  cache.store_variables(first_identity, 1, variables)
  cache.store_evaluated_variable(first_identity, "10:arr[0]", variables[0])
  let snapshot = variables[0].snapshot()
  cache.store_snapshot(first_identity, "10:answer", snapshot)
  assert_true(cache.cached_scopes(first_identity) is Some(_))
  assert_true(cache.cached_variables(first_identity, 1) is Some(_))
  guard cache.cached_evaluated_variable(first_identity, "10:arr[0]")
    is Some(cached) else {
    fail("the evaluated variable should be cached in its stop epoch")
  }
  assert_eq(cached.name, "answer")
  assert_eq(cached.value, "42")
  assert_eq(cache.cached_snapshot(first_identity, "10:answer"), Some(snapshot))
  cache.select_frame(1, 11)
  let caller_identity = VariableCacheIdentity::{ epoch: 1, frame_index: 11, }
  cache.store_scopes(first_identity, scopes)
  assert_true(cache.cached_scopes(caller_identity) is None)
  cache.select_frame(1, 10)
  assert_eq(cache.cached_snapshot(first_identity, "10:answer"), Some(snapshot))
  assert_true(cache.cached_scopes(first_identity) is None)
  cache.reset(2)
  let second_identity = VariableCacheIdentity::{ epoch: 2, frame_index: 10, }
  assert_true(cache.cached_scopes(first_identity) is None)
  assert_true(cache.cached_variables(first_identity, 1) is None)
  assert_true(
    cache.cached_evaluated_variable(first_identity, "10:arr[0]") is None,
  )
  assert_true(cache.cached_snapshot(first_identity, "10:answer") is None)
  assert_true(cache.cached_scopes(second_identity) is None)
  cache.store_variables(first_identity, 1, variables)
  cache.store_snapshot(first_identity, "10:answer", snapshot)
  assert_true(cache.cached_variables(second_identity, 1) is None)
  assert_true(cache.cached_snapshot(second_identity, "10:answer") is None)
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
    let backend = LldbDapBackend::{ session: lldb_session, }
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
      is @moondbg.VariableFound(choice) &&
      choice.content() is @moondbg.VariableEnum(enum_value) &&
      enum_value.payload() is [payload] else {
      fail("boxed enum root should expose its active shallow constructor")
    }
    assert_eq(choice.value(), "")
    assert_eq(enum_value.constructor_name(), "Some")
    assert_eq(payload.position(), 0)
    assert_eq(payload.type_name(), "Int")
    assert_eq(payload.scalar_value(), Some("9"))
    assert_eq(transport.remaining_inputs(), 0)
    assert_eq(transport.sent_messages().filter_map(sent_command), [
      "initialize", "launch", "configurationDone", "stackTrace", "scopes", "variables",
      "variables", "variables", "variables", "variables", "variables", "readMemory",
      "variables",
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
    let backend = LldbDapBackend::{ session: lldb_session, }
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
    let backend = LldbDapBackend::{ session: lldb_session, }
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
    assert_eq(short_collection.kind(), @moondbg.FixedArrayCollection)
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
    assert_eq(long_collection.kind(), @moondbg.FixedArrayCollection)
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
      launch_arguments.get("initCommands") is None &&
      launch_arguments.get("preRunCommands")
      is Some(Array([String("!settings set target.input-path /dev/null")])),
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
test "native payload pointers only accept explicit hexadecimal addresses" {
  assert_true(
    parse_native_payload_pointer("0x1234") is Some(PayloadPointer("0x1234")),
  )
  assert_true(
    parse_native_payload_pointer("  0x0000  ") is Some(NullPayloadPointer),
  )
  assert_true(parse_native_payload_pointer("4096") is None)
  assert_true(parse_native_payload_pointer("(int *) 0x1000") is None)
  assert_true(parse_native_payload_pointer("0x1000 trailing") is None)
  assert_true(parse_native_payload_pointer("0x") is None)
}

///|
async test "lldb-dap materializes Array logical values within bounded storage reads" {
  @async.with_task_group(async fn(group) {
    let transport = @dap_testkit.ScriptedTransport::new(
      array_double_variable_script(),
    )
    let lldb_session = LldbDapSession::start_with_dispatcher_factory(
      group,
      () => @dap.DapDispatcher::from_transport(transport.as_transport()),
      preparation_timeout_ms=10000,
    )
    let backend = LldbDapBackend::{ session: lldb_session, }
    let session = @moondbg.DebugSession::new("/tmp/array-program", backend)
    defer session.close()
    guard session.run() is @moondbg.Stopped(_) else {
      fail("scripted Array execution should stop")
    }
    guard session.find_variable(@moondbg.VariablePath::root("arr"))
      is @moondbg.VariableFound(short) &&
      short.content() is @moondbg.VariableIndexedCollection(short_collection) &&
      short_collection.preview_elements() is [first, .., last] &&
      first.value() is Some(first_value) &&
      last.value() is Some(last_value) else {
      fail("short Array should be materialized completely")
    }
    assert_eq(short_collection.kind(), @moondbg.ArrayCollection)
    assert_eq(short_collection.element_type_name(), "Double")
    assert_eq(short_collection.total_length(), 10)
    assert_true(short_collection.is_complete())
    assert_eq(first.index(), 0)
    assert_eq(first_value.value(), "1")
    assert_eq(last.index(), 9)
    assert_eq(last_value.value(), "10")
    guard session.find_variable(@moondbg.VariablePath::root("arr"))
      is @moondbg.VariableFound(cached_short) else {
      fail("same-stop Array lookup should use its snapshot cache")
    }
    assert_eq(cached_short, short)
    guard session.find_variable(@moondbg.VariablePath::root("empty"))
      is @moondbg.VariableFound(empty) &&
      empty.content() is @moondbg.VariableIndexedCollection(empty_collection) else {
      fail("a null zero-length Array should be materialized safely")
    }
    assert_eq(empty_collection.kind(), @moondbg.ArrayCollection)
    assert_eq(empty_collection.total_length(), 0)
    assert_true(empty_collection.preview_elements() is [])

    guard session.next() is @moondbg.Stopped(_) else {
      fail("next should establish a second Array stop epoch")
    }
    guard session.find_variable(@moondbg.VariablePath::root("arr"))
      is @moondbg.VariableFound(long) &&
      long.content() is @moondbg.VariableIndexedCollection(long_collection) &&
      long_collection.preview_elements() is [long_first, .., long_last] &&
      long_first.value() is Some(long_first_value) &&
      long_last.value() is Some(long_last_value) else {
      fail("long Array should retain its bounded head and logical tail")
    }
    assert_eq(long_collection.kind(), @moondbg.ArrayCollection)
    assert_eq(long_collection.total_length(), 100)
    assert_eq(long_collection.preview_elements().length(), 16)
    assert_eq(long_collection.omitted_count(), 84)
    assert_eq(long_first.index(), 0)
    assert_eq(long_first_value.value(), "1")
    assert_eq(long_last.index(), 99)
    assert_eq(long_last_value.value(), "100")
    guard session.find_variable(@moondbg.VariablePath::root("arr"))
      is @moondbg.VariableFound(cached_long) else {
      fail("second-stop Array lookup should also be cached")
    }
    assert_eq(cached_long, long)

    guard backend.session.execution is Some(execution) &&
      execution.machine.current_stop_epoch() is Some(epoch) else {
      fail("scripted Array execution should retain its second stop epoch")
    }
    let invalid_rejected = try {
      execution
      .variable_inspector()
      .find_variable_inner(
        VariableCacheIdentity::{ epoch, frame_index: 0, },
        121,
        @moondbg.VariablePath::root("invalid"),
      )
      |> ignore
      false
    } catch {
      InvalidIndexedCollectionValue(message) =>
        message.contains("InvalidArrayLength") &&
        message.contains("129") &&
        message.contains("128")
      _ => false
    }
    assert_true(invalid_rejected)

    assert_eq(transport.remaining_inputs(), 0)
    let sent = transport.sent_messages()
    assert_eq(sent.filter_map(sent_command), [
      "initialize", "launch", "configurationDone", "stackTrace", "scopes", "variables",
      "variables", "variables", "readMemory", "readMemory", "variables", "variables",
      "next", "stackTrace", "scopes", "variables", "variables", "variables", "readMemory",
      "readMemory", "readMemory", "variables", "variables", "readMemory",
    ])
    assert_false(sent.any(message => sent_command(message) == Some("evaluate")))
    assert_true(
      sent[8]
      is {
        "arguments": {
          "memoryReference": String("0x5000"),
          "offset": Number(-8, ..),
          "count": Number(8, ..),
          ..
        },
        ..
      },
    )
    assert_true(
      sent[9]
      is {
        "arguments": {
          "memoryReference": String("0x5000"),
          "offset": Number(0, ..),
          "count": Number(80, ..),
          ..
        },
        ..
      },
    )
    assert_true(
      sent[18]
      is {
        "arguments": {
          "memoryReference": String("0x6000"),
          "offset": Number(-8, ..),
          "count": Number(8, ..),
          ..
        },
        ..
      },
    )
    assert_true(
      sent[19]
      is {
        "arguments": {
          "memoryReference": String("0x6000"),
          "offset": Number(0, ..),
          "count": Number(120, ..),
          ..
        },
        ..
      },
    )
    assert_true(
      sent[20]
      is {
        "arguments": {
          "memoryReference": String("0x6000"),
          "offset": Number(792, ..),
          "count": Number(8, ..),
          ..
        },
        ..
      },
    )
  })
}

///|
async test "lldb-dap resolves precise Array and FixedArray indices with mixed field paths" {
  @async.with_task_group(async fn(group) {
    let transport = @dap_testkit.ScriptedTransport::new(
      indexed_path_variable_script(),
    )
    let lldb_session = LldbDapSession::start_with_dispatcher_factory(
      group,
      () => @dap.DapDispatcher::from_transport(transport.as_transport()),
      preparation_timeout_ms=10000,
    )
    let backend = LldbDapBackend::{ session: lldb_session, }
    let session = @moondbg.DebugSession::new(
      "/tmp/indexed-path-program", backend,
    )
    defer session.close()
    guard session.run() is @moondbg.Stopped(_) else {
      fail("scripted indexed-path execution should stop")
    }
    let arr_element_path = @moondbg.VariablePath::new("arr", [@moondbg.Index(0)])
    guard session.find_variable(arr_element_path)
      is @moondbg.VariableFound(point) &&
      point.content() is @moondbg.VariableStructure(point_structure) &&
      point_structure.children() is [x, y] else {
      fail("arr[0] should materialize one complete Point")
    }
    assert_eq(point.name(), "arr[0]")
    assert_eq(point.type_name(), Some("example/geometry/Point &"))
    assert_eq(x.name(), "x")
    assert_eq(x.value(), "1")
    assert_eq(y.name(), "y")
    assert_eq(y.value(), "2")
    guard session.find_variable(arr_element_path)
      is @moondbg.VariableFound(cached_point) else {
      fail("the exact indexed path should use its snapshot cache")
    }
    assert_eq(cached_point, point)
    guard session.find_variable(
        @moondbg.VariablePath::new("arr", [
          @moondbg.Index(0),
          @moondbg.Field("x"),
        ]),
      )
      is @moondbg.VariableFound(arr_x) else {
      fail("arr[0].x should continue through variablesReference")
    }
    assert_eq(arr_x.name(), "arr[0].x")
    assert_eq(arr_x.value(), "1")

    guard session.find_variable(
        @moondbg.VariablePath::new("lines", [
          @moondbg.Index(0),
          @moondbg.Field("start"),
          @moondbg.Field("x"),
        ]),
      )
      is @moondbg.VariableFound(line_x) else {
      fail("lines[0].start.x should resolve an Index/Field chain")
    }
    assert_eq(line_x.name(), "lines[0].start.x")
    assert_eq(line_x.value(), "1")

    guard session.find_variable(
        @moondbg.VariablePath::new("box", [
          @moondbg.Field("points"),
          @moondbg.Index(0),
          @moondbg.Field("x"),
        ]),
      )
      is @moondbg.VariableFound(box_x) else {
      fail("box.points[0].x should resolve a Field/Index/Field chain")
    }
    assert_eq(box_x.name(), "box.points[0].x")
    assert_eq(box_x.value(), "1")

    guard session.find_variable(
        @moondbg.VariablePath::new("ints", [@moondbg.Index(2)]),
      )
      is @moondbg.VariableFound(integer) else {
      fail("FixedArray scalar indexing should share the exact path resolver")
    }
    assert_eq(integer.name(), "ints[2]")
    assert_eq(integer.type_name(), Some("int"))
    assert_eq(integer.value(), "30")
    assert_true(integer.content() is @moondbg.VariableLeaf)

    assert_true(
      session.find_variable(
        @moondbg.VariablePath::new("arr", [@moondbg.Index(3)]),
      )
      is @moondbg.VariableLookupFailed(
        @moondbg.VariableIndexOutOfBounds("arr", 3, 3)
      ),
    )
    assert_true(
      session.find_variable(
        @moondbg.VariablePath::new("point", [@moondbg.Index(0)]),
      )
      is @moondbg.VariableLookupFailed(
        @moondbg.VariableIndexAccessOnNonCollection(
          "point",
          0,
          Some("example/geometry/Point &")
        )
      ),
    )
    assert_true(
      session.find_variable(
        @moondbg.VariablePath::new("empty", [@moondbg.Index(0)]),
      )
      is @moondbg.VariableLookupFailed(
        @moondbg.VariableIndexOutOfBounds("empty", 0, 0)
      ),
    )

    guard session.next() is @moondbg.Stopped(_) else {
      fail("next should establish a new indexed-path stop epoch")
    }
    guard session.find_variable(arr_element_path)
      is @moondbg.VariableFound(next_point) else {
      fail("the indexed element should be evaluated again after resume")
    }
    assert_eq(next_point, point)
    assert_eq(transport.remaining_inputs(), 0)

    let sent = transport.sent_messages()
    let evaluations = sent.filter_map(message => {
      match message {
        {
          "command": String("evaluate"),
          "arguments": {
            "expression": String(expression),
            "context": String(context),
            "frameId": Number(frame_id, ..),
            ..
          },
          ..
        } => Some((expression, context, frame_id.to_int()))
        _ => None
      }
    })
    assert_eq(evaluations, [
      ("adapter.arr.body[0]", "watch", 140),
      ("adapter.lines.body[0]", "watch", 140),
      ("trusted.box.body[0]", "watch", 140),
      ("trusted.ints.body[2]", "watch", 140),
      ("adapter.arr.body[0]", "watch", 141),
    ])
    assert_false(
      evaluations.any(item => {
        item.0.contains("box.points") || item.0.contains("arr[0].x")
      }),
    )
  })
}

///|
async fn indexed_path_failure_message(mode : IndexedPathFailureMode) -> String {
  @async.with_task_group(async fn(group) {
    let transport = @dap_testkit.ScriptedTransport::new(
      indexed_path_failure_script(mode),
    )
    let lldb_session = LldbDapSession::start_with_dispatcher_factory(
      group,
      () => @dap.DapDispatcher::from_transport(transport.as_transport()),
      preparation_timeout_ms=10000,
    )
    let backend = LldbDapBackend::{ session: lldb_session, }
    let session = @moondbg.DebugSession::new(
      "/tmp/index-failure-program", backend,
    )
    defer session.close()
    session.run() |> ignore
    guard backend.session.execution is Some(execution) &&
      execution.machine.current_stop_epoch() is Some(epoch) else {
      fail("scripted index failure should retain one stopped execution")
    }
    execution.variable_cache.select_frame(epoch, 0)
    let message = try {
      execution
      .variable_inspector()
      .find_variable_inner(
        VariableCacheIdentity::{ epoch, frame_index: 0, },
        150,
        @moondbg.VariablePath::new("arr", [@moondbg.Index(0)]),
      )
      |> ignore
      fail("indexed path failure script should reject its element")
    } catch {
      InvalidIndexedElementValue(message) => message
      error => fail("unexpected indexed path error: \{@debug.to_string(error)}")
    }
    assert_eq(transport.remaining_inputs(), 0)
    let evaluate_count = transport
      .sent_messages()
      .filter_map(sent_command)
      .filter(command => command == "evaluate")
      .length()
    match mode {
      MissingEvaluateName => assert_eq(evaluate_count, 0)
      _ => assert_eq(evaluate_count, 1)
    }
    message
  })
}

///|
async test "lldb-dap reports stable indexed evaluate and protocol failures" {
  let missing_name = indexed_path_failure_message(MissingEvaluateName)
  assert_true(missing_name.contains("no evaluateName"))
  let failed = indexed_path_failure_message(FailedEvaluate)
  assert_true(failed.contains("could not evaluate indexed element"))
  assert_true(failed.contains("expression is unavailable"))
  let malformed = indexed_path_failure_message(MalformedEvaluate)
  assert_true(malformed.contains("incomplete indexed element"))
  let malformed_memory = indexed_path_failure_message(
    MalformedEvaluateMemoryReference,
  )
  assert_true(malformed_memory.contains("malformed indexed element memory"))
  let unavailable = indexed_path_failure_message(UnavailableEvaluate)
  assert_true(unavailable.contains("arr[0]"))
  assert_true(unavailable.contains("unavailable at the current location"))
  let unexpandable = indexed_path_failure_message(UnexpandableEvaluate)
  assert_true(unexpandable.contains("arr[0]"))
  assert_true(unexpandable.contains("no expandable value"))
}

///|
async test "lldb-dap materializes only the active enum constructor shallowly" {
  @async.with_task_group(async fn(group) {
    let transport = @dap_testkit.ScriptedTransport::new(
      boxed_enum_variable_script(),
    )
    let lldb_session = LldbDapSession::start_with_dispatcher_factory(
      group,
      () => @dap.DapDispatcher::from_transport(transport.as_transport()),
      preparation_timeout_ms=10000,
    )
    let backend = LldbDapBackend::{ session: lldb_session, }
    let session = @moondbg.DebugSession::new("/tmp/enum-program", backend)
    defer session.close()
    guard session.run() is @moondbg.Stopped(_) else {
      fail("scripted enum execution should stop")
    }
    guard session.find_variable(@moondbg.VariablePath::root("empty"))
      is @moondbg.VariableFound(empty) &&
      empty.content() is @moondbg.VariableEnum(empty_value) else {
      fail("payloadless enum should expose its active constructor")
    }
    assert_eq(empty.value(), "")
    assert_eq(empty_value.constructor_name(), "Empty")
    assert_true(empty_value.payload() is [])

    guard session.find_variable(@moondbg.VariablePath::root("scalar"))
      is @moondbg.VariableFound(scalar) &&
      scalar.content() is @moondbg.VariableEnum(scalar_value) &&
      scalar_value.payload() is [scalar_payload] else {
      fail("scalar enum payload should retain its DAP scalar value")
    }
    assert_eq(scalar_value.constructor_name(), "B")
    assert_eq(scalar_payload.position(), 0)
    assert_eq(scalar_payload.type_name(), "Int")
    assert_eq(scalar_payload.scalar_value(), Some("7"))

    guard session.find_variable(@moondbg.VariablePath::root("list"))
      is @moondbg.VariableFound(list) &&
      list.content() is @moondbg.VariableEnum(list_value) &&
      list_value.payload() is [head, tail] else {
      fail("Cons should expose only its direct payload")
    }
    assert_eq(list_value.constructor_name(), "Cons")
    assert_eq(head.type_name(), "Int")
    assert_eq(head.scalar_value(), Some("3"))
    assert_eq(tail.position(), 1)
    assert_eq(tail.type_name(), "List")
    assert_eq(tail.scalar_value(), None)
    guard session.find_variable(@moondbg.VariablePath::root("list"))
      is @moondbg.VariableFound(cached_list) else {
      fail("same-stop enum lookup should use its snapshot cache")
    }
    assert_eq(cached_list, list)

    guard session.find_variable(@moondbg.VariablePath::root("pair"))
      is @moondbg.VariableFound(pair) &&
      pair.content() is @moondbg.VariableEnum(pair_value) &&
      pair_value.payload() is [left, right] else {
      fail("C(Double, Int) should retain both scalar payloads")
    }
    assert_eq(pair_value.constructor_name(), "C")
    assert_eq(left.type_name(), "Double")
    assert_eq(left.scalar_value(), Some("1.5"))
    assert_eq(right.type_name(), "Int")
    assert_eq(right.scalar_value(), Some("2"))

    guard session.find_variable(@moondbg.VariablePath::root("unknown"))
      is @moondbg.VariableFound(unknown) else {
      fail("unknown non-enum aggregate should remain printable")
    }
    assert_true(unknown.content() is @moondbg.VariableLeaf)
    assert_eq(unknown.value(), "opaque")

    assert_eq(transport.remaining_inputs(), 0)
    let sent = transport.sent_messages()
    assert_eq(sent.filter_map(sent_command), [
      "initialize", "launch", "configurationDone", "stackTrace", "scopes", "variables",
      "variables", "readMemory", "variables", "variables", "readMemory", "variables",
      "variables", "readMemory", "variables", "variables", "readMemory", "variables",
      "variables",
    ])
    assert_false(sent.any(message => sent_command(message) == Some("evaluate")))
    assert_false(
      sent.any(message => {
        message
        is { "arguments": { "variablesReference": Number(439, ..), .. }, .. }
      }),
    )
    assert_true(
      sent[13]
      is {
        "arguments": {
          "memoryReference": String("0x0000000000003000"),
          "offset": Number(-4, ..),
          "count": Number(4, ..),
          ..
        },
        ..
      },
    )
  })
}

///|
async test "lldb-dap rejects malformed enum protocol instead of guessing" {
  @async.with_task_group(async fn(group) {
    let transport = @dap_testkit.ScriptedTransport::new(
      malformed_boxed_enum_script(),
    )
    let lldb_session = LldbDapSession::start_with_dispatcher_factory(
      group,
      () => @dap.DapDispatcher::from_transport(transport.as_transport()),
      preparation_timeout_ms=10000,
    )
    let backend = LldbDapBackend::{ session: lldb_session, }
    let session = @moondbg.DebugSession::new(
      "/tmp/malformed-enum-program", backend,
    )
    defer session.close()
    guard session.run() is @moondbg.Stopped(_) &&
      backend.session.execution is Some(execution) &&
      execution.machine.current_stop_epoch() is Some(epoch) else {
      fail("malformed enum fixture should retain one stopped execution")
    }
    execution.variable_cache.select_frame(epoch, 0)
    let cases = [
      ("unknown_tag", "unknown tag 1"),
      ("duplicate_tag", "repeats tag 0"),
      ("illegal_tag", "does not end in a decimal tag"),
      ("bad_pointer", "malformed payload pointer"),
      ("duplicate_marker", "exactly one moonbit.enum marker"),
      ("unreadable", "failed to read boxed enum descriptor"),
    ]
    for _, case in cases {
      let (name, expected) = case
      let rejected = try {
        execution
        .variable_inspector()
        .find_variable_inner(
          VariableCacheIdentity::{ epoch, frame_index: 0, },
          140,
          @moondbg.VariablePath::root(name),
        )
        |> ignore
        false
      } catch {
        InvalidEnumValue(message) => message.contains(expected)
        _ => false
      }
      assert_true(rejected)
    }
    assert_eq(transport.remaining_inputs(), 0)
    let sent = transport.sent_messages()
    assert_eq(sent.filter_map(sent_command), [
      "initialize", "launch", "configurationDone", "stackTrace", "scopes", "variables",
      "variables", "readMemory", "variables", "variables", "variables", "variables",
      "variables", "readMemory",
    ])
    assert_false(sent.any(message => sent_command(message) == Some("evaluate")))
    assert_true(
      sent[7]
      is {
        "arguments": {
          "memoryReference": String("0x5000"),
          "offset": Number(-4, ..),
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
    let backend = LldbDapBackend::{ session: lldb_session, }
    let session = @moondbg.DebugSession::new("/tmp/truncated-program", backend)
    defer session.close()
    session.run() |> ignore
    guard backend.session.execution is Some(execution) &&
      execution.machine.current_stop_epoch() is Some(epoch) else {
      fail("scripted execution should retain one stop epoch")
    }
    execution.variable_cache.select_frame(epoch, 0)
    let line = DapVariable::{
      name: "line1",
      value: "0x1000",
      type_name: Some("example/geometry/Line &"),
      variables_reference: 101,
      evaluate_name: None,
    }
    let snapshot = execution
      .variable_inspector()
      .materialize_variable_with_limits(
        VariableCacheIdentity::{ epoch, frame_index: 0, },
        line,
        8,
        2,
      )
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
    let depth_limited = execution
      .variable_inspector()
      .materialize_variable_with_limits(
        VariableCacheIdentity::{ epoch, frame_index: 0, },
        line,
        0,
        10,
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
    let backend = LldbDapBackend::{ session: lldb_session, }
    let session = @moondbg.DebugSession::new("/tmp/cyclic-program", backend)
    defer session.close()
    session.run() |> ignore
    guard backend.session.execution is Some(execution) &&
      execution.machine.current_stop_epoch() is Some(epoch) else {
      fail("scripted execution should retain one stop epoch")
    }
    execution.variable_cache.select_frame(epoch, 0)
    let node = DapVariable::{
      name: "node",
      value: "0x1000",
      type_name: Some("example/Node &"),
      variables_reference: 101,
      evaluate_name: None,
    }
    let snapshot = execution
      .variable_inspector()
      .materialize_variable_with_limits(
        VariableCacheIdentity::{ epoch, frame_index: 0, },
        node,
        8,
        10,
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
