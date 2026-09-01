///|
fn local_summary(
  name : String,
  type_name : String?,
  availability : @moondbg.LocalVariableAvailability,
) -> @moondbg.LocalVariableSnapshot {
  @moondbg.LocalVariableSnapshot::new(name, type_name, availability)
}

///|
fn locals_test_frame(
  physical_index : Int,
) -> @moondbg.FrameSelection raise @moondbg.StackSnapshotError {
  stack_command_snapshot(5, true).selection(physical_index).unwrap()
}

///|
test "locals parser is strict and registry exposes its help entry" {
  let registry = default_command_registry()
  assert_true(registry.parse_line("locals") is RegistryCommand(_))
  for invalid in ["locals now", "locals --all", "local"] {
    if invalid == "local" {
      assert_true(registry.parse_line(invalid) is RegistryUnknown)
    } else {
      assert_true(
        registry.parse_line(invalid)
        is RegistryInvalid("locals does not accept arguments"),
      )
    }
  }
  guard registry.lookup("locals") is Some(spec) else {
    fail("locals command should be registered")
  }
  assert_eq(spec.usage, "locals")
  assert_eq(spec.aliases, [])
}

///|
test "locals compact renderer covers values aggregates and availability" {
  let variables = [
    local_summary(
      "count",
      Some("Int"),
      @moondbg.LocalVariableAvailable(@moondbg.LocalScalar("3")),
    ),
    local_summary(
      "items",
      Some("Array[Double]"),
      @moondbg.LocalVariableAvailable(
        @moondbg.LocalCollection(@moondbg.ArrayCollection, 10),
      ),
    ),
    local_summary(
      "point",
      Some("Point"),
      @moondbg.LocalVariableAvailable(@moondbg.LocalStructure),
    ),
    local_summary(
      "list",
      Some("List"),
      @moondbg.LocalVariableAvailable(@moondbg.LocalEnumConstructor("Cons")),
    ),
    local_summary("future", Some("Int"), @moondbg.LocalVariableUnavailable),
    local_summary("shadowed", Some("Int"), @moondbg.LocalVariableAmbiguous),
  ]
  let expected =
    #|  count: Int = 3
    #|  items: Array[Double] with length = 10
    #|  point: Point
    #|  list: List = Cons
    #|  future: Int = <unavailable>
    #|  shadowed: Int = <ambiguous binding>
  let thread = @moondbg.ThreadSelection::initial()
  let frame = locals_test_frame(1)
  let snapshot = @moondbg.LocalVariablesSnapshot::available(
    thread, frame, variables,
  )
  assert_eq(local_snapshot_lines(snapshot).join("\n"), "Locals:\n\{expected}")
  assert_eq(
    local_snapshot_lines(
      @moondbg.LocalVariablesSnapshot::available(thread, frame, []),
    ),
    ["No local variables in the selected frame."],
  )
  assert_eq(
    local_snapshot_lines(
      @moondbg.LocalVariablesSnapshot::scope_unavailable(thread, frame),
    ),
    ["Local variables are unavailable in the selected frame."],
  )
}

///|
async test "locals follows the selected physical frame" {
  let backend = StackCommandTestBackend::new()
  backend.stack_responses.push(stack_command_snapshot(5, true))
  backend.local_results.set(
    1,
    @moondbg.LocalVariablesSnapshot::available(
      @moondbg.ThreadSelection::initial(),
      locals_test_frame(1),
      [
        local_summary(
          "leaf_value",
          Some("Int"),
          @moondbg.LocalVariableAvailable(@moondbg.LocalScalar("11")),
        ),
      ],
    ),
  )
  backend.local_results.set(
    4,
    @moondbg.LocalVariablesSnapshot::available(
      @moondbg.ThreadSelection::initial(),
      locals_test_frame(4),
      [
        local_summary(
          "main_value",
          Some("Int"),
          @moondbg.LocalVariableAvailable(@moondbg.LocalScalar("44")),
        ),
      ],
    ),
  )
  let context = stack_command_context(backend)
  context.session.run() |> ignore
  guard execute_framework_command(context, "locals").events
    is [LocalsPresentation(leaf)] else {
    fail("locals should return one structured snapshot")
  }
  assert_eq(leaf.variables()[0].name(), "leaf_value")
  assert_eq(leaf.thread().index(), 0)
  assert_eq(leaf.frame().index(), 1)
  execute_framework_command(context, "frame 4") |> ignore
  guard execute_framework_command(context, "locals").events
    is [LocalsPresentation(main)] else {
    fail("locals should follow an explicit frame selection")
  }
  assert_eq(main.variables()[0].name(), "main_value")
  assert_eq(main.thread().index(), 0)
  assert_eq(main.frame().index(), 4)
  assert_eq(backend.local_frames, [1, 4])
}

///|
async test "locals distinguishes empty and missing scopes including native frames" {
  let backend = StackCommandTestBackend::new()
  backend.stack_responses.push(stack_command_snapshot(5, true))
  backend.local_results.set(
    1,
    @moondbg.LocalVariablesSnapshot::available(
      @moondbg.ThreadSelection::initial(),
      locals_test_frame(1),
      [],
    ),
  )
  let context = stack_command_context(backend)
  context.session.run() |> ignore
  guard execute_framework_command(context, "locals").events
    is [LocalsPresentation(empty)] else {
    fail("available empty locals should remain a structured result")
  }
  assert_eq(empty.scope_availability(), @moondbg.LocalScopeAvailable)
  assert_eq(empty.frame().index(), 1)
  execute_framework_command(context, "frame 0") |> ignore
  guard execute_framework_command(context, "locals").events
    is [LocalsPresentation(native)] else {
    fail("native frame without Locals scope should remain a structured result")
  }
  assert_eq(native.scope_availability(), @moondbg.LocalScopeUnavailable)
  assert_eq(native.frame().index(), 0)
}

///|
async test "locals maps invalid state and adapter failure without protocol text" {
  let ready_backend = StackCommandTestBackend::new()
  let ready_context = stack_command_context(ready_backend)
  assert_true(
    execute_framework_command(ready_context, "locals").events
    is [
      OperationNotAllowedPresentation(@moondbg.Ready, "inspect local variables"),
    ],
  )

  let failed_backend = StackCommandTestBackend::new()
  failed_backend.stack_responses.push(stack_command_snapshot(5, true))
  failed_backend.fail_locals = true
  let failed_context = stack_command_context(failed_backend)
  failed_context.session.run() |> ignore
  assert_true(
    execute_framework_command(failed_context, "locals").events
    is [AdapterFailurePresentation("locals adapter failed")],
  )
  assert_true(failed_context.session.state() is @moondbg.Ready)
}
