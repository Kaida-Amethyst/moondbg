///|
priv enum ObservationVariableMode {
  ObservationVariableFound
  ObservationVariableRootMissing
  ObservationVariableFieldMissing
  ObservationVariableNonStruct
  ObservationVariableNonCollection
  ObservationVariableIndexOutOfBounds
  ObservationVariableUnavailable
  ObservationVariableFailure
}

///|
priv struct ObservationCommandTestBackend {
  mut launches : Int
  mut lookups : Int
  mut last_name : String?
  frame_selections : Array[Int]
  mut stack : @debugger.StackSnapshot?
  variable_mode : ObservationVariableMode
  output : Array[@debugger.DebugOutput]
}

///|
fn ObservationCommandTestBackend::new(
  variable_mode : ObservationVariableMode,
) -> ObservationCommandTestBackend {
  {
    launches: 0,
    lookups: 0,
    last_name: None,
    frame_selections: [],
    stack: None,
    variable_mode,
    output: [],
  }
}

///|
fn observation_command_stop() -> @debugger.StopSnapshot {
  @debugger.StopSnapshot::new(
    "breakpoint",
    "test.main",
    Some("/tmp/observation.mbt"),
    Some(9),
    Some(1),
  )
}

///|
impl @debugger.DebugBackend for ObservationCommandTestBackend with fn launch(
  self,
  _executable,
  _breakpoints,
  _function_breakpoints,
) {
  self.launches += 1
  @debugger.RunOutcome::stopped(observation_command_stop())
}

///|
fn ObservationCommandTestBackend::install_source_breakpoint(
  _self : ObservationCommandTestBackend,
  breakpoint : @debugger.SourceBreakpoint,
) -> @debugger.BreakpointSnapshot {
  @debugger.BreakpointSnapshot::verified(
    breakpoint.id(),
    breakpoint.source_path(),
    breakpoint.requested_line(),
    Some(breakpoint.requested_line()),
  )
}

///|
fn ObservationCommandTestBackend::install_function_breakpoint(
  _self : ObservationCommandTestBackend,
  breakpoint : @debugger.FunctionBreakpoint,
) -> @debugger.FunctionBreakpointSnapshot {
  @debugger.FunctionBreakpointSnapshot::verified(
    breakpoint.id(),
    breakpoint.display_name(),
  )
}

///|
impl @debugger.DebugBackend for ObservationCommandTestBackend with fn continue_execution(
  _self,
  _thread,
) {
  @debugger.RunOutcome::exited(Some(0))
}

///|
impl @debugger.DebugBackend for ObservationCommandTestBackend with fn next(
  _self,
  _thread,
) {
  @debugger.RunOutcome::stopped(observation_command_stop())
}

///|
impl @debugger.DebugBackend for ObservationCommandTestBackend with fn step(
  _self,
  _thread,
) {
  @debugger.RunOutcome::stopped(observation_command_stop())
}

///|
impl @debugger.DebugBackend for ObservationCommandTestBackend with fn finish(
  _self,
  _thread,
) {
  @debugger.RunOutcome::stopped(observation_command_stop())
}

///|
impl @debugger.DebugBackend for ObservationCommandTestBackend with fn stack_snapshot(
  self,
  thread,
  _window,
) {
  match self.stack {
    Some(stack) => stack
    None => test_stack_snapshot_from_stop(thread, observation_command_stop())
  }
}

