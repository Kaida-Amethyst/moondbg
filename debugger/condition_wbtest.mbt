///|
async test "conditions survive disabled and restarted executions and invalid edits are atomic" {
  let backend = RecordingBackend::new()
  let session = DebugSession::new(
    "/tmp/program",
    backend,
    debug_context=DebugContext::new("example/main", []),
  )
  session.add_source_breakpoint("/tmp/main.mbt", 4) |> ignore
  session.add_function_breakpoint(FunctionBreakpointRequest::current("main"))
  |> ignore
  session.set_condition(1, "i == 7")
  assert_eq(session.condition_text(1), Some("i == 7"))
  assert_eq(session.breakpoints()[0].condition, Some("i == 7"))
  for (id, text) in [(1, "i = 3"), (2, "i == 3"), (999, "i == 3")] {
    assert_true(
      try {
        session.set_condition(id, text)
        false
      } catch {
        _ => true
      },
    )
  }
  assert_eq(session.condition_text(1), Some("i == 7"))
  session.manage_breakpoint(1, DisableBreakpoint) |> ignore
  assert_eq(session.breakpoints()[0].condition, Some("i == 7"))
  session.manage_breakpoint(1, EnableBreakpoint) |> ignore
  session.run() |> ignore
  backend.reject_sync = true
  assert_true(
    try {
      session.set_condition(1, "i < 2")
      false
    } catch {
      _ => true
    },
  )
  assert_eq(session.condition_text(1), Some("i == 7"))
  backend.reject_sync = false
  session.set_condition(1, "i >= 8")
  assert_eq(
    backend.breakpoints[0].condition().map(condition => condition.text),
    Some("i >= 8"),
  )
  session.run() |> ignore
  assert_eq(session.condition_text(1), Some("i >= 8"))
  session.set_condition(1, "   ")
  assert_eq(session.condition_text(1), None)
  assert_eq(backend.breakpoints[0].condition(), None)
}
