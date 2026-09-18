///|
test "bare breakpoint lines are positive absolute decimal lines and preserve other targets" {
  let registry = default_command_registry()
  for
    command in [
      "b 1", "break 0007", "b 2147483647", "b main", "b helper2", "b @util.foo",
      "b 123.mbt:8", "b path/to/main.mbt:9",
    ] {
    assert_true(registry.parse_line(command) is RegistryCommand(_), msg=command)
  }
  for
    arguments in [
      "0", "00", "-1", "+1", "1.5", "1e2", "0x10", "1_000", "2147483648", "99999999999999999999",
      "1 2", "1\t2", "1..3", "-", "+",
    ] {
    assert_true(
      registry.parse_line("b \{arguments}")
      is RegistryInvalid("breakpoint line must be a positive decimal integer"),
      msg=arguments,
    )
  }
  assert_true(registry.parse_line("b") is RegistryInvalid(_))
}

///|
async fn current_source_breakpoint_context() -> (ReplContext, String, String) {
  let source_a = @fs.realpath("break.mbt")
  let source_b = @fs.realpath("run.mbt")
  let backend = StackCommandTestBackend::new()
  backend.stack_responses.push(
    @debugger.StackSnapshot::new(
      @debugger.ThreadSelection::initial(),
      [
        stack_command_frame(
          0,
          "leaf",
          Some(source_a),
          Some(4),
          @debugger.MoonBitUserFrame,
        ),
        stack_command_frame(
          1,
          "caller",
          Some(source_b),
          Some(6),
          @debugger.MoonBitUserFrame,
        ),
        stack_command_frame(2, "native", None, None, @debugger.NativeFrame),
      ],
      0,
      3,
      Some(3),
      true,
    ),
  )
  (stack_command_context(backend), source_a, source_b)
}

///|
async test "current-file errors do not consume ids or guess source files" {
  let (context, source, _) = current_source_breakpoint_context()
  defer context.session.close()
  assert_true(
    execute_framework_command(context, "b 12").events
    is [BreakpointErrorPresentation(BreakpointCurrentFrameMissing)],
  )
  assert_eq(context.session.breakpoint_configuration().sources().length(), 0)
  context.session.run() |> ignore
  execute_framework_command(context, "frame 2") |> ignore
  assert_true(
    execute_framework_command(context, "break 12").events
    is [BreakpointErrorPresentation(BreakpointCurrentFrameSourceMissing)],
  )
  assert_eq(context.session.breakpoint_configuration().sources().length(), 0)
  guard execute_framework_command(context, "b \{source}:12").events
    is [BreakpointUpdatePresentation(breakpoint)] else {
    fail("explicit source remains usable without selected source")
  }
  assert_eq(breakpoint.id(), 1)
  assert_eq(breakpoint.source_path(), source)
  execute_framework_command(context, "continue") |> ignore
  assert_true(
    execute_framework_command(context, "b 8").events
    is [BreakpointErrorPresentation(BreakpointCurrentFrameMissing)],
  )
  assert_eq(
    context.session.breakpoint_configuration().sources().map(item => item.id()),
    [1],
  )
}

///|
async test "bare line binds at execution to selected frame and old breakpoints stay fixed" {
  let (context, source_a, source_b) = current_source_breakpoint_context()
  defer context.session.close()
  context.session.run() |> ignore
  let epoch = context.session.stop_epoch()
  guard context.registry.parse_line("b 12") is RegistryCommand(delayed) else {
    fail("line command")
  }
  execute_framework_command(context, "frame 1") |> ignore
  delayed.execute(context) |> ignore
  execute_framework_command(context, "down") |> ignore
  execute_framework_command(context, "b 8") |> ignore
  execute_framework_command(context, "up") |> ignore
  execute_framework_command(context, "break 9") |> ignore
  guard execute_framework_command(context, "list").events
    is [SourceViewPresentation(view)] else {
    fail("list context")
  }
  assert_eq(view.source_path, Some(source_b))
  let configured = context.session.breakpoint_configuration().sources()
  assert_eq(configured.map(item => item.id()), [1, 2, 3])
  assert_eq(configured.map(item => item.source_path()), [
    source_b, source_a, source_b,
  ])
  assert_eq(configured.map(item => item.requested_line()), [12, 8, 9])
  assert_eq(context.session.stop_epoch(), epoch)
  assert_eq(
    context.session.selected_frame().map(frame => frame.index()),
    Some(1),
  )
}
