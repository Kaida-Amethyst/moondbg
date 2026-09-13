///|
test "source window centers odd and even line counts" {
  assert_eq(source_window(20, 100, line_count=5), (18, 22))
  assert_eq(source_window(20, 100, line_count=10), (15, 24))
}

///|
test "source window shifts at file boundaries and caps at file length" {
  assert_eq(source_window(2, 100, line_count=10), (1, 10))
  assert_eq(source_window(99, 100, line_count=10), (91, 100))
  assert_eq(source_window(3, 6, line_count=10), (1, 6))
}
