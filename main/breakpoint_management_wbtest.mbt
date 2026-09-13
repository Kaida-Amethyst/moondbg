///|
fn breakpoint_command_test_context() -> (
  ExecutionCommandTestBackend,
  ReplContext,
) raise {
  let backend = ExecutionCommandTestBackend::new()
  let session = @moondbg.DebugSession::new(
    "/tmp/program",
    backend,
    debug_context=@moondbg.DebugContext::new("example/main", []),
  )
  (
    backend,
    ReplContext::new(session, default_command_registry(), HumanRenderer::new()),
  )
}

///|
test "breakpoint management parsers accept exactly one positive decimal ID" {
  let registry = default_command_registry()
  assert_true(registry.parse_line("breakpoints") is RegistryCommand(_))
  assert_true(
    registry.parse_line("breakpoints 1")
    is RegistryInvalid("breakpoints does not accept arguments"),
  )
  for name in ["delete", "disable", "enable"] {
    for id in ["1", "001", "2147483647"] {
      assert_true(
        registry.parse_line("  \{name}\t\{id}  ") is RegistryCommand(_),
      )
    }
    for
      id in [
        "", "0", "00", "-1", "+1", "1.0", "1e2", "0x10", "1_000", "2147483648", "999999999999999999999999999",
        "1 2", "1\t2", "1-3", "all", "*", "１", "1\n",
      ] {
      assert_true(
        registry.parse_line("\{name} \{id}") is RegistryInvalid(_),
        msg="\{name} \{id}",
      )
    }
    guard registry.lookup(name) is Some(spec) else {
      fail("registered management command")
    }
    assert_eq(spec.aliases, [])
    assert_eq(spec.usage, "\{name} <id>")
  }
  for name in ["del", "dis", "en", "bp", "breakpoint", "DELETE", "disable1"] {
    assert_true(registry.parse_line(name) is RegistryUnknown)
  }
}

///|
async test "Ready breakpoint commands are local and return structured idempotent results" {
  let (backend, context) = breakpoint_command_test_context()
  defer context.session.close()
  guard execute_framework_command(context, "breakpoints").events
    is [BreakpointsPresentation(empty)] else {
    fail("list presentation")
  }
  assert_eq(breakpoint_list_lines(empty), ["No breakpoints."])
  execute_framework_command(context, "b main") |> ignore
  guard execute_framework_command(context, "disable 1").events
    is [BreakpointManagedPresentation(disabled)] else {
    fail("disable result")
  }
  assert_eq(breakpoint_managed_line(disabled), "Breakpoint 1 disabled.")
  guard execute_framework_command(context, "disable 1").events
    is [BreakpointManagedPresentation(unchanged)] else {
    fail("idempotent disable")
  }
  assert_eq(
    breakpoint_managed_line(unchanged),
    "Breakpoint 1 is already disabled.",
  )
  guard execute_framework_command(context, "enable 001").events
    is [BreakpointManagedPresentation(enabled)] else {
    fail("enable result")
  }
  assert_eq(
    breakpoint_managed_line(enabled),
    "Breakpoint 1 enabled (not installed).",
  )
  guard execute_framework_command(context, "enable 1").events
    is [BreakpointManagedPresentation(unchanged)] else {
    fail("idempotent enable")
  }
  assert_eq(
    breakpoint_managed_line(unchanged),
    "Breakpoint 1 is already enabled.",
  )
  guard execute_framework_command(context, "delete 1").events
    is [BreakpointManagedPresentation(deleted)] else {
    fail("delete result")
  }
  assert_eq(breakpoint_managed_line(deleted), "Breakpoint 1 deleted.")
  guard execute_framework_command(context, "delete 1").events
    is [BreakpointManagementFailurePresentation(failure)] else {
    fail("unknown id")
  }
  assert_true(failure is BreakpointIdNotFound(1))
  assert_eq(
    breakpoint_management_failure_line(failure),
    "Breakpoint 1 was not found.",
  )
  assert_eq(backend.syncs, 0)
  assert_eq(backend.launches, 0)
}

///|
async test "Stopped management synchronizes and presents rejected enable without losing intent" {
  let (backend, context) = breakpoint_command_test_context()
  defer context.session.close()
  execute_framework_command(context, "b identity") |> ignore
  execute_framework_command(context, "run") |> ignore
  execute_framework_command(context, "disable 1") |> ignore
  backend.function_snapshot_overrides.push(
    @moondbg.FunctionBreakpointSnapshot::rejected(
      1,
      "identity",
      "no matching functions",
      location_count=Some(0),
    ),
  )
  guard execute_framework_command(context, "enable 1").events
    is [BreakpointManagedPresentation(result)] else {
    fail("enable result")
  }
  assert_true(result.breakpoint.enabled)
  assert_true(
    result.breakpoint.installation
    is @moondbg.CurrentInstallation(@moondbg.Rejected("no matching functions")),
  )
  assert_eq(
    breakpoint_managed_line(result),
    "Breakpoint 1 enabled (current: rejected: no matching functions).",
  )
  assert_eq(backend.syncs, 2)
  let before = backend.syncs
  execute_framework_command(context, "breakpoints") |> ignore
  assert_eq(backend.syncs, before)
  assert_true(context.session.state() is @moondbg.Stopped)
}

///|
async test "management presents refusal recovery and state errors with domain distinctions" {
  for uncertain in [false, true] {
    let (backend, context) = breakpoint_command_test_context()
    defer context.session.close()
    execute_framework_command(context, "b main") |> ignore
    execute_framework_command(context, "run") |> ignore
    backend.fail_sync = uncertain
    backend.refuse_sync = !uncertain
    let result = execute_framework_command(context, "delete 1")
    if uncertain {
      assert_true(
        result.events is [AdapterFailurePresentation(message)] &&
        message.contains("current execution was discarded"),
      )
      assert_true(context.session.state() is @moondbg.Ready)
    } else {
      guard result.events is [BreakpointManagementFailurePresentation(failure)] else {
        fail("refusal event")
      }
      assert_eq(
        breakpoint_management_failure_line(failure),
        "Cannot manage breakpoint: test rejected without changes",
      )
      assert_true(context.session.state() is @moondbg.Stopped)
    }
    assert_true(context.session.breakpoints()[0].enabled)
    context.session.close()
    assert_true(
      execute_framework_command(context, "disable 1").events
      is [
        OperationNotAllowedPresentation(@moondbg.Exited, "manage breakpoints"),
      ],
    )
  }
}

///|
async test "run reports only enabled source and function breakpoints" {
  let (backend, context) = breakpoint_command_test_context()
  defer context.session.close()
  context.session.add_source_breakpoint("/tmp/main.mbt", 4) |> ignore
  execute_framework_command(context, "b identity") |> ignore
  context.session.add_source_breakpoint("/tmp/main.mbt", 8) |> ignore
  execute_framework_command(context, "b main") |> ignore
  execute_framework_command(context, "disable 1") |> ignore
  execute_framework_command(context, "disable 2") |> ignore
  let result = execute_framework_command(context, "run")
  let ids = result.events.filter_map(event => {
    match event {
      BreakpointUpdatePresentation(item) => Some(item.id())
      FunctionBreakpointUpdatePresentation(item) => Some(item.id())
      _ => None
    }
  })
  assert_eq(ids, [3, 4])
  assert_eq(backend.breakpoints.map(item => item.id()), [3])
  assert_eq(backend.function_breakpoints.map(item => item.id()), [4])
}
