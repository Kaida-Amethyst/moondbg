///|
priv enum ObservationVariableMode {
  ObservationVariableFound
  ObservationVariableMissing
  ObservationVariableFailure
}

///|
priv struct ObservationCommandTestBackend {
  mut launches : Int
  mut lookups : Int
  mut last_name : String?
  variable_mode : ObservationVariableMode
  output : Array[@moondbg.DebugOutput]
}

///|
fn ObservationCommandTestBackend::new(
  variable_mode : ObservationVariableMode,
) -> ObservationCommandTestBackend {
  { launches: 0, lookups: 0, last_name: None, variable_mode, output: [], }
}

///|
fn observation_command_stop() -> @moondbg.StopSnapshot {
  @moondbg.StopSnapshot::new(
    "breakpoint",
    "test.main",
    Some("/tmp/observation.mbt"),
    Some(9),
    Some(1),
  )
}

///|
impl @moondbg.DebugBackend for ObservationCommandTestBackend with fn launch(
  self,
  _executable,
  _breakpoints,
  _function_breakpoints,
) {
  self.launches += 1
  @moondbg.RunOutcome::stopped(observation_command_stop())
}

///|
impl @moondbg.DebugBackend for ObservationCommandTestBackend with fn continue_execution(
  _self,
  _thread,
) {
  @moondbg.RunOutcome::exited(Some(0))
}

///|
impl @moondbg.DebugBackend for ObservationCommandTestBackend with fn next(
  _self,
  _thread,
) {
  @moondbg.RunOutcome::stopped(observation_command_stop())
}

///|
impl @moondbg.DebugBackend for ObservationCommandTestBackend with fn step(
  _self,
  _thread,
) {
  @moondbg.RunOutcome::stopped(observation_command_stop())
}

///|
impl @moondbg.DebugBackend for ObservationCommandTestBackend with fn finish(
  _self,
  _thread,
) {
  @moondbg.RunOutcome::stopped(observation_command_stop())
}

///|
impl @moondbg.DebugBackend for ObservationCommandTestBackend with fn find_variable(
  self,
  _thread,
  _frame,
  name,
) {
  self.lookups += 1
  self.last_name = Some(name)
  match self.variable_mode {
    ObservationVariableFound =>
      @moondbg.VariableLookupResult::found(
        @moondbg.VariableSnapshot::new(name, "42", Some("Int")),
      )
    ObservationVariableMissing => @moondbg.VariableLookupResult::not_found(name)
    ObservationVariableFailure =>
      raise @moondbg.DebugBackendError::failure("variable adapter failed")
  }
}

///|
impl @moondbg.DebugBackend for ObservationCommandTestBackend with fn breakpoint_snapshots(
  _self,
) {
  []
}

///|
impl @moondbg.DebugBackend for ObservationCommandTestBackend with fn function_breakpoint_snapshots(
  _self,
) {
  []
}

///|
impl @moondbg.DebugBackend for ObservationCommandTestBackend with fn take_output(
  self,
) {
  let output = self.output.copy()
  self.output.clear()
  output
}

///|
impl @moondbg.DebugBackend for ObservationCommandTestBackend with fn disconnect(
  _self,
) {
  ()
}

///|
impl @moondbg.DebugBackend for ObservationCommandTestBackend with fn close(
  _self,
) {
  ()
}

///|
fn observation_command_test_context(
  variable_mode : ObservationVariableMode,
) -> (ObservationCommandTestBackend, ReplContext) raise {
  let backend = ObservationCommandTestBackend::new(variable_mode)
  let session = @moondbg.DebugSession::new("/tmp/program", backend)
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
test "P7 print spec retains alias and simple variable validation" {
  let registry = default_command_registry()
  guard registry.lookup("print") is Some(command) &&
    registry.lookup("p") is Some(command_alias) else {
    fail("print and p should be registered")
  }
  assert_eq(command.name, "print")
  assert_eq(command_alias.name, "print")
  for valid in ["print answer", "p input", "p 结果"] {
    assert_true(registry.parse_line(valid) is RegistryCommand(_), msg=valid)
  }
  for
    invalid in ["p", "print", "p point.x", "p items[3]", "p answer + 1", "p 42"] {
    assert_true(registry.parse_line(invalid) is RegistryInvalid(_), msg=invalid)
  }
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
  assert_eq(backend.lookups, 2)
  assert_eq(backend.last_name, Some("结果"))
}

///|
async test "P7 print returns not-found and operation-not-allowed events" {
  let (_missing_backend, missing_context) = stopped_observation_context(
    ObservationVariableMissing,
  )
  let missing = execute_framework_command(missing_context, "p absent")
  assert_true(missing.events is [VariableNotFoundPresentation("absent")])
  let (ready_backend, ready_context) = observation_command_test_context(
    ObservationVariableFound,
  )
  let disallowed = execute_framework_command(ready_context, "print answer")
  assert_eq(ready_backend.lookups, 0)
  assert_true(
    disallowed.events
    is [OperationNotAllowedPresentation(@moondbg.Ready, "inspect a variable")],
  )
}

///|
async test "P7 print preserves output before result or adapter failure" {
  let (found_backend, found_context) = stopped_observation_context(
    ObservationVariableFound,
  )
  found_backend.output.push(
    @moondbg.DebugOutput::standard_output("variable-output"),
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
    @moondbg.DebugOutput::standard_error("adapter-output"),
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
async test "P7 list returns independent stop and source-view events" {
  let (backend, context) = stopped_observation_context(ObservationVariableFound)
  for
    entry in [
      ("list", DEFAULT_SOURCE_LINE_COUNT),
      ("list -c 10", 10),
      ("list --count 12", 12),
    ] {
    let result = execute_framework_command(context, entry.0)
    guard result.events
      is [StopPresentation(snapshot), SourceViewPresentation(source_view)] else {
      fail("list should return separate stop and source-view events")
    }
    assert_eq(snapshot.reason(), "breakpoint")
    assert_eq(source_view.source_path, Some("/tmp/observation.mbt"))
    assert_eq(source_view.line, Some(9))
    assert_eq(source_view.line_count, entry.1)
  }
  assert_eq(backend.launches, 1)
  assert_eq(backend.lookups, 0)
}

///|
async test "P7 list without a stable stop returns a semantic empty-state event" {
  let (_backend, context) = observation_command_test_context(
    ObservationVariableFound,
  )
  let result = execute_framework_command(context, "list")
  assert_true(result.events is [NoStoppedSourcePresentation])
}
