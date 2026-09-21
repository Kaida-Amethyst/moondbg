///|
async test "compound conditions preserve precedence parentheses and genuinely short circuit" {
  for
    (text, expected, names) in [
      ("i >= 3 && i < 8", true, ["i", "i"]),
      ("i < 3 && missing == 0", false, ["i"]),
      ("i >= 3 || missing == 0", true, ["i"]),
      ("!(i == 0)", true, ["i"]),
      ("!!(i == 0)", false, ["i"]),
      ("i == 5 || i < 3 && missing == 0", true, ["i"]),
      ("(i == 5 || i < 3) && i == 0", false, ["i", "i"]),
      ("i == 0 || i == 5 && !(i < 4)", true, ["i", "i", "i"]),
      ("i != 5 && flag < other", false, ["i"]),
    ] {
    let reads : Array[String] = []
    let read : async (VariablePath) -> ScalarValue = path => {
      reads.push(path.display_name())
      guard path.root_name() == "i" else { fail("Unexpected read") }
      IntValue(5)
    }
    let parsed = Condition::parse(text)
    assert_eq(parsed.evaluate(read), expected, msg=text)
    assert_eq(reads, names, msg=text)
    assert_eq(Condition::parse(parsed.text).evaluate(read), expected)
  }
}

///|
async test "reachable failures propagate but skipped runtime type checks do not run" {
  for
    text in [
      "i == 5 && missing == 0", "i != 5 || missing == 0", "!(missing == 0)",
    ] {
    let result = try {
      Condition::parse(text).evaluate(path => {
        guard path.root_name() == "i" else { raise ConditionError("missing") }
        IntValue(5)
      })
      |> ignore
      false
    } catch {
      ConditionError(message) => message == "missing"
      _ => false
    }
    assert_true(result, msg=text)
  }
  assert_true(
    Condition::parse("i == 5 || flag < other").evaluate(path => {
      if path.root_name() == "i" {
        IntValue(5)
      } else {
        BoolValue(true)
      }
    }),
  )
}

///|
test "compound parsing validates skipped syntax and bounds nesting and node count" {
  for
    text in [
      "i == 5 || x = 0",
      "i == 5 &&",
      "|| i == 0",
      "()",
      "(i == 0",
      "i == 0)",
      "i == 0 & i < 1",
      "i == 0 | i < 1",
      "i == 0 &&& i < 1",
      "!",
      "!(i == 0))",
      "i == 0 || call() == 0",
      "i == 0 || arr[i] == 0",
      "!i == 0",
      "(".repeat(66) + "i == 0" + ")".repeat(66),
      "i == 0 || ".repeat(260) + "i == 0",
    ] {
    assert_true(
      try {
        Condition::parse(text) |> ignore
        false
      } catch {
        _ => true
      },
      msg=text,
    )
  }
}
