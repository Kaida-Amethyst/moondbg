///|
test "variable snapshot represents a leaf without adapter state" {
  let leaf = @moondbg.VariableSnapshot::new("answer", "42", Some("Int"))
  assert_eq(leaf.name(), "answer")
  assert_eq(leaf.value(), "42")
  assert_eq(leaf.type_name(), Some("Int"))
  assert_true(leaf.content() is @moondbg.VariableLeaf)
}

///|
test "variable snapshot represents empty and populated structures" {
  let empty = @moondbg.VariableSnapshot::expanded(
    "empty",
    "0x10",
    Some("example/Empty &"),
    [],
  )
  guard empty.content() is @moondbg.VariableStructure(empty_structure) else {
    fail("empty should be represented as a structure")
  }
  assert_false(empty_structure.is_truncated())
  assert_eq(empty_structure.children().length(), 0)
  let point = @moondbg.VariableSnapshot::expanded(
    "point",
    "0x20",
    Some("example/Point &"),
    [
      @moondbg.VariableSnapshot::new("x", "1", Some("double")),
      @moondbg.VariableSnapshot::new("y", "2", Some("double")),
    ],
  )
  guard point.content() is @moondbg.VariableStructure(point_structure) &&
    point_structure.children() is [x, y] else {
    fail("point should contain two materialized fields")
  }
  assert_eq(x.name(), "x")
  assert_eq(y.name(), "y")
}

///|
test "variable snapshot owns its read-only structure children" {
  let children = [@moondbg.VariableSnapshot::new("value", "1", Some("int32_t"))]
  let snapshot = @moondbg.VariableSnapshot::expanded(
    "box",
    "0x10",
    Some("example/Box &"),
    children,
  )
  children.clear()
  guard snapshot.content() is @moondbg.VariableStructure(structure) &&
    structure.children() is [value] else {
    fail("mutating the constructor input must not change the snapshot")
  }
  assert_eq(value.name(), "value")
}

///|
test "enum snapshot retains ordered shallow payload without adapter state" {
  let payload = [
    @moondbg.VariableEnumPayload::scalar(0, "Int", "3"),
    @moondbg.VariableEnumPayload::aggregate(1, "List"),
  ]
  let enum_value = @moondbg.VariableEnumSnapshot::new("Cons", payload)
  payload.clear()
  let snapshot = @moondbg.VariableSnapshot::enum_value(
    "list",
    Some("example/list/List"),
    enum_value,
  )
  guard snapshot.content() is @moondbg.VariableEnum(active) &&
    active.payload() is [head, tail] else {
    fail("enum should retain its active constructor and direct payload")
  }
  assert_eq(snapshot.value(), "")
  assert_eq(active.constructor_name(), "Cons")
  assert_eq(head.position(), 0)
  assert_eq(head.type_name(), "Int")
  assert_eq(head.scalar_value(), Some("3"))
  assert_eq(tail.position(), 1)
  assert_eq(tail.type_name(), "List")
  assert_eq(tail.scalar_value(), None)
}

///|
test "enum snapshot rejects malformed constructor and payload metadata" {
  assert_true(
    try {
      @moondbg.VariableEnumSnapshot::new("", []) |> ignore
      false
    } catch {
      @moondbg.InvalidEnumConstructor("") => true
      _ => false
    },
  )
  assert_true(
    try {
      @moondbg.VariableEnumSnapshot::new("C", [
        @moondbg.VariableEnumPayload::scalar(1, "Int", "1"),
      ])
      |> ignore
      false
    } catch {
      @moondbg.InvalidEnumPayloadPosition(expected=0, actual=1) => true
      _ => false
    },
  )
  assert_true(
    try {
      @moondbg.VariableEnumSnapshot::new("C", [
        @moondbg.VariableEnumPayload::aggregate(0, ""),
      ])
      |> ignore
      false
    } catch {
      @moondbg.InvalidEnumPayloadType(position=0, type_name="") => true
      _ => false
    },
  )
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
  guard line.content() is @moondbg.VariableStructure(line_structure) &&
    line_structure.children() is [start] &&
    start.content() is @moondbg.VariableStructure(point_structure) &&
    point_structure.children() is [x] else {
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
    truncated.content() is @moondbg.VariableStructure(structure) &&
    structure.is_truncated() &&
    structure.children() is [materialized] &&
    materialized.name() == "start",
  )
}

