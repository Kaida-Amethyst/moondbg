///|
priv struct ExecutionCommandTestBackend {
  mut launches : Int
  mut continues : Int
  mut nexts : Int
  mut steps : Int
  mut finishes : Int
  breakpoints : Array[@debugger.SourceBreakpoint]
  function_breakpoints : Array[@debugger.FunctionBreakpoint]
  output : Array[@debugger.DebugOutput]
  mut fail_next : Bool
  mut fail_installs : Bool
  mut reject_installs : Bool
  mut syncs : Int
  mut fail_sync : Bool
  mut refuse_sync : Bool
  source_snapshot_overrides : Array[@debugger.BreakpointSnapshot]
  function_snapshot_overrides : Array[@debugger.FunctionBreakpointSnapshot]
}

///|
fn ExecutionCommandTestBackend::new() -> ExecutionCommandTestBackend {
  {
    launches: 0,
    continues: 0,
    nexts: 0,
    steps: 0,
    finishes: 0,
    breakpoints: [],
    function_breakpoints: [],
    output: [],
    fail_next: false,
    fail_installs: false,
    reject_installs: false,
    syncs: 0,
    fail_sync: false,
    refuse_sync: false,
    source_snapshot_overrides: [],
    function_snapshot_overrides: [],
  }
}

///|
fn execution_command_stop() -> @debugger.StopSnapshot {
  @debugger.StopSnapshot::new(
    "test-stop",
    "test.main",
    Some("/tmp/test.mbt"),
    Some(4),
    Some(1),
  )
}

///|
impl @debugger.DebugBackend for ExecutionCommandTestBackend with fn launch(
  self,
  _executable,
  breakpoints,
  function_breakpoints,
) {
  self.launches += 1
  self.breakpoints.clear()
  for breakpoint in breakpoints {
    self.breakpoints.push(breakpoint)
  }
  self.function_breakpoints.clear()
  for breakpoint in function_breakpoints {
    self.function_breakpoints.push(breakpoint)
  }
  @debugger.RunOutcome::stopped(execution_command_stop())
}

///|
fn ExecutionCommandTestBackend::install_source_breakpoint(
  self : ExecutionCommandTestBackend,
  breakpoint : @debugger.SourceBreakpoint,
) -> @debugger.BreakpointSnapshot raise {
  self.breakpoints.push(breakpoint)
  if self.fail_installs {
    raise @debugger.DebugBackendError::failure("breakpoint adapter failed")
  }
  if self.reject_installs {
    return @debugger.BreakpointSnapshot::rejected(
      breakpoint.id(),
      breakpoint.source_path(),
      breakpoint.requested_line(),
      "no executable code at this location",
    )
  }
  @debugger.BreakpointSnapshot::verified(
    breakpoint.id(),
    breakpoint.source_path(),
    breakpoint.requested_line(),
    Some(breakpoint.requested_line()),
  )
}

///|
fn ExecutionCommandTestBackend::install_function_breakpoint(
  self : ExecutionCommandTestBackend,
  breakpoint : @debugger.FunctionBreakpoint,
) -> @debugger.FunctionBreakpointSnapshot raise {
  self.function_breakpoints.push(breakpoint)
  if self.fail_installs {
    raise @debugger.DebugBackendError::failure("breakpoint adapter failed")
  }
  if self.reject_installs {
    return @debugger.FunctionBreakpointSnapshot::rejected(
      breakpoint.id(),
      breakpoint.display_name(),
      "no matching functions were found",
    )
  }
  @debugger.FunctionBreakpointSnapshot::verified(
    breakpoint.id(),
    breakpoint.display_name(),
  )
}

///|
impl @debugger.DebugBackend for ExecutionCommandTestBackend with fn continue_execution(
  self,
  _thread,
) {
  self.continues += 1
  @debugger.RunOutcome::exited(Some(0))
}

///|
impl @debugger.DebugBackend for ExecutionCommandTestBackend with fn next(
  self,
  _thread,
) {
  self.nexts += 1
  if self.fail_next {
    raise @debugger.DebugBackendError::failure("next adapter failed")
  }
  @debugger.RunOutcome::stopped(execution_command_stop())
}

