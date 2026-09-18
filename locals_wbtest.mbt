///|
fn local_summary(
  name : String,
  type_name : String?,
  availability : @debugger.LocalVariableAvailability,
) -> @debugger.LocalVariableSnapshot {
  @debugger.LocalVariableSnapshot::new(name, type_name, availability)
}

///|
fn locals_test_frame(
  physical_index : Int,
) -> @debugger.FrameSelection raise @debugger.StackSnapshotError {
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
      @debugger.LocalVariableAvailable(@debugger.LocalScalar("3")),
    ),
    local_summary(
      "items",
      Some("Array[Double]"),
      @debugger.LocalVariableAvailable(
        @debugger.LocalCollection(@debugger.ArrayCollection, 10),
      ),
    ),
    local_summary(
      "point",
      Some("Point"),
      @debugger.LocalVariableAvailable(@debugger.LocalStructure),
    ),
    local_summary(
      "list",
      Some("List"),
      @debugger.LocalVariableAvailable(@debugger.LocalEnumConstructor("Cons")),
    ),
    local_summary("future", Some("Int"), @debugger.LocalVariableUnavailable),
    local_summary("shadowed", Some("Int"), @debugger.LocalVariableAmbiguous),
  ]
  let expected =
    #|  count: Int = 3
    #|  items: Array[Double] with length = 10
    #|  point: Point
    #|  list: List = Cons
    #|  future: Int = <unavailable>
    #|  shadowed: Int = <ambiguous binding>
  let thread = @debugger.ThreadSelection::initial()
  let frame = locals_test_frame(1)
  let snapshot = @debugger.LocalVariablesSnapshot::available(
    thread, frame, variables,
  )
  assert_eq(local_snapshot_lines(snapshot).join("\n"), "Locals:\n\{expected}")
  assert_eq(
    local_snapshot_lines(
      @debugger.LocalVariablesSnapshot::available(thread, frame, []),
    ),
    ["No local variables in the selected frame."],
  )
  assert_eq(
    local_snapshot_lines(
      @debugger.LocalVariablesSnapshot::scope_unavailable(thread, frame),
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
    @debugger.LocalVariablesSnapshot::available(
      @debugger.ThreadSelection::initial(),
      locals_test_frame(1),
      [
        local_summary(
          "leaf_value",
          Some("Int"),
          @debugger.LocalVariableAvailable(@debugger.LocalScalar("11")),
        ),
      ],
    ),
  )
  backend.local_results.set(
    4,
    @debugger.LocalVariablesSnapshot::available(
      @debugger.ThreadSelection::initial(),
      locals_test_frame(4),
      [
        local_summary(
          "main_value",
          Some("Int"),
          @debugger.LocalVariableAvailable(@debugger.LocalScalar("44")),
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
    @debugger.LocalVariablesSnapshot::available(
      @debugger.ThreadSelection::initial(),
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
  assert_eq(empty.scope_availability(), @debugger.LocalScopeAvailable)
  assert_eq(empty.frame().index(), 1)
  execute_framework_command(context, "frame 0") |> ignore
  guard execute_framework_command(context, "locals").events
    is [LocalsPresentation(native)] else {
    fail("native frame without Locals scope should remain a structured result")
  }
  assert_eq(native.scope_availability(), @debugger.LocalScopeUnavailable)
  assert_eq(native.frame().index(), 0)
}

///|
async test "locals maps invalid state and adapter failure without protocol text" {
  let ready_backend = StackCommandTestBackend::new()
  let ready_context = stack_command_context(ready_backend)
  assert_true(
    execute_framework_command(ready_context, "locals").events
    is [
      OperationNotAllowedPresentation(
        @debugger.Ready,
        "inspect local variables"
      ),
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
  assert_true(failed_context.session.state() is @debugger.Ready)
}
