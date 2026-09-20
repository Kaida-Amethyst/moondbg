///|
test "shared function parser and resolver use the launch package context" {
  let context = @debugger.DebugContext::new("demo/main", [
    ("util", "demo/helper"),
  ])
  let main = @debugger.FunctionBreakpointRequest::parse("main")
  assert_eq(
    @debugger.DebugContext::empty().resolve_function(main),
    @debugger.FunctionBreakpointSelector::exact_physical("moonbit_main"),
  )
  let current = @debugger.FunctionBreakpointRequest::parse("foo")
  let imported = @debugger.FunctionBreakpointRequest::parse("@util.foo")
  assert_eq(current.display_name(), "foo")
  assert_eq(imported.display_name(), "@util.foo")
  assert_true(
    context.resolve_function(current) != context.resolve_function(imported),
  )
  for
    text in [
      "", "foo bar", "foo\nbar", "@util", "@.foo", "@util.", "foo.x", "@util.foo.bar",
    ] {
    assert_true(
      try {
        @debugger.FunctionBreakpointRequest::parse(text) |> ignore
        false
      } catch {
        _ => true
      },
      msg=text,
    )
  }
  assert_true(
    try {
      @debugger.DebugContext::empty().resolve_function(current) |> ignore
      false
    } catch {
      @debugger.MissingCurrentPackage => true
      _ => false
    },
  )
}