///|
impl @debugger.DebugBackend for ObservationCommandTestBackend with fn find_variable(
  self,
  _thread,
  frame,
  path,
) {
  self.lookups += 1
  self.frame_selections.push(frame.index())
  let name = path.display_name()
  self.last_name = Some(name)
  match self.variable_mode {
    ObservationVariableFound =>
      @debugger.VariableLookupResult::found(
        @debugger.VariableSnapshot::new(name, "42", Some("Int")),
      )
    ObservationVariableRootMissing =>
      @debugger.VariableLookupResult::not_found(name)
    ObservationVariableFieldMissing =>
      @debugger.VariableLookupResult::field_not_found("point", "z")
    ObservationVariableNonStruct =>
      @debugger.VariableLookupResult::field_access_on_non_struct(
        "point.x",
        "value",
        Some("Double"),
      )
    ObservationVariableNonCollection =>
      @debugger.VariableLookupResult::index_access_on_non_collection(
        "point",
        0,
        Some("Point"),
      )
    ObservationVariableIndexOutOfBounds =>
      @debugger.VariableLookupResult::index_out_of_bounds("arr", 3, 3)
    ObservationVariableUnavailable =>
      @debugger.VariableLookupResult::unavailable("line.start")
    ObservationVariableFailure =>
      raise @debugger.DebugBackendError::failure("variable adapter failed")
  }
}

///|
impl @debugger.DebugBackend for ObservationCommandTestBackend with fn local_variables(
  _self,
  thread,
  frame,
) {
  @debugger.LocalVariablesSnapshot::available(thread, frame, [])
}

///|
impl @debugger.DebugBackend for ObservationCommandTestBackend with fn breakpoint_snapshots(
  _self,
) {
  []
}

///|
impl @debugger.DebugBackend for ObservationCommandTestBackend with fn function_breakpoint_snapshots(
  _self,
) {
  []
}

///|
impl @debugger.DebugBackend for ObservationCommandTestBackend with fn take_output(
  self,
) {
  let output = self.output.copy()
  self.output.clear()
  output
}

///|
impl @debugger.DebugBackend for ObservationCommandTestBackend with fn disconnect(
  _self,
) {
  ()
}

///|
impl @debugger.DebugBackend for ObservationCommandTestBackend with fn close(
  _self,
) {
  ()
}

///|
fn observation_command_test_context(
  variable_mode : ObservationVariableMode,
) -> (ObservationCommandTestBackend, ReplContext) raise {
  let backend = ObservationCommandTestBackend::new(variable_mode)
  let session = @debugger.DebugSession::new("/tmp/program", backend)
  let renderer = HumanRenderer::new()
  let context = ReplContext::new(session, default_command_registry(), renderer)
  (backend, context)
}

///|
async fn stopped_observation_context(
  variable_mode : ObservationVariableMode,
) -> (ObservationCommandTestBackend, ReplContext) {
  let (backend, context) = observation_command_test_context(variable_mode)
  context.session.run() |> ignore
  (backend, context)
}

///|
test "print spec accepts deterministic field and index paths only" {
  let registry = default_command_registry()
  guard registry.lookup("print") is Some(command) &&
    registry.lookup("p") is Some(command_alias) else {
    fail("print and p should be registered")
  }
  assert_eq(command.name, "print")
  assert_eq(command_alias.name, "print")
  for
    valid in [
      "print answer", "p input", "p 结果", "p point.x", "p line.start.x", "p 线段.起点.x1",
      "p arr[0]", "p arr[00012].x", "p lines[0].start.x", "p matrix[1][2]", "p arr[0].0",
      "p pair.0", "p result.0.x",
    ] {
    assert_true(registry.parse_line(valid) is RegistryCommand(_), msg=valid)
  }
  for
    invalid in [
      "p", "print", "p .x", "p x.", "p x..y", "p x .y", "p x. y", "p answer + 1",
      "p point()", "p 42", "p point.2x", "p arr[]", "p arr[-1]", "p arr[+1]", "p arr[ 1]",
      "p arr[1 ]", "p arr[1", "p arr1]", "p arr[1]tail", "p arr[999999999999999999999999999999999999999999]",
      "p arr[0].-1", "p arr[0]..x", "p arr[0].", "p arr [0]", "p arr[0] x",
    ] {
    assert_true(registry.parse_line(invalid) is RegistryInvalid(_), msg=invalid)
  }
  guard parse_variable_path("line.start.x") is Some(path) else {
    fail("a valid field path should be structured")
  }
  assert_eq(path.root_name(), "line")
  assert_true(
    path.steps()
    is [
      @debugger.VariablePathStep::Field("start"),
      @debugger.VariablePathStep::Field("x"),
    ],
  )
  assert_eq(path.display_name(), "line.start.x")
  guard parse_variable_path("lines[000].start[12].x") is Some(mixed) else {
    fail("a valid mixed path should be structured")
  }
  assert_true(
    mixed.steps()
    is [
      @debugger.VariablePathStep::Index(0),
      @debugger.VariablePathStep::Field("start"),
      @debugger.VariablePathStep::Index(12),
      @debugger.VariablePathStep::Field("x"),
    ],
  )
  assert_eq(mixed.display_name(), "lines[0].start[12].x")
  assert_eq(command.usage, "print <path>")
  assert_eq(
    command.summary,
    "Show a variable path or String/Bytes [start:end] range",
  )
}

