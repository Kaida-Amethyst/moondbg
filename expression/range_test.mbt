///|
test "terminal content ranges preserve their base path" {
  let path = VariablePath::parse("values.items[2].text[128:256]").unwrap()
  assert_eq(path.range(), Some((128, 256)))
  assert_eq(path.without_range().display_name(), "values.items[2].text")
  assert_eq(path.display_name(), "values.items[2].text[128:256]")
  assert_true(VariablePath::parse("text[0:0]") is Some(_))
  for
    text in [
      "text[:2]", "text[1:]", "text[-1:2]", "text[2:1]", "text[0:2147483648]", "text[0:1].x",
      "text[0:1][0]", "text[0: 1]", "text[0:1:2]",
    ] {
    assert_eq(VariablePath::parse(text), None, msg=text)
  }
}
