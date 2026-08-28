///|
test "struct variable renderer uses MoonBit names and stable nesting" {
  let line = @moondbg.VariableSnapshot::expanded(
    "line1",
    "0x1000",
    Some("example/geometry/Line &"),
    [
      @moondbg.VariableSnapshot::expanded(
        "start",
        "0x1100",
        Some("example/geometry/Point &"),
        [
          @moondbg.VariableSnapshot::new("x", "1", Some("double")),
          @moondbg.VariableSnapshot::new("y", "2", Some("double")),
        ],
      ),
      @moondbg.VariableSnapshot::expanded(
        "end",
        "0x1200",
        Some("example/geometry/Point &"),
        [
          @moondbg.VariableSnapshot::new("x", "4", Some("double")),
          @moondbg.VariableSnapshot::new("y", "6", Some("double")),
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
test "struct variable renderer represents empty and truncated structures" {
  let root = @moondbg.VariableSnapshot::expanded(
    "root",
    "0x2000",
    Some("example/Root &"),
    [
      @moondbg.VariableSnapshot::expanded(
        "empty",
        "0x2100",
        Some("example/Empty &"),
        [],
      ),
      @moondbg.VariableSnapshot::truncated(
        "next",
        "0x2200",
        Some("example/Node &"),
        [@moondbg.VariableSnapshot::new("value", "7", None)],
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
  let scalar = @moondbg.VariableSnapshot::new("answer", "42", Some("Int"))
  let array = @moondbg.VariableSnapshot::new(
    "arr",
    "moonbit.array_i32 @ 0x2000",
    Some("moonbit.array_i32"),
  )
  inspect(variable_lines(scalar).join("\n"), content="answer: Int = 42")
  inspect(
    variable_lines(array).join("\n"),
    content="arr: moonbit.array_i32 = moonbit.array_i32 @ 0x2000",
  )
}
