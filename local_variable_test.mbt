///|
test "local snapshots distinguish empty and unavailable scopes" {
  let thread = ThreadSelection::initial()
  let frames = [
    StackFrameSnapshot::new(
      0,
      "zero",
      "zero",
      None,
      None,
      None,
      None,
      UnknownFrame,
    ),
    StackFrameSnapshot::new(
      1,
      "one",
      "one",
      None,
      None,
      None,
      None,
      UnknownFrame,
    ),
    StackFrameSnapshot::new(
      2,
      "two",
      "two",
      None,
      None,
      None,
      None,
      MoonBitUserFrame,
    ),
  ]
  let frame = StackSnapshot::new(thread, frames, 0, 3, Some(3), true)
    .selection(2)
    .unwrap()
  let empty = LocalVariablesSnapshot::available(thread, frame, [])
  assert_eq(empty.thread(), thread)
  assert_eq(empty.frame(), frame)
  assert_eq(empty.scope_availability(), LocalScopeAvailable)
  assert_eq(empty.variables().length(), 0)
  let unavailable = LocalVariablesSnapshot::scope_unavailable(thread, frame)
  assert_eq(unavailable.thread(), thread)
  assert_eq(unavailable.frame(), frame)
  assert_eq(unavailable.scope_availability(), LocalScopeUnavailable)
  assert_eq(unavailable.variables().length(), 0)
}

///|
test "local variable summary keeps source type availability and compact kind" {
  let summary = LocalVariableSnapshot::new(
    "items",
    Some("Array[Int]"),
    LocalVariableAvailable(LocalCollection(ArrayCollection, 3)),
  )
  assert_eq(summary.name(), "items")
  assert_eq(summary.type_name(), Some("Array[Int]"))
  assert_eq(
    summary.availability(),
    LocalVariableAvailable(LocalCollection(ArrayCollection, 3)),
  )
}