///|
async test "P7 print and p call the session and return variable events" {
  let (backend, context) = stopped_observation_context(ObservationVariableFound)
  let full = execute_framework_command(context, "print answer")
  guard full.events is [VariablePresentation(variable)] else {
    fail("print should return a variable event")
  }
  assert_eq(variable.name(), "answer")
  assert_eq(variable.value(), "42")
  assert_eq(variable.type_name(), Some("Int"))
  let command_alias = execute_framework_command(context, "p 结果")
  guard command_alias.events is [VariablePresentation(variable)] else {
    fail("p should use the print command")
  }
  assert_eq(variable.name(), "结果")
  let field = execute_framework_command(context, "p line.start.x")
  guard field.events is [VariablePresentation(variable)] else {
    fail("p should send the complete field path to the session")
  }
  assert_eq(variable.name(), "line.start.x")
  let indexed = execute_framework_command(context, "p lines[0].start.x")
  guard indexed.events is [VariablePresentation(variable)] else {
    fail("p should send the complete mixed path to the session")
  }
  assert_eq(variable.name(), "lines[0].start.x")
  assert_eq(backend.lookups, 4)
  assert_eq(backend.last_name, Some("lines[0].start.x"))
}

///|
async test "print returns structured lookup failures and operation-not-allowed events" {
  let (_missing_backend, missing_context) = stopped_observation_context(
    ObservationVariableRootMissing,
  )
  let missing = execute_framework_command(missing_context, "p absent")
  assert_true(
    missing.events
    is [
      VariableLookupFailurePresentation(
        @debugger.VariableRootNotFound("absent")
      ),
    ],
  )
  let (_, field_context) = stopped_observation_context(
    ObservationVariableFieldMissing,
  )
  let field = execute_framework_command(field_context, "p point.z")
  assert_true(
    field.events
    is [
      VariableLookupFailurePresentation(
        @debugger.VariableFieldNotFound("point", "z")
      ),
    ],
  )
  let (_, non_struct_context) = stopped_observation_context(
    ObservationVariableNonStruct,
  )
  let non_struct = execute_framework_command(
    non_struct_context, "p point.x.value",
  )
  assert_true(
    non_struct.events
    is [
      VariableLookupFailurePresentation(
        @debugger.VariableFieldAccessOnNonStruct(
          "point.x",
          "value",
          Some("Double")
        )
      ),
    ],
  )
  let (_, non_collection_context) = stopped_observation_context(
    ObservationVariableNonCollection,
  )
  let non_collection = execute_framework_command(
    non_collection_context, "p point[0]",
  )
  assert_true(
    non_collection.events
    is [
      VariableLookupFailurePresentation(
        @debugger.VariableIndexAccessOnNonCollection("point", 0, Some("Point"))
      ),
    ],
  )
  let (_, out_of_bounds_context) = stopped_observation_context(
    ObservationVariableIndexOutOfBounds,
  )
  let out_of_bounds = execute_framework_command(
    out_of_bounds_context, "p arr[3]",
  )
  assert_true(
    out_of_bounds.events
    is [
      VariableLookupFailurePresentation(
        @debugger.VariableIndexOutOfBounds("arr", 3, 3)
      ),
    ],
  )
  let (_, unavailable_context) = stopped_observation_context(
    ObservationVariableUnavailable,
  )
  let unavailable = execute_framework_command(
    unavailable_context, "p line.start",
  )
  assert_true(
    unavailable.events
    is [
      VariableLookupFailurePresentation(
        @debugger.VariableUnavailable("line.start")
      ),
    ],
  )
  let (ready_backend, ready_context) = observation_command_test_context(
    ObservationVariableFound,
  )
  let disallowed = execute_framework_command(ready_context, "print answer")
  assert_eq(ready_backend.lookups, 0)
  assert_true(
    disallowed.events
    is [OperationNotAllowedPresentation(@debugger.Ready, "inspect a variable")],
  )
}