///|
impl @debugger.DebugBackend for ExecutionCommandTestBackend with fn step(
  self,
  _thread,
) {
  self.steps += 1
  @debugger.RunOutcome::stopped(execution_command_stop())
}

///|
impl @debugger.DebugBackend for ExecutionCommandTestBackend with fn finish(
  self,
  _thread,
) {
  self.finishes += 1
  @debugger.RunOutcome::stopped(execution_command_stop())
}

///|
impl @debugger.DebugBackend for ExecutionCommandTestBackend with fn stack_snapshot(
  _self,
  thread,
  _window,
) {
  test_stack_snapshot_from_stop(thread, execution_command_stop())
}

///|
impl @debugger.DebugBackend for ExecutionCommandTestBackend with fn find_variable(
  _self,
  _thread,
  _frame,
  path,
) {
  @debugger.VariableLookupResult::not_found(path.display_name())
}

///|
impl @debugger.DebugBackend for ExecutionCommandTestBackend with fn local_variables(
  _self,
  thread,
  frame,
) {
  @debugger.LocalVariablesSnapshot::available(thread, frame, [])
}

///|
impl @debugger.DebugBackend for ExecutionCommandTestBackend with fn breakpoint_snapshots(
  self,
) {
  if self.source_snapshot_overrides is [_, ..] {
    return self.source_snapshot_overrides.copy()
  }
  self.breakpoints.map(breakpoint => {
    @debugger.BreakpointSnapshot::verified(
      breakpoint.id(),
      breakpoint.source_path(),
      breakpoint.requested_line(),
      Some(breakpoint.requested_line()),
    )
  })
}

///|
impl @debugger.DebugBackend for ExecutionCommandTestBackend with fn function_breakpoint_snapshots(
  self,
) {
  if self.function_snapshot_overrides is [_, ..] {
    return self.function_snapshot_overrides.copy()
  }
  self.function_breakpoints.map(breakpoint => {
    @debugger.FunctionBreakpointSnapshot::verified(
      breakpoint.id(),
      breakpoint.display_name(),
    )
  })
}

///|
impl @debugger.DebugBackend for ExecutionCommandTestBackend with fn take_output(
  self,
) {
  let output = self.output.copy()
  self.output.clear()
  output
}

///|
impl @debugger.DebugBackend for ExecutionCommandTestBackend with fn disconnect(
  _self,
) {
  ()
}

///|
impl @debugger.DebugBackend for ExecutionCommandTestBackend with fn close(_self) {
  ()
}

///|
fn execution_command_test_context() -> (
  ExecutionCommandTestBackend,
  ReplContext,
) raise {
  let backend = ExecutionCommandTestBackend::new()
  let session = @debugger.DebugSession::new("/tmp/program", backend)
  let renderer = HumanRenderer::new()
  let context = ReplContext::new(session, default_command_registry(), renderer)
  (backend, context)
}

///|
fn function_breakpoint_test_context() -> (
  ExecutionCommandTestBackend,
  ReplContext,
) raise {
  let backend = ExecutionCommandTestBackend::new()
  let debug_context = @debugger.DebugContext::new("example/app/main", [
    ("util", "example/lib/util"),
  ])
  let session = @debugger.DebugSession::new(
    "/tmp/program",
    backend,
    debug_context~,
  )
  let renderer = HumanRenderer::new()
  let context = ReplContext::new(session, default_command_registry(), renderer)
  (backend, context)
}

///|
async fn execute_stopped_command(
  command : StringView,
) -> (ExecutionCommandTestBackend, CommandResult) {
  let (backend, context) = execution_command_test_context()
  context.session.run() |> ignore
  let result = execute_framework_command(context, command)
  (backend, result)
}

///|
fn assert_stopped_command_result(result : CommandResult) -> Unit raise {
  assert_true(result.control is ContinueRepl)
  guard result.events
    is [StopPresentation(snapshot), SourceViewPresentation(source_view)] else {
    fail("expected independent stop and source-view events")
  }
  assert_eq(snapshot.reason(), "test-stop")
  assert_eq(source_view.source_path, Some("/tmp/test.mbt"))
  assert_eq(source_view.line, Some(4))
  assert_eq(source_view.line_count, DEFAULT_SOURCE_LINE_COUNT)
}

