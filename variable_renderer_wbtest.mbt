///|
test "struct variable renderer uses MoonBit names and stable nesting" {
  let line = @debugger.VariableSnapshot::expanded(
    "line1",
    "0x1000",
    Some("example/geometry/Line &"),
    [
      @debugger.VariableSnapshot::expanded(
        "start",
        "0x1100",
        Some("example/geometry/Point &"),
        [
          @debugger.VariableSnapshot::new("x", "1", Some("double")),
          @debugger.VariableSnapshot::new("y", "2", Some("double")),
        ],
      ),
      @debugger.VariableSnapshot::expanded(
        "end",
        "0x1200",
        Some("example/geometry/Point &"),
        [
          @debugger.VariableSnapshot::new("x", "4", Some("double")),
          @debugger.VariableSnapshot::new("y", "6", Some("double")),
        ],
      ),
    ],
  )
  inspect(
    variable_lines(line).join("\n"),
    content=(
      #|line1: Line = {
      #|  start: Point = {
      #|    x: Double = 1
      #|    y: Double = 2
      #|  }
      #|  end: Point = {
      #|    x: Double = 4
      #|    y: Double = 6
      #|  }
      #|}
    ),
  )
}

///|
test "indexed struct pointer rendering keeps the source-facing Point type" {
  let point = @debugger.VariableSnapshot::expanded(
    "arr[0]",
    "0x1010",
    Some("example/geometry/Point *"),
    [
      @debugger.VariableSnapshot::new("x", "1", Some("double")),
      @debugger.VariableSnapshot::new("y", "2", Some("double")),
    ],
  )
  inspect(
    variable_lines(point).join("\n"),
    content=(
      #|arr[0]: Point = {
      #|  x: Double = 1
      #|  y: Double = 2
      #|}
    ),
  )
}

///|
test "struct variable renderer represents empty and truncated structures" {
  let root = @debugger.VariableSnapshot::expanded(
    "root",
    "0x2000",
    Some("example/Root &"),
    [
      @debugger.VariableSnapshot::expanded(
        "empty",
        "0x2100",
        Some("example/Empty &"),
        [],
      ),
      @debugger.VariableSnapshot::truncated(
        "next",
        "0x2200",
        Some("example/Node &"),
        [@debugger.VariableSnapshot::new("value", "7", None)],
      ),
    ],
  )
  inspect(
    variable_lines(root).join("\n"),
    content=(
      #|root: Root = {
      #|  empty: Empty = {}
      #|  next: Node = {
      #|    value = 7
      #|    …
      #|  }
      #|}
    ),
  )
}

///|
test "scalar and unsupported container rendering remains one line" {
  let scalar = @debugger.VariableSnapshot::new("answer", "42", Some("Int"))
  let array = @debugger.VariableSnapshot::new(
    "arr",
    "moonbit.array_i32 @ 0x2000",
    Some("moonbit.array_i32"),
  )
  inspect(variable_lines(scalar).join("\n"), content="answer: Int = 42")
  inspect(
    variable_lines(array).join("\n"),
    content="arr: FixedArray[Int] = moonbit.array_i32 @ 0x2000",
  )
}

///|
fn enum_variable(
  name : String,
  type_name : String,
  constructor_name : String,
  payload : Array[@debugger.VariableEnumPayload],
) -> @debugger.VariableSnapshot raise {
  @debugger.VariableSnapshot::enum_value(
    name,
    Some(type_name),
    @debugger.VariableEnumSnapshot::new(constructor_name, payload),
  )
}

///|
test "enum renderer shows payloadless scalar and aggregate constructors" {
  inspect(
    variable_lines(enum_variable("a", "example/E", "A", [])).join("\n"),
    content=(
      #|a: E
      #|
      #|  A
    ),
  )
  inspect(
    variable_lines(
      enum_variable("b", "example/E", "B", [
        @debugger.VariableEnumPayload::scalar(0, "Int", "7"),
      ]),
    ).join("\n"),
    content=(
      #|b: E
      #|
      #|  B(7)
    ),
  )
  inspect(
    variable_lines(
      enum_variable("c", "example/E", "C", [
        @debugger.VariableEnumPayload::scalar(0, "Double", "1.5"),
        @debugger.VariableEnumPayload::scalar(1, "Int", "2"),
      ]),
    ).join("\n"),
    content=(
      #|c: E
      #|
      #|  C(1.5, 2)
    ),
  )
  inspect(
    variable_lines(
      enum_variable(
        "list",
        "Kaida-Amethyst/moondbg-dwarf-probe/list/List",
        "Cons",
        [
          @debugger.VariableEnumPayload::scalar(0, "Int", "3"),
          @debugger.VariableEnumPayload::aggregate(1, "List"),
        ],
      ),
    ).join("\n"),
    content=(
      #|list: List
      #|
      #|  Cons(3, List)
    ),
  )
}