///|
fn test_lookup_failure(
  result : @debugger.VariableLookupResult,
) -> @debugger.VariableLookupFailure raise {
  guard result is @debugger.VariableLookupFailed(failure) else {
    fail("expected a variable lookup failure")
  }
  failure
}

///|
test "variable lookup failures render stable MoonBit-oriented messages" {
  assert_eq(
    variable_lookup_failure_message(
      test_lookup_failure(@debugger.VariableLookupResult::not_found("missing")),
    ),
    "Variable 'missing' was not found in the current frame.",
  )
  assert_eq(
    variable_lookup_failure_message(
      test_lookup_failure(
        @debugger.VariableLookupResult::field_not_found("point", "z"),
      ),
    ),
    "Field 'z' was not found in 'point'.",
  )
  assert_eq(
    variable_lookup_failure_message(
      test_lookup_failure(
        @debugger.VariableLookupResult::field_access_on_non_struct(
          "point.x",
          "value",
          Some("Double"),
        ),
      ),
    ),
    "Cannot access field 'value' because 'point.x' is not a struct.",
  )
  assert_eq(
    variable_lookup_failure_message(
      test_lookup_failure(
        @debugger.VariableLookupResult::index_access_on_non_collection(
          "point",
          0,
          Some("Point"),
        ),
      ),
    ),
    "Cannot access index 0 because 'point' is not an Array or FixedArray.",
  )
  assert_eq(
    variable_lookup_failure_message(
      test_lookup_failure(
        @debugger.VariableLookupResult::index_out_of_bounds("arr", 3, 3),
      ),
    ),
    "Index 3 is out of bounds for 'arr' with length 3.",
  )
  assert_eq(
    variable_lookup_failure_message(
      test_lookup_failure(
        @debugger.VariableLookupResult::unavailable("line.start"),
      ),
    ),
    "Variable 'line.start' is unavailable at the current location.",
  )
}

///|
async test "P7 print preserves output before result or adapter failure" {
  let (found_backend, found_context) = stopped_observation_context(
    ObservationVariableFound,
  )
  found_backend.output.push(
    @debugger.DebugOutput::standard_output("variable-output"),
  )
  let found = execute_framework_command(found_context, "p answer")
  guard found.events
    is [DebuggeeOutputPresentation(output), VariablePresentation(variable)] else {
    fail("debuggee output must precede the variable result")
  }
  guard output is [item] else { fail("expected one output item") }
  assert_eq(item.text(), "variable-output")
  assert_eq(variable.name(), "answer")
  let (failed_backend, failed_context) = stopped_observation_context(
    ObservationVariableFailure,
  )
  failed_backend.output.push(
    @debugger.DebugOutput::standard_error("adapter-output"),
  )
  let failed = execute_framework_command(failed_context, "print answer")
  guard failed.events
    is [
      DebuggeeOutputPresentation(output),
      AdapterFailurePresentation("variable adapter failed"),
    ] else {
    fail("debuggee output must precede the adapter failure")
  }
  guard output is [item] else { fail("expected adapter output") }
  assert_eq(item.text(), "adapter-output")
}

