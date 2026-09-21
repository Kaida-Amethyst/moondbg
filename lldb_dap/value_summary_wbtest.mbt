///|
test "summary exact character fit is not marked truncated" {
  let budget = ValueSummaryBudget::new()
  budget.write("🙂".repeat(159))
  budget.write("x")
  assert_eq(budget.text(), "🙂".repeat(159) + "x")
  budget.write("unprinted")
  assert_eq(budget.text(), "🙂".repeat(159) + "…")
}

///|
fn summary_test_variable(
  name : String,
  ty : String,
  reference : Int,
  value? : String = "1",
) -> DapVariable {
  {
    name,
    type_name: Some(ty),
    variables_reference: reference,
    value,
    evaluate_name: None,
  }
}

///|
fn summary_test_inspector(
  graph : Map[Int, Array[DapVariable]],
  requested : Array[Int],
) -> VariableInspector {
  VariableInspector::new(
    (command, args) => {
      assert_eq(command, "variables")
      let reference = json_int_field(args, "variablesReference").unwrap()
      requested.push(reference)
      guard graph.get(reference) is Some(children) else {
        fail("Unexpected summary read: \{reference}")
      }
      tree_reply(command, {
        "variables": children
        .map(child => {
          "name": child.name.to_json(),
          "type": child.type_name.unwrap().to_json(),
          "value": child.value.to_json(),
          "variablesReference": child.variables_reference.to_json(),
        })
        .to_json(),
      })
    },
    () => Some(1),
    {},
  )
}

///|
async test "nested summary expands two composite levels but manual expansion can go deeper" {
  let point = summary_test_variable(".0", "example/Point &", 10)
  let inner = summary_test_variable("inner", "example/Point &", 11)
  let requested = []
  let inspector = summary_test_inspector(
    Map([
      (10, [summary_test_variable("x", "Int", 0), inner]),
      (11, [summary_test_variable("x", "Int", 0, value="42")]),
    ]),
    requested,
  )
  let identity = inspector.tree_identity(1)
  let root = summary_test_variable("item", "example/View", 1)
  assert_eq(
    inspector.positional_summary(identity, root, "Item", [point]),
    "Item(Point { x: 1, inner: Point { … } })",
  )
  assert_eq(requested, [10])
  assert_eq(inspector.value_summary(identity, inner), "Point { x: 42 }")
  assert_eq(requested, [10, 11])
}

///|
async test "summary member limit never visits the omitted fifth child" {
  let requested = []
  let children = Array::makei(5, index => {
    summary_test_variable(".\{index}", "example/Point &", index + 10)
  })
  let graph = Map(
    Array::makei(4, index => {
      (index + 10, [summary_test_variable("x", "Int", 0)])
    }),
  )
  let inspector = summary_test_inspector(graph, requested)
  let root = summary_test_variable("item", "example/View", 1)
  let result = inspector.positional_summary(
    inspector.tree_identity(1),
    root,
    "Many",
    children,
  )
  assert_eq(
    result, "Many(Point { x: 1 }, Point { x: 1 }, Point { x: 1 }, Point { x: 1 }, …)",
  )
  assert_eq(requested, [10, 11, 12, 13])
}

///|
async test "summary node budget is shared by siblings and includes the root" {
  let requested = []
  let children = Array::makei(4, index => {
    summary_test_variable(".\{index}", "example/P &", index + 10)
  })
  let graph = Map(
    Array::makei(4, index => {
      (
        index + 10,
        ["a", "b", "c", "d"].map(name => summary_test_variable(name, "Int", 0)),
      )
    }),
  )
  let inspector = summary_test_inspector(graph, requested)
  let root = summary_test_variable("item", "example/View", 1)
  assert_eq(
    inspector.positional_summary(
      inspector.tree_identity(1),
      root,
      "Many",
      children,
    ),
    "Many(P { a: 1, b: 1, c: 1, d: 1 }, P { a: 1, b: 1, c: 1, d: 1 }, P { a: 1, b: 1, c: 1, d: 1 }, …)",
  )
  assert_eq(requested, [10, 11, 12])
}

