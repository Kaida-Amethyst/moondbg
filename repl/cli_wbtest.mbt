///|
test "CLI help names its required executable" {
  let help = command().render_help()
  assert_true(help.contains("moondbg"))
  assert_true(help.contains("executable"))
}

///|
test "CLI accepts exactly one executable" {
  let matches = command().parse(argv=["hello.exe"], env={})
  assert_eq(executable_argument(matches), "hello.exe")
}
