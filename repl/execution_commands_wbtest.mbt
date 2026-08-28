///|
priv struct ExecutionCommandTestBackend {
  mut launches : Int
  mut continues : Int
  mut nexts : Int
  mut steps : Int
  mut finishes : Int
  breakpoints : Array[@moondbg.SourceBreakpoint]
  function_breakpoints : Array[@moondbg.FunctionBreakpoint]
  output : Array[@moondbg.DebugOutput]
  mut fail_next : Bool
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
  }
}

///|
fn execution_command_stop() -> @moondbg.StopSnapshot {
  @moondbg.StopSnapshot::new(
    "test-stop",
    "test.main",
    Some("/tmp/test.mbt"),
    Some(4),
    Some(1),
  )
}

///|
impl @moondbg.DebugBackend for ExecutionCommandTestBackend with fn launch(
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
  @moondbg.RunOutcome::stopped(execution_command_stop())
}

///|
impl @moondbg.DebugBackend for ExecutionCommandTestBackend with fn install_source_breakpoint(
  self,
  breakpoint,
) {
  self.breakpoints.push(breakpoint)
  @moondbg.BreakpointSnapshot::verified(
    breakpoint.id(),
    breakpoint.source_path(),
    breakpoint.requested_line(),
    Some(breakpoint.requested_line()),
  )
}

///|
impl @moondbg.DebugBackend for ExecutionCommandTestBackend with fn install_function_breakpoint(
  self,
  breakpoint,
) {
  self.function_breakpoints.push(breakpoint)
  @moondbg.FunctionBreakpointSnapshot::verified(
    breakpoint.id(),
    breakpoint.display_name(),
  )
}

///|
impl @moondbg.DebugBackend for ExecutionCommandTestBackend with fn continue_execution(
  self,
  _thread,
) {
  self.continues += 1
  @moondbg.RunOutcome::exited(Some(0))
}

///|
impl @moondbg.DebugBackend for ExecutionCommandTestBackend with fn next(
  self,
  _thread,
) {
  self.nexts += 1
  if self.fail_next {
    raise @moondbg.DebugBackendError::failure("next adapter failed")
  }
  @moondbg.RunOutcome::stopped(execution_command_stop())
}

///|
impl @moondbg.DebugBackend for ExecutionCommandTestBackend with fn step(
  self,
  _thread,
) {
  self.steps += 1
  @moondbg.RunOutcome::stopped(execution_command_stop())
}

///|
impl @moondbg.DebugBackend for ExecutionCommandTestBackend with fn finish(
  self,
  _thread,
) {
  self.finishes += 1
  @moondbg.RunOutcome::stopped(execution_command_stop())
}

///|
impl @moondbg.DebugBackend for ExecutionCommandTestBackend with fn find_variable(
  _self,
  _thread,
  _frame,
  name,
) {
  @moondbg.VariableLookupResult::not_found(name)
}

///|
impl @moondbg.DebugBackend for ExecutionCommandTestBackend with fn breakpoint_snapshots(
  self,
) {
  self.breakpoints.map(breakpoint => {
    @moondbg.BreakpointSnapshot::verified(
      breakpoint.id(),
      breakpoint.source_path(),
      breakpoint.requested_line(),
      Some(breakpoint.requested_line()),
    )
  })
}

///|
impl @moondbg.DebugBackend for ExecutionCommandTestBackend with fn function_breakpoint_snapshots(
  self,
) {
  self.function_breakpoints.map(breakpoint => {
    @moondbg.FunctionBreakpointSnapshot::verified(
      breakpoint.id(),
      breakpoint.display_name(),
    )
  })
}

///|
impl @moondbg.DebugBackend for ExecutionCommandTestBackend with fn take_output(
  self,
) {
  let output = self.output.copy()
  self.output.clear()
  output
}

///|
impl @moondbg.DebugBackend for ExecutionCommandTestBackend with fn disconnect(
  _self,
) {
  ()
}

///|
impl @moondbg.DebugBackend for ExecutionCommandTestBackend with fn close(_self) {
  ()
}

///|
fn execution_command_test_context() -> (
  ExecutionCommandTestBackend,
  ReplContext,
) raise {
  let backend = ExecutionCommandTestBackend::new()
  let session = @moondbg.DebugSession::new("/tmp/program", backend)
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
  let debug_context = @moondbg.DebugContext::new("example/app/main", [
    ("util", "example/lib/util"),
  ])
  let session = @moondbg.DebugSession::new(
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
    is @moondbg.MoonBitFunctionFamily("_M0FP37example3app4main6helper"),
  )
  assert_true(
    imported.selector()
    is @moondbg.MoonBitFunctionFamily("_M0FP37example3lib4util5parse"),
  )
  assert_true(
    entry.selector() is @moondbg.ExactPhysicalFunction("moonbit_main"),
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
  let first = execute_framework_command(context, "break repl/main.mbt:4")
  guard first.events is [BreakpointPendingPresentation(1, source, 4)] else {
    fail("break should return its pending breakpoint event")
  }
  assert_eq(source, "repl/main.mbt")
  let second = execute_framework_command(context, "b repl/main.mbt:7")
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
async test "P6 break path and debugger-state failures are structured" {
  let (_backend, context) = execution_command_test_context()
  let missing = execute_framework_command(
    context, "break repl/no-such-source.mbt:4",
  )
  assert_true(
    missing.events
    is [
      BreakpointErrorPresentation(
        BreakpointSourceNotFound("repl/no-such-source.mbt")
      ),
    ],
  )
  let directory = execute_framework_command(context, "break repl:4")
  assert_true(
    directory.events
    is [BreakpointErrorPresentation(BreakpointSourceNotAFile("repl"))],
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
  let stopped = execute_framework_command(context, "break repl/main.mbt:4")
  assert_true(
    stopped.events
    is [
      BreakpointErrorPresentation(
        BreakpointOperationNotAllowed(@moondbg.Stopped, "add source breakpoint")
      ),
    ],
  )
}

///|
async test "P6 run and r call launch and preserve ordered events" {
  let (backend, context) = execution_command_test_context()
  context.session.add_source_breakpoint("/tmp/test.mbt", 4) |> ignore
  backend.output.push(@moondbg.DebugOutput::standard_output("program-output"))
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
  assert_true(breakpoint.status() is @moondbg.Verified)
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
    is [OperationNotAllowedPresentation(@moondbg.Ready, "step over")],
  )
  let (failed_backend, failed_context) = execution_command_test_context()
  failed_context.session.run() |> ignore
  failed_backend.output.push(
    @moondbg.DebugOutput::standard_error("adapter-output"),
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
