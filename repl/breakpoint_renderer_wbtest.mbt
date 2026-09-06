///|
async test "mixed breakpoint list keeps requests actual locations counts and history distinct" {
  let (backend, context) = breakpoint_command_test_context()
  defer context.session.close()
  context.session.add_source_breakpoint(
    "/canonical/main.mbt",
    4,
    display_path="src/../main.mbt",
  )
  |> ignore
  execute_framework_command(context, "b main") |> ignore
  execute_framework_command(context, "b identity") |> ignore
  execute_framework_command(context, "b many") |> ignore
  execute_framework_command(context, "b missing") |> ignore
  backend.source_snapshot_overrides.push(
    @moondbg.BreakpointSnapshot::verified(1, "/canonical/main.mbt", 4, Some(6)).with_locations([
        {
          source_path: Some("/actual/generated.mbt"),
          line: Some(6),
          column: Some(7),
          instruction_reference: Some("0x10"),
        },
      ],
    ),
  )
  backend.function_snapshot_overrides.append([
    @moondbg.FunctionBreakpointSnapshot::verified(2, "main"),
    @moondbg.FunctionBreakpointSnapshot::verified(3, "identity").with_locations([
        {
          source_path: None,
          line: None,
          column: None,
          instruction_reference: Some("0x20"),
        },
      ],
    ),
    @moondbg.FunctionBreakpointSnapshot::verified(
      4,
      "many",
      location_count=Some(8),
    ).with_locations([
      {
        source_path: Some("/actual/family.mbt"),
        line: Some(9),
        column: None,
        instruction_reference: None,
      },
      {
        source_path: Some("/actual/family.mbt"),
        line: Some(10),
        column: None,
        instruction_reference: None,
      },
      {
        source_path: Some("/actual/family.mbt"),
        line: Some(11),
        column: None,
        instruction_reference: None,
      },
      {
        source_path: Some("/actual/family.mbt"),
        line: Some(12),
        column: None,
        instruction_reference: None,
      },
    ]),
    @moondbg.FunctionBreakpointSnapshot::rejected(
      5,
      "missing",
      "no matching function instances were found",
      location_count=Some(0),
    ),
  ])
  context.session.run() |> ignore
  guard execute_framework_command(context, "breakpoints").events
    is [BreakpointsPresentation(entries)] else {
    fail("structured breakpoint list")
  }
  let shuffled = [entries[3], entries[1], entries[4], entries[0], entries[2]]
  let expected =
    #|Breakpoints:
    #|  1  enabled  requested: src/../main.mbt:4
    #|     installation: current: verified
    #|     actual: /actual/generated.mbt:6:7
    #|  2  enabled  requested: function main
    #|     installation: current: verified
    #|     actual: source location unknown
    #|  3  enabled  requested: function identity
    #|     installation: current: verified
    #|     locations: unknown
    #|     actual: source location unknown
    #|  4  enabled  requested: function many
    #|     installation: current: verified
    #|     locations: 8
    #|     actual: /actual/family.mbt:9
    #|     actual: /actual/family.mbt:10
    #|     actual: /actual/family.mbt:11
    #|     ... (showing 3 representative locations)
    #|  5  enabled  requested: function missing
    #|     installation: current: rejected: no matching function instances were found
    #|     locations: 0
    #|     actual: source location unknown
  assert_eq(breakpoint_list_lines(shuffled).join("\n"), expected)
  assert_eq(entries.map(item => item.id), [1, 2, 3, 4, 5])
  execute_framework_command(context, "disable 4") |> ignore
  let disabled = context.session.breakpoints()[3]
  assert_true(!disabled.enabled)
  assert_eq(breakpoint_list_lines([disabled]), [
    "Breakpoints:", "  4  disabled  requested: function many", "     installation: previous: verified",
    "     previous locations: 8", "     previous actual: /actual/family.mbt:9", "     previous actual: /actual/family.mbt:10",
    "     previous actual: /actual/family.mbt:11", "     ... (showing 3 representative locations)",
  ])
  execute_framework_command(context, "continue") |> ignore
  assert_true(context.session.state() is @moondbg.Ready)
  let history = breakpoint_list_lines(context.session.breakpoints()).join("\n")
  assert_true(history.contains("installation: previous: verified"))
  assert_true(!history.contains("installation: current:"))
}

///|
async test "uninstalled family list reports unknown location count and source" {
  let (_, context) = breakpoint_command_test_context()
  defer context.session.close()
  execute_framework_command(context, "b identity") |> ignore
  assert_eq(breakpoint_list_lines(context.session.breakpoints()), [
    "Breakpoints:", "  1  enabled  requested: function identity", "     installation: not installed",
    "     locations: unknown", "     actual: source location unknown",
  ])
}
