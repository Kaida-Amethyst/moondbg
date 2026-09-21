///|
test "condition bindings retain unrelated stops and use all co-located conditions" {
  let bindings = BreakpointConditions::new()
  let first = @expression.Condition::parse("i == 7")
  let second = @expression.Condition::parse("i < 2")
  bindings.replace("/a.mbt", [(1, Some(first)), (2, None)])
  bindings.replace("/b.mbt", [(3, Some(second))])
  assert_eq(
    bindings.for_stop({ "reason": "breakpoint", "hitBreakpointIds": [1, 3] }),
    Some([first, second]),
  )
  let preserved : Array[Json] = [
    { "reason": "breakpoint", "hitBreakpointIds": [1, 2] },
    { "reason": "breakpoint", "hitBreakpointIds": [1, 999] },
    { "reason": "breakpoint", "hitBreakpointIds": [] },
    { "reason": "breakpoint" },
    { "reason": "exception", "hitBreakpointIds": [1] },
    { "reason": "pause", "hitBreakpointIds": [1] },
    { "reason": "step", "hitBreakpointIds": [1] },
  ]
  for stop in preserved {
    assert_true(bindings.for_stop(stop) is None, msg=stop.stringify())
  }
  bindings.replace("/b.mbt", [(1, None)])
  assert_true(
    bindings.for_stop({ "reason": "breakpoint", "hitBreakpointIds": [1] })
    is None,
  )
  bindings.replace("/b.mbt", [])
  assert_eq(
    bindings.for_stop({ "reason": "breakpoint", "hitBreakpointIds": [1] }),
    Some([first]),
  )
  bindings.replace("/a.mbt", [])
  assert_true(
    bindings.for_stop({ "reason": "breakpoint", "hitBreakpointIds": [1] })
    is None,
  )
}

///|
async test "condition evaluation uses typed raw Int values and never evaluates user code" {
  let calls = []
  let inspector = VariableInspector::new(
    (command, _) => {
      calls.push(command)
      tree_reply(
        command,
        match command {
          "scopes" =>
            { "scopes": [{ "name": "Locals", "variablesReference": 100 }] }
          "variables" =>
            {
              "variables": [
                {
                  "name": "i",
                  "type": "int",
                  "value": "7",
                  "variablesReference": 0,
                },
                {
                  "name": "min",
                  "type": "int32_t",
                  "value": "-2147483648",
                  "variablesReference": 0,
                },
                {
                  "name": "double",
                  "type": "double",
                  "value": "7",
                  "variablesReference": 0,
                },
                {
                  "name": "gone",
                  "type": "int",
                  "value": "<unavailable>",
                  "variablesReference": 0,
                },
              ],
            }
          _ => fail("Unexpected request: \{command}")
        },
      )
    },
    () => Some(1),
    {},
  )
  let conditions = [
    @expression.Condition::parse("i < 2"),
    @expression.Condition::parse("i == 7"),
  ]
  assert_eq(inspector.test_conditions(10, conditions), Ok(true))
  assert_eq(
    inspector.read_scalar(10, @debugger.VariablePath::root("min")),
    @expression.IntValue(-2147483648),
  )
  assert_eq(inspector.test_conditions(10, [conditions[0]]), Ok(false))
  for text in ["missing == 0", "double == 7", "gone == 0"] {
    assert_true(
      inspector.test_conditions(10, [
        conditions[1],
        @expression.Condition::parse(text),
      ])
      is Err(message) &&
      message.contains(text),
      msg=text,
    )
  }
  assert_true(
    calls.all(command => command == "scopes" || command == "variables"),
  )
}

///|
async test "shared scalar reader traverses fields and rejects stale or non-scalar values" {
  let mut epoch = Some(1)
  let inspector = VariableInspector::new(
    (command, args) => {
      tree_reply(
        command,
        match command {
          "scopes" =>
            { "scopes": [{ "name": "Locals", "variablesReference": 100 }] }
          "variables" =>
            match json_int_field(args, "variablesReference") {
              Some(100) =>
                {
                  "variables": [
                    {
                      "name": "point",
                      "type": "example/Point &",
                      "value": "0x123",
                      "variablesReference": 101,
                    },
                    {
                      "name": "limit",
                      "type": "unsigned int",
                      "value": "7",
                      "variablesReference": 0,
                    },
                    {
                      "name": "flag",
                      "type": "bool",
                      "value": "true",
                      "variablesReference": 0,
                    },
                    {
                      "name": "stale",
                      "type": "example/Point &",
                      "value": "0x456",
                      "variablesReference": 102,
                    },
                  ],
                }
              Some(101) =>
                {
                  "variables": [
                    {
                      "name": "x",
                      "type": "int",
                      "value": "7",
                      "variablesReference": 0,
                    },
                  ],
                }
              Some(102) => {
                epoch = None
                {
                  "variables": [
                    {
                      "name": "x",
                      "type": "int",
                      "value": "7",
                      "variablesReference": 0,
                    },
                  ],
                }
              }
              _ => fail(args.stringify())
            }
          _ => fail(command)
        },
      )
    },
    () => epoch,
    {},
  )
  assert_eq(
    inspector.read_scalar(
      10,
      @debugger.VariablePath::with_fields("point", ["x"]),
    ),
    @expression.IntValue(7),
  )
  assert_eq(
    inspector.read_scalar(10, @debugger.VariablePath::root("flag")),
    @expression.BoolValue(true),
  )
  for
    (text, fragment) in [
      ("point.x == limit", "type mismatch"),
      ("point == point", "Unsupported"),
      ("point.x == missing", "missing"),
      ("point.missing == 0", "missing"),
    ] {
    assert_true(
      inspector.test_conditions(10, [@expression.Condition::parse(text)])
      is Err(message) &&
      message.contains(fragment),
      msg=text,
    )
  }
  assert_true(
    inspector.test_conditions(10, [@expression.Condition::parse("stale.x == 7")])
    is Err(_),
  )
}

///|
async test "scalar reader rejects manually constructed invalid paths before backend IO" {
  let inspector = VariableInspector::new(
    (command, _) => fail("Unexpected backend request: \{command}"),
    () => Some(1),
    {},
  )
  for
    path in [
      @debugger.VariablePath::root("f()"),
      @debugger.VariablePath::with_fields("point", ["x + 1"]),
      @debugger.VariablePath::new("arr", [@debugger.VariablePathStep::Index(-1)]),
    ] {
    assert_true(
      try {
        inspector.read_scalar(10, path) |> ignore
        false
      } catch {
        @expression.ConditionError(message) =>
          message == "Invalid variable path"
        _ => false
      },
    )
  }
}

///|
test "function conditions share hit IDs safely with source and duplicate logical breakpoints" {
  let bindings = BreakpointConditions::new()
  let first = @expression.Condition::parse("i > 3 && i < 8")
  let second = @expression.Condition::parse("i == 0")
  let stop : Json = { "reason": "breakpoint", "hitBreakpointIds": [9] }
  bindings.replace_functions([(9, Some(first)), (9, Some(second))])
  assert_eq(bindings.for_stop(stop), Some([first, second]))
  bindings.replace("/main.mbt", [(9, None)])
  assert_eq(bindings.for_stop(stop), None)
  bindings.replace("/main.mbt", [])
  bindings.replace_functions([(9, Some(first)), (9, None)])
  assert_eq(bindings.for_stop(stop), None)
  bindings.replace_functions([])
  assert_eq(bindings.for_stop(stop), None)
}
