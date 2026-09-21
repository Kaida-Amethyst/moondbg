///|
test "shared variable path grammar is read-only and canonicalizes indices" {
  for
    (text, canonical) in [
      ("point", "point"),
      ("line.start.x", "line.start.x"),
      ("points[001].x", "points[1].x"),
      ("matrix[1][2]", "matrix[1][2]"),
      ("pair.00", "pair.0"),
      ("result.0.x", "result.0.x"),
      ("arr[0].1.0.text[2:4]", "arr[0].1.0.text[2:4]"),
      ("线段.起点.x1", "线段.起点.x1"),
    ] {
    guard @debugger.VariablePath::parse(text) is Some(path) else { fail(text) }
    assert_eq(path.display_name(), canonical)
    assert_eq(@debugger.VariablePath::parse(canonical), Some(path))
  }
  for
    text in [
      "", " ", "p point", "point()", "point.x + 1", "point.x=2", "arr[i]", "arr[-1]",
      "arr[+1]", "arr[2147483648]", "arr[0];exit", "arr[0]tail", "point..x", "point.-1",
      "pair.+1", "pair.2147483648", "pair.0x", "pair.0()", "pair.0 + 1", "point .x",
      "arr[ 0]", "arr[0 ]", "42", "`expr`",
    ] {
    assert_eq(@debugger.VariablePath::parse(text), None, msg=text)
  }
  assert_true(@debugger.VariablePath::parse("a".repeat(4097)) is None)
  assert_true(@debugger.VariablePath::parse("a" + ".x".repeat(65)) is None)
}
