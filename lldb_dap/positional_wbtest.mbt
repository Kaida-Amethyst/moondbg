///|
fn positional_test_child(name : String, value : String) -> DapVariable {
  {
    name,
    value,
    type_name: Some("int"),
    variables_reference: 0,
    evaluate_name: None,
  }
}

///|
test "tuple arity respects nested tuples and generic parameters" {
  assert_eq(tuple_arity("(Int, String)"), Some(2))
  assert_eq(
    tuple_arity("((Int, Point), Result[Point, String], Array[(Int, Int)])"),
    Some(3),
  )
  assert_eq(tuple_arity("Point"), None)
  assert_eq(tuple_arity("(Int, Array[Int)"), None)
}

///|
async test "missing tuple metadata is unavailable rather than an empty tuple" {
  let inspector = VariableInspector::new(
    (command, args) => {
      let body : Json = match command {
        "scopes" =>
          { "scopes": [{ "name": "Locals", "variablesReference": 1 }] }
        "variables" =>
          match json_int_field(args, "variablesReference") {
            Some(1) =>
              {
                "variables": [
                  {
                    "name": "pair",
                    "type": "(Int, Int) &",
                    "value": "0x1000",
                    "variablesReference": 0,
                  },
                ],
              }
            _ => fail(args.stringify())
          }
        _ => fail(command)
      }
      tree_reply(command, body)
    },
    () => Some(1),
    {},
  )
  let locals = inspector.tree_locals(10)
  assert_true(locals[0].value.contains("Tuple debug members are unavailable"))
  let failed = try {
    inspector.tree_evaluate(
      10,
      @debugger.VariablePath::parse("pair.0").unwrap(),
    )
    |> ignore
    false
  } catch {
    VariableEvaluationError(_) => true
    error => raise error
  }
  assert_true(failed)
}

///|
test "positions use member names rather than adapter order" {
  let sorted = ordered_position_members([
    positional_test_child(".1", "20"),
    positional_test_child(".0", "10"),
  ])
  assert_eq(sorted.map(item => item.value), ["10", "20"])
  for names in [[".0", ".0"], [".0", ".2"], ["x"], [".-1"], [".2147483648"]] {
    let rejected = try {
      ordered_position_members(
        names.map(name => positional_test_child(name, "0")),
      )
      |> ignore
      false
    } catch {
      VariableEvaluationError(_) => true
      error => raise error
    }
    assert_true(rejected)
  }
}

///|
async test "tuple paths and tree children use the same ordered source members" {
  let inspector = VariableInspector::new(
    (command, args) => {
      let body : Json = match command {
        "scopes" =>
          { "scopes": [{ "name": "Locals", "variablesReference": 1 }] }
        "variables" =>
          match json_int_field(args, "variablesReference") {
            Some(1) =>
              {
                "variables": [
                  {
                    "name": "pair",
                    "type": "(Int, Int) &",
                    "value": "tuple @ 0x1000",
                    "variablesReference": 2,
                  },
                ],
              }
            Some(2) =>
              {
                "variables": [
                  {
                    "name": ".1",
                    "type": "int",
                    "value": "20",
                    "variablesReference": 0,
                  },
                  {
                    "name": ".0",
                    "type": "int",
                    "value": "10",
                    "variablesReference": 0,
                  },
                ],
              }
            _ => fail(args.stringify())
          }
        _ => fail(command)
      }
      tree_reply(command, body)
    },
    () => Some(1),
    {},
  )
  let locals = inspector.tree_locals(10)
  let children = inspector.tree_children(10, locals[0], start=0, count=100)
  assert_eq(children.map(item => item.name), [".0", ".1"])
  for child in children {
    guard child.evaluate_name() is Some(path) else {
      fail("Missing evaluateName")
    }
    let evaluated = inspector.tree_evaluate(
      10,
      @debugger.VariablePath::parse(path).unwrap(),
    )
    assert_eq(evaluated.value, child.value)
  }
  for text in ["pair.2", "pair.x", "pair[0]", "pair.0.0"] {
    let failed = try {
      inspector.tree_evaluate(10, @debugger.VariablePath::parse(text).unwrap())
      |> ignore
      false
    } catch {
      VariableEvaluationError(_) => true
      error => raise error
    }
    assert_true(failed, msg=text)
  }
  let identity = inspector.tree_identity(10)
  let snapshot = inspector.find_variable_inner(
    identity,
    10,
    @debugger.VariablePath::root("pair"),
  )
  assert_true(
    snapshot is @debugger.VariableFound(value) &&
    value.content() is @debugger.VariableTuple(items) &&
    items.children().length() == 2,
  )
  guard inspector.resolve_root_variable(identity, 10, "pair")
    is DapVariableResolved(variable) else {
    fail("tuple root")
  }
  let truncated = inspector.materialize_variable_with_limits(
    identity, variable, 4, 2,
  )
  assert_true(
    truncated.content() is @debugger.VariableTuple(items) &&
    items.is_truncated() &&
    items.children().length() == 1,
  )
  let depth_limited = inspector.materialize_variable_with_limits(
    identity, variable, 0, 100,
  )
  assert_true(
    depth_limited.content() is @debugger.VariableTuple(items) &&
    items.is_truncated() &&
    items.children().is_empty(),
  )
}