///|
test "P7 list spec retains default and positive count validation" {
  let registry = default_command_registry()
  guard registry.lookup("list") is Some(command) else {
    fail("list should be registered")
  }
  assert_eq(command.name, "list")
  assert_eq(command.aliases, [])
  for valid in ["list", " list -c 10\t", "list --count\t12"] {
    assert_true(registry.parse_line(valid) is RegistryCommand(_), msg=valid)
  }
  for
    invalid in [
      "list -c", "list --count", "list -c 0", "list -c -1", "list -c ten", "list -c 10 more",
      "list 10", "list --lines 10", "list around",
    ] {
    assert_true(registry.parse_line(invalid) is RegistryInvalid(_), msg=invalid)
  }
}

///|
async test "P7 list returns the selected frame source view" {
  let (backend, context) = stopped_observation_context(ObservationVariableFound)
  for
    entry in [
      ("list", DEFAULT_SOURCE_LINE_COUNT),
      ("list -c 10", 10),
      ("list --count 12", 12),
    ] {
    let result = execute_framework_command(context, entry.0)
    guard result.events is [SourceViewPresentation(source_view)] else {
      fail("list should return the selected frame source-view event")
    }
    assert_eq(source_view.source_path, Some("/tmp/observation.mbt"))
    assert_eq(source_view.line, Some(9))
    assert_eq(source_view.line_count, entry.1)
  }
  assert_eq(backend.launches, 1)
  assert_eq(backend.lookups, 0)
}

///|
async test "P3 list and print follow selection without rewriting the initial stop" {
  let (backend, context) = observation_command_test_context(
    ObservationVariableFound,
  )
  backend.stack = Some(
    @debugger.StackSnapshot::new(
      @debugger.ThreadSelection::initial(),
      [
        @debugger.StackFrameSnapshot::new(
          0,
          "test.main",
          "test.main",
          None,
          Some("/tmp/observation.mbt"),
          Some(9),
          Some(1),
          @debugger.MoonBitUserFrame,
        ),
        @debugger.StackFrameSnapshot::new(
          1,
          "test.caller",
          "test.caller",
          None,
          Some("/tmp/caller.mbt"),
          Some(21),
          Some(3),
          @debugger.MoonBitUserFrame,
        ),
      ],
      0,
      2,
      Some(2),
      true,
    ),
  )
  guard context.session.run() is @debugger.Stopped(initial_stop) else {
    fail("the observation backend should stop")
  }
  guard context.session.last_stop_snapshot() is Some(before_selection) else {
    fail("the initial stop snapshot should be retained")
  }
  assert_eq(before_selection.function_name(), initial_stop.function_name())
  assert_eq(before_selection.source_path(), initial_stop.source_path())
  assert_eq(before_selection.line(), initial_stop.line())
  context.session.select_frame(1) |> ignore
  guard context.session.last_stop_snapshot() is Some(after_selection) else {
    fail("frame selection must not discard the initial stop snapshot")
  }
  assert_eq(after_selection.function_name(), initial_stop.function_name())
  assert_eq(after_selection.source_path(), initial_stop.source_path())
  assert_eq(after_selection.line(), initial_stop.line())
  let listed = execute_framework_command(context, "list")
  guard listed.events is [SourceViewPresentation(source_view)] else {
    fail("list should use the selected caller frame")
  }
  assert_eq(source_view.source_path, Some("/tmp/caller.mbt"))
  assert_eq(source_view.line, Some(21))
  execute_framework_command(context, "p answer") |> ignore
  assert_eq(backend.frame_selections, [1])
}

///|
async test "P7 list without a stable stop returns a semantic empty-state event" {
  let (_backend, context) = observation_command_test_context(
    ObservationVariableFound,
  )
  let result = execute_framework_command(context, "list")
  assert_true(result.events is [NoStoppedSourcePresentation])
}