///|
test "indexed collection snapshot retains indices values and omission count" {
  let elements = [
    @moondbg.IndexedVariableElement::with_value(
      0,
      @moondbg.VariableSnapshot::new("[0]", "1", Some("Int")),
    ),
    @moondbg.IndexedVariableElement::with_value(
      1,
      @moondbg.VariableSnapshot::new("[1]", "2", Some("Int")),
    ),
    @moondbg.IndexedVariableElement::with_value(
      9,
      @moondbg.VariableSnapshot::new("[9]", "10", Some("Int")),
    ),
  ]
  let collection = @moondbg.IndexedCollectionSnapshot::new(
    @moondbg.FixedArrayCollection,
    "Int",
    10,
    elements,
  )
  elements.clear()
  let array = @moondbg.VariableSnapshot::indexed_collection(
    "arr",
    "moonbit.array_i32 @ 0x1000",
    Some("moonbit.array_i32"),
    collection,
  )
  guard array.content() is @moondbg.VariableIndexedCollection(indexed) &&
    indexed.preview_elements() is [first, second, last] &&
    first.value() is Some(first_value) &&
    last.value() is Some(last_value) else {
    fail("array should retain its structured indexed preview")
  }
  assert_eq(indexed.element_type_name(), "Int")
  assert_eq(indexed.kind(), @moondbg.FixedArrayCollection)
  assert_eq(indexed.total_length(), 10)
  assert_eq(indexed.omitted_count(), 7)
  assert_false(indexed.is_complete())
  assert_eq(first.index(), 0)
  assert_eq(first_value.value(), "1")
  assert_eq(second.index(), 1)
  assert_eq(last.index(), 9)
  assert_eq(last_value.value(), "10")
}

///|
test "indexed collection snapshot represents empty complete and placeholder previews" {
  let empty = @moondbg.IndexedCollectionSnapshot::new(
    @moondbg.ArrayCollection,
    "Int",
    0,
    [],
  )
  assert_eq(empty.kind(), @moondbg.ArrayCollection)
  assert_true(empty.is_complete())
  assert_eq(empty.omitted_count(), 0)
  let points = @moondbg.IndexedCollectionSnapshot::new(
    @moondbg.FixedArrayCollection,
    "Point",
    100,
    [
      @moondbg.IndexedVariableElement::placeholder(0),
      @moondbg.IndexedVariableElement::placeholder(1),
      @moondbg.IndexedVariableElement::placeholder(99),
    ],
  )
  guard points.preview_elements() is [first, second, last] else {
    fail("point preview should preserve three selected indices")
  }
  assert_eq(points.omitted_count(), 97)
  assert_true(first.value() is None)
  assert_eq(second.index(), 1)
  assert_eq(last.index(), 99)
}