///|
test "P6 execution command specs retain names aliases and argument errors" {
  let registry = default_command_registry()
  for
    entry in [
      ("break", "b"),
      ("run", "r"),
      ("continue", "c"),
      ("next", "n"),
      ("step", "s"),
      ("finish", "fin"),
    ] {
    guard registry.lookup(entry.0) is Some(canonical) &&
      registry.lookup(entry.1) is Some(command_alias) else {
      fail("missing command spec for '\{entry.0}'")
    }
    assert_eq(canonical.name, entry.0)
    assert_eq(command_alias.name, entry.0)
  }
  for
    entry in [
      ("run now", "run does not accept arguments"),
      ("r now", "r does not accept arguments"),
      ("continue now", "continue does not accept arguments"),
      ("c now", "c does not accept arguments"),
      ("next now", "next does not accept arguments"),
      ("n now", "n does not accept arguments"),
      ("step 1", "step does not accept arguments"),
      ("s 1", "s does not accept arguments"),
      ("finish frame", "finish does not accept arguments"),
      ("fin frame", "fin does not accept arguments"),
    ] {
    guard registry.parse_line(entry.0) is RegistryInvalid(message) else {
      fail("expected invalid command '\{entry.0}'")
    }
    assert_eq(message, entry.1)
  }
}

///|
test "P6 break parser retains source and line validation" {
  let registry = default_command_registry()
  for
    command in [
      "break", "b main.mbt", "break :4", "break main.mbt:", "break main.mbt:0", "break main.mbt:-1",
      "break main.mbt:nope",
    ] {
    assert_true(registry.parse_line(command) is RegistryInvalid(_), msg=command)
  }
}

///|
test "function break parser accepts local_breakpoint and imported top-level names" {
  let registry = default_command_registry()
  for command in ["b main", "break helper", "b @util.parse"] {
    assert_true(registry.parse_line(command) is RegistryCommand(_), msg=command)
  }
  for
    command in [
      "b @util", "b @.parse", "b @util.", "b @util.foo.more", "b foo bar",
    ] {
    assert_true(registry.parse_line(command) is RegistryInvalid(_), msg=command)
  }
}

///|
async test "function break command resolves local_breakpoint imported and entry symbols" {
  let (backend, context) = function_breakpoint_test_context()
  for
    expected in [
      ("b helper", 1, "helper"),
      ("b @util.parse", 2, "@util.parse"),
      ("b main", 3, "main"),
    ] {
    let result = execute_framework_command(context, expected.0)
    guard result.events
      is [FunctionBreakpointPendingPresentation(actual_id, actual_name)] else {
      fail("expected a pending function breakpoint for '\{expected.0}'")
    }
    assert_eq(actual_id, expected.1)
    assert_eq(actual_name, expected.2)
  }
  context.session.run() |> ignore
  guard backend.function_breakpoints is [local_breakpoint, imported, entry] else {
    fail("run should pass function breakpoints to the backend")
  }
  assert_true(
    local_breakpoint.selector()
    is @debugger.MoonBitFunctionFamily("_M0FP37example3app4main6helper"),
  )
  assert_true(
    imported.selector()
    is @debugger.MoonBitFunctionFamily("_M0FP37example3lib4util5parse"),
  )
  assert_true(
    entry.selector() is @debugger.ExactPhysicalFunction("moonbit_main"),
  )
}

///|
async test "function break command reports missing and unknown package context" {
  let (_backend, context) = execution_command_test_context()
  let missing = execute_framework_command(context, "b helper")
  assert_true(
    missing.events
    is [BreakpointErrorPresentation(BreakpointFunctionContextMissing)],
  )
  let (_backend, context) = function_breakpoint_test_context()
  let unknown = execute_framework_command(context, "b @missing.helper")
  assert_true(
    unknown.events
    is [BreakpointErrorPresentation(BreakpointUnknownPackageAlias("missing"))],
  )
}

