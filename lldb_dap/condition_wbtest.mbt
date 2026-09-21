///|
test "condition bindings retain unrelated stops and use all co-located conditions" {
  let bindings = BreakpointConditions::new()
  let first = @expression.IntCondition::parse("i == 7")
  let second = @expression.IntCondition::parse("i < 2")
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
    @expression.IntCondition::parse("i < 2"),
    @expression.IntCondition::parse("i == 7"),
  ]
  assert_eq(inspector.test_conditions(10, conditions), Ok(true))
  assert_eq(inspector.read_condition_int(10, "min"), -2147483648)
  assert_eq(inspector.test_conditions(10, [conditions[0]]), Ok(false))
  for text in ["missing == 0", "double == 7", "gone == 0"] {
    assert_true(
      inspector.test_conditions(10, [
        conditions[1],
        @expression.IntCondition::parse(text),
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
