///|
test "variable snapshot represents a leaf without adapter state" {
  let leaf = @moondbg.VariableSnapshot::new("answer", "42", Some("Int"))
  assert_eq(leaf.name(), "answer")
  assert_eq(leaf.value(), "42")
  assert_eq(leaf.type_name(), Some("Int"))
  assert_true(leaf.expansion() is @moondbg.VariableLeaf)
}

///|
test "variable snapshot represents empty and populated structures" {
  let empty = @moondbg.VariableSnapshot::expanded(
    "empty",
    "0x10",
    Some("example/Empty &"),
    [],
  )
  assert_true(empty.expansion() is @moondbg.VariableExpanded)
  assert_eq(empty.children().length(), 0)
  let point = @moondbg.VariableSnapshot::expanded(
    "point",
    "0x20",
    Some("example/Point &"),
    [
      @moondbg.VariableSnapshot::new("x", "1", Some("double")),
      @moondbg.VariableSnapshot::new("y", "2", Some("double")),
    ],
  )
  guard point.expansion() is @moondbg.VariableExpanded &&
    point.children() is [x, y] else {
    fail("point should contain two materialized fields")
  }
  assert_eq(x.name(), "x")
  assert_eq(y.name(), "y")
}

///|
test "variable snapshot owns its read-only children" {
  let children = [@moondbg.VariableSnapshot::new("value", "1", Some("int32_t"))]
  let snapshot = @moondbg.VariableSnapshot::expanded(
    "box",
    "0x10",
    Some("example/Box &"),
    children,
  )
  children.clear()
  guard snapshot.children() is [value] else {
    fail("mutating the constructor input must not change the snapshot")
  }
  assert_eq(value.name(), "value")
}

///|
test "variable snapshot represents nested and truncated structures" {
  let point = @moondbg.VariableSnapshot::expanded(
    "start",
    "0x20",
    Some("example/Point &"),
    [@moondbg.VariableSnapshot::new("x", "1", Some("double"))],
  )
  let line = @moondbg.VariableSnapshot::expanded(
    "line",
    "0x30",
    Some("example/Line &"),
    [point],
  )
  guard line.expansion() is @moondbg.VariableExpanded &&
    line.children() is [start] &&
    start.expansion() is @moondbg.VariableExpanded &&
    start.children() is [x] else {
    fail("line should retain its nested point field")
  }
  assert_eq(x.value(), "1")
  let truncated = @moondbg.VariableSnapshot::truncated(
    "next",
    "0x40",
    Some("example/Node &"),
    [point],
  )
  assert_true(
    truncated.expansion() is @moondbg.VariableTruncated &&
    truncated.children() is [materialized] &&
    materialized.name() == "start",
  )
}