///|
async test "P6 break and b call the session and return pending events" {
  let (backend, context) = execution_command_test_context()
  let first = execute_framework_command(context, "break main.mbt:4")
  guard first.events is [BreakpointPendingPresentation(1, source, 4)] else {
    fail("break should return its pending breakpoint event")
  }
  assert_eq(source, "main.mbt")
  let second = execute_framework_command(context, "b main.mbt:7")
  guard second.events is [BreakpointPendingPresentation(2, _, 7)] else {
    fail("b should use the same breakpoint command factory")
  }
  guard context.session.source_breakpoints() is [one, two] else {
    fail("break commands should add two logical session breakpoints")
  }
  assert_eq(one.id(), 1)
  assert_eq(two.id(), 2)
  assert_eq(backend.launches, 0)
}

///|
async test "break paths stay structured and stopped additions update immediately" {
  let (backend, context) = execution_command_test_context()
  let missing = execute_framework_command(context, "break no-such-source.mbt:4")
  assert_true(
    missing.events
    is [
      BreakpointErrorPresentation(
        BreakpointSourceNotFound("no-such-source.mbt")
      ),
    ],
  )
  let directory = execute_framework_command(context, "break debugger:4")
  assert_true(
    directory.events
    is [BreakpointErrorPresentation(BreakpointSourceNotAFile("debugger"))],
  )
  let final_colon = execute_framework_command(
    context, "b C:/project/main.mbt:12",
  )
  assert_true(
    final_colon.events
    is [
      BreakpointErrorPresentation(
        BreakpointSourceNotFound("C:/project/main.mbt")
      ),
    ],
  )
  context.session.run() |> ignore
  let stopped = execute_framework_command(context, "break main.mbt:4")
  guard stopped.events is [BreakpointUpdatePresentation(breakpoint)] else {
    fail("stopped breakpoint should return its immediate adapter result")
  }
  assert_true(breakpoint.status() is @debugger.Verified)
  assert_eq(breakpoint.id(), 1)
  assert_true(context.session.state() is @debugger.Stopped)
  assert_eq(backend.breakpoints.map(item => item.id()), [1])
}

///|
async test "stopped function breakpoint returns an immediate verified event" {
  let (backend, context) = function_breakpoint_test_context()
  context.session.run() |> ignore
  let result = execute_framework_command(context, "b helper")
  guard result.events is [FunctionBreakpointUpdatePresentation(breakpoint)] else {
    fail("stopped function breakpoint should not be reported as pending")
  }
  assert_true(breakpoint.status() is @debugger.Verified)
  assert_eq(breakpoint.id(), 1)
  assert_eq(breakpoint.display_name(), "helper")
  assert_eq(backend.function_breakpoints.map(item => item.id()), [1])
  assert_true(context.session.state() is @debugger.Stopped)
}

///|
async test "dynamic breakpoint adapter failure is presented and invalidates the stop" {
  let (backend, context) = execution_command_test_context()
  context.session.run() |> ignore
  backend.fail_installs = true
  let result = execute_framework_command(context, "b main.mbt:4")
  assert_true(
    result.events
    is [
      AdapterFailurePresentation(
        "breakpoint adapter failed; current execution was discarded"
      ),
    ],
  )
  assert_true(context.session.state() is @debugger.Ready)
  assert_eq(context.session.stop_epoch(), None)
  guard context.session.source_breakpoints() is [retained] else {
    fail("adapter failure should retain the logical breakpoint")
  }
  assert_eq(retained.id(), 1)
}

///|
async test "stopped rejected breakpoint is immediate and keeps the current stop" {
  let (backend, context) = execution_command_test_context()
  context.session.run() |> ignore
  let stop_epoch = context.session.stop_epoch()
  backend.reject_installs = true
  let result = execute_framework_command(context, "b main.mbt:4")
  guard result.events is [BreakpointUpdatePresentation(breakpoint)] else {
    fail("semantic rejection should be an immediate breakpoint update")
  }
  assert_true(
    breakpoint.status()
    is @debugger.Rejected("no executable code at this location"),
  )
  assert_true(context.session.state() is @debugger.Stopped)
  assert_eq(context.session.stop_epoch(), stop_epoch)
}