///|
async test "summary Unicode character budget stops subsequent adapter reads" {
  let inspector = summary_test_inspector(Map([]), [])
  let root = summary_test_variable("item", "example/View", 1)
  let result = inspector.positional_summary(
    inspector.tree_identity(1),
    root,
    "Text",
    [
      summary_test_variable(".0", "opaque", 0, value="🙂".repeat(500)),
      summary_test_variable(".1", "example/Point &", 99),
    ],
  )
  assert_eq(result.iter().count(), 160)
  assert_true(result.has_suffix("…"))
  assert_true(result.has_prefix("Text(🙂🙂"))
}

///|
async test "summary cycles and unavailable children are explicit and do not cause reads" {
  let root = summary_test_variable("node", "example/Node &", 1)
  let requested = []
  let inspector = summary_test_inspector(
    Map([
      (
        1,
        [
          { ..root, name: "next", },
          summary_test_variable(
            "gone",
            "Int",
            99,
            value="<error: register unavailable>",
          ),
        ],
      ),
    ]),
    requested,
  )
  assert_eq(
    inspector.value_summary(inspector.tree_identity(1), root),
    "Node { next: Node { … }, gone: <unavailable: <error: register unavailable>> }",
  )
  assert_eq(requested, [1])
}

///|
async test "summary arrays read headers but never payloads" {
  let calls = []
  let inspector = VariableInspector::new(
    (command, args) => {
      calls.push(command)
      let body : Json = match command {
        "variables" =>
          {
            "variables": [
              {
                "name": "body",
                "value": "0x1000",
                "type": "int *",
                "variablesReference": 0,
              },
            ],
          }
        "readMemory" => {
          assert_eq(json_int_field(args, "offset"), Some(-8))
          assert_eq(json_int_field(args, "count"), Some(8))
          { "data": "AAAAAAMAAAA=" }
        }
        _ => fail(command)
      }
      tree_reply(command, body)
    },
    () => Some(1),
    { "supportsReadMemoryRequest": true },
  )
  let root = summary_test_variable("item", "example/View", 1)
  let arr = summary_test_variable(".0", "FixedArray[Int]", 10)
  assert_eq(
    inspector.positional_summary(inspector.tree_identity(1), root, "Items", [
      arr,
    ]),
    "Items(FixedArray[Int] with length = 3)",
  )
  assert_eq(calls, ["variables", "readMemory"])
}

///|
async test "nested failed reads preserve their category and do not hide sibling scalars" {
  let inspector = VariableInspector::new(
    (command, _) => {
      if command == "readMemory" {
        raise MemoryReadError("unmapped address")
      }
      tree_reply(command, {
        "variables": [
          {
            "name": "body",
            "value": "0x1000",
            "type": "int *",
            "variablesReference": 0,
          },
        ],
      })
    },
    () => Some(1),
    { "supportsReadMemoryRequest": true },
  )
  let root = summary_test_variable("item", "example/View", 1)
  let arr = summary_test_variable(".0", "FixedArray[Int]", 10)
  assert_eq(
    inspector.positional_summary(inspector.tree_identity(1), root, "Items", [
      arr,
      summary_test_variable(".1", "Int", 0),
    ]),
    "Items(<Memory read failed for '.0': unmapped address>, 1)",
  )
  assert_true(
    inspection_failure("arr", MemoryReadError("unmapped address"))
    is Some(@debugger.VariableMemoryReadFailed("arr", "unmapped address")),
  )
}

///|
async test "a resumed stop invalidates an in-flight summary instead of displaying an error value" {
  let epoch : Ref[Int?] = { val: Some(1), }
  let inspector = VariableInspector::new(
    (command, _) => {
      epoch.val = None
      tree_reply(command, { "variables": [] })
    },
    () => epoch.val,
    {},
  )
  let identity = inspector.tree_identity(10)
  let stale = try {
    inspector.value_summary(
      identity,
      summary_test_variable("point", "example/Point &", 10),
    )
    |> ignore
    false
  } catch {
    StaleVariableResult(..) => true
    error => raise error
  }
  assert_true(stale)
}
