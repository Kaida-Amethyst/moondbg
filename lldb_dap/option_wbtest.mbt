///|
fn option_test_variable(
  name : String,
  ty : String,
  value : String,
) -> DapVariable {
  {
    name,
    value,
    type_name: Some(ty),
    variables_reference: 0,
    evaluate_name: None,
  }
}

///|
test "Option contract discriminates Some and None without guessing bare values" {
  let option = option_test_variable(
    "value", "moonbitlang/core/option/Option[Int]", "",
  )
  let marker = option_test_variable(
    "__moonbit_option_v1_i64_4294967296", "unsigned long long", "7",
  )
  let payload = option_test_variable(".0", "int", "7")
  assert_true(
    optimized_option_members(option, [marker, payload])
    is Some(("Some", [value])) &&
    value.value == "7",
  )
  // The invalid overlapping payload of None is intentionally never consumed.
  let absent = { ..marker, value: "4294967296", }
  let unavailable = { ..payload, value: "<unavailable>", }
  assert_true(
    optimized_option_members(option, [absent, unavailable])
    is Some(("None", [])),
  )
  assert_true(optimized_option_members(payload, []) is None)
  let reference = option_test_variable(
    "value", "moonbitlang/core/option/Option[Point]", "",
  )
  let null = option_test_variable(
    "__moonbit_option_v1_null", "unsigned long long", "0",
  )
  assert_true(
    optimized_option_members(reference, [null, unavailable])
    is Some(("None", [])),
  )
}

///|
test "invalid or unsupported Option metadata fails explicitly" {
  let option = option_test_variable(
    "value", "moonbitlang/core/option/Option[Int]", "",
  )
  let marker = option_test_variable(
    "__moonbit_option_v1_i64_4294967296", "unsigned long long", "7",
  )
  let payload = option_test_variable(".0", "int", "7")
  for
    children in [
      [marker],
      [marker, marker, payload],
      [{ ..marker, name: "__moonbit_option_v2_null", }, payload],
      [{ ..marker, value: "<unavailable>", }, payload],
      [{ ..marker, value: "-1", }, payload],
      [{ ..marker, value: "4294967297", }, payload],
      [{ ..marker, type_name: Some("int"), }, payload],
      [marker, { ..payload, name: ".1", }],
      [marker, { ..payload, value: "<unavailable>", }],
    ] {
    let failed = try {
      optimized_option_members(option, children) |> ignore
      false
    } catch {
      VariableEvaluationError(_) => true
      error => raise error
    }
    assert_true(
      failed,
      msg=children.map(child => "\{child.name}=\{child.value}").join(", "),
    )
  }
}

///|
async test "None tree never fetches its invalid pointer payload" {
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
                    "name": "absent",
                    "type": "moonbitlang/core/option/Option[Point]",
                    "value": "Option",
                    "variablesReference": 2,
                  },
                ],
              }
            Some(2) =>
              {
                "variables": [
                  {
                    "name": "__moonbit_option_v1_null",
                    "type": "unsigned long long",
                    "value": "0",
                    "variablesReference": 0,
                  },
                  {
                    "name": ".0",
                    "type": "Point &",
                    "value": "<unavailable>",
                    "variablesReference": 99,
                  },
                ],
              }
            _ => fail("Must not fetch None's payload: \{args.stringify()}")
          }
        _ => fail(command)
      }
      tree_reply(command, body)
    },
    () => Some(1),
    {},
  )
  let locals = inspector.tree_locals(10)
  assert_eq(locals[0].value, "None")
  assert_true(
    inspector.tree_children(10, locals[0], start=0, count=100).is_empty(),
  )
  let failed = try {
    inspector.tree_evaluate(
      10,
      @debugger.VariablePath::parse("absent.0").unwrap(),
    )
    |> ignore
    false
  } catch {
    VariableEvaluationError(_) => true
    error => raise error
  }
  assert_true(failed)
}