///|
fn indexed_value(
  index : Int,
  value : String,
  type_name : String,
) -> @debugger.IndexedVariableElement {
  @debugger.IndexedVariableElement::with_value(
    index,
    @debugger.VariableSnapshot::new("[\{index}]", value, Some(type_name)),
  )
}

///|
fn indexed_array(
  name : String,
  element_type : String,
  length : Int,
  elements : Array[@debugger.IndexedVariableElement],
  kind? : @debugger.IndexedCollectionKind = @debugger.FixedArrayCollection,
) -> @debugger.VariableSnapshot raise {
  @debugger.VariableSnapshot::indexed_collection(
    name,
    "raw array",
    None,
    @debugger.IndexedCollectionSnapshot::new(
      kind, element_type, length, elements,
    ),
  )
}

///|
test "FixedArray renderer displays empty single and complete short arrays" {
  inspect(
    variable_lines(indexed_array("empty", "Int", 0, [])).join("\n"),
    content=(
      #|empty: FixedArray[Int] with length = 0
      #|
      #|  []
    ),
  )
  inspect(
    variable_lines(
      indexed_array("one", "Bool", 1, [indexed_value(0, "true", "Bool")]),
    ).join("\n"),
    content=(
      #|one: FixedArray[Bool] with length = 1
      #|
      #|  [true]
    ),
  )
  inspect(
    variable_lines(
      indexed_array("arr", "Int", 3, [
        indexed_value(0, "1", "Int"),
        indexed_value(1, "2", "Int"),
        indexed_value(2, "3", "Int"),
      ]),
    ).join("\n"),
    content=(
      #|arr: FixedArray[Int] with length = 3
      #|
      #|  [1, 2, 3]
    ),
  )
}

///|
test "FixedArray renderer keeps a bounded head and the true tail" {
  let elements = Array::makei(15, index => {
    indexed_value(index, (index + 1).to_string(), "Int")
  })
  elements.push(indexed_value(99, "100", "Int"))
  inspect(
    variable_lines(indexed_array("arr", "Int", 100, elements)).join("\n"),
    content=(
      #|arr: FixedArray[Int] with length = 100
      #|
      #|  [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, ..., 100]
    ),
  )
}

///|
test "FixedArray renderer applies its character budget without losing endpoints" {
  let elements = Array::makei(15, index => {
    indexed_value(index, "18446744073709551615", "UInt64")
  })
  elements.push(indexed_value(99, "100", "UInt64"))
  let array = indexed_array("wide", "UInt64", 100, elements)
  guard variable_lines(array) is [_, "", content] else {
    fail("FixedArray should render as a header, blank line, and content line")
  }
  assert_true(content.length() <= INDEXED_COLLECTION_CONTENT_WIDTH + 2)
  assert_true(content.has_prefix("  [18446744073709551615"))
  assert_true(content.has_suffix("..., 100]"))
  inspect(
    content,
    content="  [18446744073709551615, 18446744073709551615, 18446744073709551615, 18446744073709551615, ..., 100]",
  )
  let exact_value = "1".repeat(48)
  let exact = indexed_array("exact", "Int", 2, [
    indexed_value(0, exact_value, "Int"),
    indexed_value(1, exact_value, "Int"),
  ])
  guard exact.content() is @debugger.VariableIndexedCollection(collection) else {
    fail("exact-width fixture should remain an indexed collection")
  }
  let exact_content = bounded_indexed_content_text(collection)
  assert_eq(exact_content.length(), INDEXED_COLLECTION_CONTENT_WIDTH)
  assert_false(exact_content.contains("..."))
}

///|
test "Array renderer uses the collection kind without changing preview rules" {
  inspect(
    variable_lines(
      indexed_array(
        "arr",
        "Double",
        3,
        [
          indexed_value(0, "1", "Double"),
          indexed_value(1, "2", "Double"),
          indexed_value(2, "3", "Double"),
        ],
        kind=@debugger.ArrayCollection,
      ),
    ).join("\n"),
    content=(
      #|arr: Array[Double] with length = 3
      #|
      #|  [1, 2, 3]
    ),
  )
}

///|
test "FixedArray renderer formats numeric values and opaque type placeholders" {
  inspect(
    variable_lines(
      indexed_array("values", "Double", 4, [
        indexed_value(0, "-2.5", "Double"),
        indexed_value(1, "0", "Double"),
        indexed_value(2, "3.25", "Double"),
        indexed_value(3, "-1e+20", "Double"),
      ]),
    ).join("\n"),
    content=(
      #|values: FixedArray[Double] with length = 4
      #|
      #|  [-2.5, 0, 3.25, -1e+20]
    ),
  )
  let points = Array::makei(15, index => {
    @debugger.IndexedVariableElement::placeholder(index)
  })
  points.push(@debugger.IndexedVariableElement::placeholder(99))
  inspect(
    variable_lines(indexed_array("points", "Point", 100, points)).join("\n"),
    content=(
      #|points: FixedArray[Point] with length = 100
      #|
      #|  [Point, Point, Point, Point, Point, Point, Point, Point, Point, Point, Point, Point, ..., Point]
    ),
  )
}