///|
async test "P6 run and r call launch and preserve ordered events" {
  let (backend, context) = execution_command_test_context()
  context.session.add_source_breakpoint("/tmp/test.mbt", 4) |> ignore
  backend.output.push(@debugger.DebugOutput::standard_output("program-output"))
  let first = execute_framework_command(context, "run")
  assert_eq(backend.launches, 1)
  guard first.events
    is [
      DebuggeeOutputPresentation(output),
      BreakpointUpdatePresentation(breakpoint),
      StopPresentation(snapshot),
      SourceViewPresentation(source_view),
    ] else {
    fail("run should return output, breakpoint update and stop in order")
  }
  guard output is [item] else { fail("run should return one output item") }
  assert_eq(item.text(), "program-output")
  assert_true(breakpoint.status() is @debugger.Verified)
  assert_eq(snapshot.reason(), "test-stop")
  assert_eq(source_view.line_count, DEFAULT_SOURCE_LINE_COUNT)
  let restarted = execute_framework_command(context, "r")
  assert_eq(backend.launches, 2)
  guard restarted.events
    is [
      ProgramRestartingPresentation,
      BreakpointUpdatePresentation(_),
      StopPresentation(_),
      SourceViewPresentation(_),
    ] else {
    fail("r should return restart, breakpoint update and stop in order")
  }
}

///|
async test "P6 continue and c call the session and return process exit" {
  let (full_backend, full) = execute_stopped_command("continue")
  assert_eq(full_backend.continues, 1)
  assert_true(full.events is [ProcessExitPresentation(Some(0))])
  let (alias_backend, command_alias) = execute_stopped_command("c")
  assert_eq(alias_backend.continues, 1)
  assert_true(command_alias.events is [ProcessExitPresentation(Some(0))])
}

///|
async test "P6 next and n call the session and return a semantic stop" {
  let (full_backend, full) = execute_stopped_command("next")
  assert_eq(full_backend.nexts, 1)
  assert_stopped_command_result(full)
  let (alias_backend, command_alias) = execute_stopped_command("n")
  assert_eq(alias_backend.nexts, 1)
  assert_stopped_command_result(command_alias)
}

///|
async test "P6 step and s call the session and return a semantic stop" {
  let (full_backend, full) = execute_stopped_command("step")
  assert_eq(full_backend.steps, 1)
  assert_stopped_command_result(full)
  let (alias_backend, command_alias) = execute_stopped_command("s")
  assert_eq(alias_backend.steps, 1)
  assert_stopped_command_result(command_alias)
}

///|
async test "P6 finish and fin call the session and return a semantic stop" {
  let (full_backend, full) = execute_stopped_command("finish")
  assert_eq(full_backend.finishes, 1)
  assert_stopped_command_result(full)
  let (alias_backend, command_alias) = execute_stopped_command("fin")
  assert_eq(alias_backend.finishes, 1)
  assert_stopped_command_result(command_alias)
}

///|
async test "P6 execution errors retain semantic state and output ordering" {
  let (ready_backend, ready_context) = execution_command_test_context()
  let disallowed = execute_framework_command(ready_context, "next")
  assert_eq(ready_backend.nexts, 0)
  assert_true(
    disallowed.events
    is [OperationNotAllowedPresentation(@debugger.Ready, "step over")],
  )
  let (failed_backend, failed_context) = execution_command_test_context()
  failed_context.session.run() |> ignore
  failed_backend.output.push(
    @debugger.DebugOutput::standard_error("adapter-output"),
  )
  failed_backend.fail_next = true
  let failed = execute_framework_command(failed_context, "next")
  guard failed.events
    is [
      DebuggeeOutputPresentation(output),
      AdapterFailurePresentation("next adapter failed"),
    ] else {
    fail("adapter output must precede the structured failure")
  }
  guard output is [item] else { fail("expected adapter output") }
  assert_eq(item.text(), "adapter-output")
}