///|
test "indexed collection snapshot rejects invalid metadata" {
  let empty_type_rejected = try {
    @moondbg.IndexedCollectionSnapshot::new(
      @moondbg.FixedArrayCollection,
      "",
      0,
      [],
    )
    |> ignore
    false
  } catch {
    @moondbg.InvalidIndexedCollectionElementType("") => true
    _ => false
  }
  assert_true(empty_type_rejected)
  let negative_length_rejected = try {
    @moondbg.IndexedCollectionSnapshot::new(
      @moondbg.FixedArrayCollection,
      "Int",
      -1,
      [],
    )
    |> ignore
    false
  } catch {
    @moondbg.InvalidIndexedCollectionLength(-1) => true
    _ => false
  }
  assert_true(negative_length_rejected)
  let out_of_bounds_rejected = try {
    @moondbg.IndexedCollectionSnapshot::new(
      @moondbg.FixedArrayCollection,
      "Int",
      1,
      [@moondbg.IndexedVariableElement::placeholder(1)],
    )
    |> ignore
    false
  } catch {
    @moondbg.InvalidIndexedCollectionIndex(index=1, total_length=1) => true
    _ => false
  }
  assert_true(out_of_bounds_rejected)
  let unordered_rejected = try {
    @moondbg.IndexedCollectionSnapshot::new(
      @moondbg.FixedArrayCollection,
      "Int",
      3,
      [
        @moondbg.IndexedVariableElement::placeholder(2),
        @moondbg.IndexedVariableElement::placeholder(1),
      ],
    )
    |> ignore
    false
  } catch {
    @moondbg.UnorderedIndexedCollectionIndex(previous=2, index=1) => true
    _ => false
  }
  assert_true(unordered_rejected)
}

///|
test "variable path owns mixed steps and produces a stable display name" {
  let root = @moondbg.VariablePath::root("answer")
  assert_eq(root.root_name(), "answer")
  assert_eq(root.steps().length(), 0)
  assert_eq(root.display_name(), "answer")
  let fields = ["start", "x"]
  let nested = @moondbg.VariablePath::with_fields("line1", fields)
  fields.clear()
  assert_eq(nested.root_name(), "line1")
  assert_true(nested.steps() is [@moondbg.Field("start"), @moondbg.Field("x")])
  assert_eq(nested.display_name(), "line1.start.x")
  let steps = [
    @moondbg.Index(0),
    @moondbg.Field("start"),
    @moondbg.Index(12),
    @moondbg.Field("x"),
  ]
  let mixed = @moondbg.VariablePath::new("lines", steps)
  steps.clear()
  assert_true(
    mixed.steps()
    is [
      @moondbg.Index(0),
      @moondbg.Field("start"),
      @moondbg.Index(12),
      @moondbg.Field("x"),
    ],
  )
  assert_eq(mixed.display_name(), "lines[0].start[12].x")
}

///|
test "variable lookup failures retain structured path context" {
  assert_true(
    @moondbg.VariableLookupResult::not_found("missing")
    is @moondbg.VariableLookupFailed(@moondbg.VariableRootNotFound("missing")),
  )
  guard @moondbg.VariableLookupResult::field_not_found("line1", "start")
    is @moondbg.VariableLookupFailed(field_missing) else {
    fail("expected a structured missing-field failure")
  }
  assert_eq(field_missing.requested_path(), "line1.start")
  guard @moondbg.VariableLookupResult::field_access_on_non_struct(
      "answer",
      "value",
      Some("Int"),
    )
    is @moondbg.VariableLookupFailed(non_struct) else {
    fail("expected a structured non-struct failure")
  }
  assert_eq(non_struct.requested_path(), "answer.value")
  guard @moondbg.VariableLookupResult::index_access_on_non_collection(
      "point",
      0,
      Some("Point"),
    )
    is @moondbg.VariableLookupFailed(non_collection) else {
    fail("expected a structured non-collection failure")
  }
  assert_eq(non_collection.requested_path(), "point[0]")
  guard @moondbg.VariableLookupResult::index_out_of_bounds("arr", 3, 3)
    is @moondbg.VariableLookupFailed(out_of_bounds) else {
    fail("expected a structured out-of-bounds failure")
  }
  assert_eq(out_of_bounds.requested_path(), "arr[3]")
  guard @moondbg.VariableLookupResult::unavailable("line1.start")
    is @moondbg.VariableLookupFailed(unavailable) else {
    fail("expected a structured unavailable failure")
  }
  assert_eq(unavailable.requested_path(), "line1.start")
}
