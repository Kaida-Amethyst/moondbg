///|
priv struct RecordingBackend {
  mut launches : Int
  mut continues : Int
  mut nexts : Int
  mut steps : Int
  mut finishes : Int
  mut variable_lookups : Int
  mut local_lookups : Int
  mut stack_requests : Int
  stack_windows : Array[StackWindow]
  mut executable : String?
  breakpoints : Array[SourceBreakpoint]
  function_breakpoints : Array[FunctionBreakpoint]
  breakpoint_launches : Array[Array[Int]]
  function_breakpoint_launches : Array[Array[Int]]
  thread_selections : Array[Int]
  frame_selections : Array[Int]
  local_frame_selections : Array[Int]
  mut stack : StackSnapshot?
  stack_responses : Array[StackSnapshot]
  mut next_stack_response : Int
  mut fail_stack : Bool
  mut fail_next : Bool
  mut observe_running_entry : (() -> Bool)?
  mut running_entries : Int
  mut invalid_running_entries : Int
  mut source_installs : Int
  mut function_installs : Int
  mut reject_installs : Bool
  mut fail_installs : Bool
  mut syncs : Int
  mut reject_sync : Bool
  mut uncertain_sync : Bool
  mut malformed_sync : Bool
  mut abandons : Int
  mut closed : Bool
}

///|
fn RecordingBackend::new() -> RecordingBackend {
  {
    launches: 0,
    continues: 0,
    nexts: 0,
    steps: 0,
    finishes: 0,
    variable_lookups: 0,
    local_lookups: 0,
    stack_requests: 0,
    stack_windows: [],
    executable: None,
    breakpoints: [],
    function_breakpoints: [],
    breakpoint_launches: [],
    function_breakpoint_launches: [],
    thread_selections: [],
    frame_selections: [],
    local_frame_selections: [],
    stack: None,
    stack_responses: [],
    next_stack_response: 0,
    fail_stack: false,
    fail_next: false,
    observe_running_entry: None,
    running_entries: 0,
    invalid_running_entries: 0,
    source_installs: 0,
    function_installs: 0,
    reject_installs: false,
    fail_installs: false,
    syncs: 0,
    reject_sync: false,
    uncertain_sync: false,
    malformed_sync: false,
    abandons: 0,
    closed: false,
  }
}

///|
fn RecordingBackend::record_running_entry(self : RecordingBackend) -> Unit {
  self.running_entries += 1
  if self.observe_running_entry is Some(observe) && !observe() {
    self.invalid_running_entries += 1
  }
}

///|
fn recording_stop() -> StopSnapshot {
  StopSnapshot::new(
    "breakpoint",
    "main",
    Some("/tmp/main.mbt"),
    Some(4),
    Some(1),
  )
}

///|
fn recording_stack(
  thread : ThreadSelection,
) -> StackSnapshot raise StackSnapshotError {
  let stop = recording_stop()
  StackSnapshot::new(
    thread,
    [
      StackFrameSnapshot::new(
        0,
        stop.function_name(),
        stop.function_name(),
        None,
        stop.source_path(),
        stop.line(),
        stop.column(),
        MoonBitUserFrame,
      ),
    ],
    0,
    1,
    Some(1),
    true,
  )
}

///|
impl DebugBackend for RecordingBackend with fn launch(
  self,
  executable,
  breakpoints,
  function_breakpoints,
) {
  self.record_running_entry()
  self.launches += 1
  self.executable = Some(executable)
  self.breakpoints.clear()
  for breakpoint in breakpoints {
    self.breakpoints.push(breakpoint)
  }
  self.function_breakpoints.clear()
  for breakpoint in function_breakpoints {
    self.function_breakpoints.push(breakpoint)
  }
  self.function_breakpoint_launches.push(
    function_breakpoints.map(breakpoint => breakpoint.id()),
  )
  self.breakpoint_launches.push(breakpoints.map(breakpoint => breakpoint.id()))
  RunOutcome::stopped(recording_stop())
}

///|
fn RecordingBackend::install_source_breakpoint(
  self : RecordingBackend,
  breakpoint : SourceBreakpoint,
) -> BreakpointSnapshot raise {
  self.source_installs += 1
  self.breakpoints.push(breakpoint)
  if self.fail_installs {
    raise DebugBackendError::BackendFailure(
      "recording backend failed to install a breakpoint",
    )
  }
  if self.reject_installs {
    return BreakpointSnapshot::rejected(
      breakpoint.id(),
      breakpoint.source_path(),
      breakpoint.requested_line(),
      "recording backend rejected the source breakpoint",
    )
  }
  BreakpointSnapshot::verified(
    breakpoint.id(),
    breakpoint.source_path(),
    breakpoint.requested_line(),
    Some(breakpoint.requested_line()),
  )
}

///|
fn RecordingBackend::install_function_breakpoint(
  self : RecordingBackend,
  breakpoint : FunctionBreakpoint,
) -> FunctionBreakpointSnapshot raise {
  self.function_installs += 1
  self.function_breakpoints.push(breakpoint)
  if self.fail_installs {
    raise DebugBackendError::BackendFailure(
      "recording backend failed to install a breakpoint",
    )
  }
  if self.reject_installs {
    return FunctionBreakpointSnapshot::rejected(
      breakpoint.id(),
      breakpoint.display_name(),
      "recording backend rejected the function breakpoint",
    )
  }
  FunctionBreakpointSnapshot::verified(
    breakpoint.id(),
    breakpoint.display_name(),
  )
}

///|
impl DebugBackend for RecordingBackend with fn continue_execution(self, thread) {
  self.record_running_entry()
  self.continues += 1
  self.thread_selections.push(thread.index())
  RunOutcome::exited(Some(0))
}

///|
impl DebugBackend for RecordingBackend with fn next(self, thread) {
  self.record_running_entry()
  self.nexts += 1
  self.thread_selections.push(thread.index())
  if self.fail_next {
    raise DebugBackendError::BackendFailure("recording backend failed on next")
  }
  RunOutcome::stopped(recording_stop())
}

///|
impl DebugBackend for RecordingBackend with fn step(self, thread) {
  self.record_running_entry()
  self.steps += 1
  self.thread_selections.push(thread.index())
  RunOutcome::stopped(recording_stop())
}

///|
impl DebugBackend for RecordingBackend with fn finish(self, thread) {
  self.record_running_entry()
  self.finishes += 1
  self.thread_selections.push(thread.index())
  RunOutcome::stopped(recording_stop())
}

///|
impl DebugBackend for RecordingBackend with fn stack_snapshot(
  self,
  thread,
  window,
) {
  self.stack_requests += 1
  self.stack_windows.push(window)
  if self.fail_stack {
    raise DebugBackendError::BackendFailure(
      "recording backend failed to inspect the stack",
    )
  }
  if self.next_stack_response < self.stack_responses.length() {
    let response = self.stack_responses[self.next_stack_response]
    self.next_stack_response += 1
    return response
  }
  match self.stack {
    Some(stack) => stack
    None => recording_stack(thread)
  }
}

///|
impl DebugBackend for RecordingBackend with fn find_variable(
  self,
  thread,
  frame,
  path,
) {
  self.variable_lookups += 1
  self.thread_selections.push(thread.index())
  self.frame_selections.push(frame.index())
  let name = path.display_name()
  VariableLookupResult::found(VariableSnapshot::new(name, "42", Some("Int")))
}

///|
impl DebugBackend for RecordingBackend with fn local_variables(
  self,
  thread,
  frame,
) {
  self.local_lookups += 1
  self.local_frame_selections.push(frame.index())
  LocalVariablesSnapshot::available(thread, frame, [
    LocalVariableSnapshot::new(
      "answer",
      Some("Int"),
      LocalVariableAvailable(LocalScalar("42")),
    ),
  ])
}

///|
impl DebugBackend for RecordingBackend with fn breakpoint_snapshots(self) {
  self.breakpoints.map(breakpoint => {
    id: breakpoint.id(),
    source_path: breakpoint.source_path(),
    requested_line: breakpoint.requested_line(),
    actual_line: Some(breakpoint.requested_line()),
    status: Verified,
    locations: [],
  })
}

///|
impl DebugBackend for RecordingBackend with fn function_breakpoint_snapshots(
  self,
) {
  self.function_breakpoints.map(breakpoint => {
    FunctionBreakpointSnapshot::verified(
      breakpoint.id(),
      breakpoint.display_name(),
    )
  })
}

///|
impl DebugBackend for RecordingBackend with fn take_output(_self) {
  []
}

///|
impl DebugBackend for RecordingBackend with fn disconnect(self) {
  self.closed = true
}

///|
impl DebugBackend for RecordingBackend with fn close(self) {
  self.closed = true
}

///|
async test "P4 application state owns epochs selections and stable breakpoint replay" {
  let backend = RecordingBackend::new()
  let session = DebugSession::new("/tmp/program", backend)
  backend.observe_running_entry = Some(() => {
    session.state() is Running &&
    session.stop_epoch() is None &&
    session.last_stop_snapshot() is None &&
    session.selected_thread() is None &&
    session.selected_frame() is None
  })
  assert_eq(session.execution_epoch(), None)
  assert_eq(session.stop_epoch(), None)
  let pending = session.add_source_breakpoint("/tmp/main.mbt", 4)
  assert_eq(pending.id(), 1)
  assert_true(pending.status() is Pending)
  assert_true(session.state() is Ready)
  guard session.run() is RunOutcome::Stopped(snapshot) else {
    fail("recording backend should stop")
  }
  assert_eq(snapshot.source_path(), Some("/tmp/main.mbt"))
  assert_true(session.state() is Stopped)
  guard session.execution_epoch() is Some(execution) else {
    fail("launch should establish an execution epoch")
  }
  assert_eq(execution.number(), 1)
  guard session.stop_epoch() is Some(stop) else {
    fail("stable stop should establish a stop epoch")
  }
  assert_eq(stop.execution(), execution)
  assert_eq(stop.number(), 1)
  assert_eq(session.selected_thread().map(thread => thread.index()), Some(0))
  assert_eq(session.selected_frame().map(frame => frame.index()), Some(0))
  assert_eq(backend.launches, 1)
  assert_eq(backend.executable, Some("/tmp/program"))
  guard backend.breakpoints is [breakpoint] else {
    fail("session should pass one logical source breakpoint")
  }
  assert_eq(breakpoint.id(), 1)
  assert_eq(breakpoint.requested_line(), 4)
  guard session.source_breakpoints() is [verified] else {
    fail("backend breakpoint result should be visible through the session")
  }
  assert_true(verified.status() is Verified)
  guard session.run() is RunOutcome::Stopped(_) else {
    fail("re-running should delegate another launch")
  }
  guard session.execution_epoch() is Some(execution) else {
    fail("re-launch should establish a new execution epoch")
  }
  assert_eq(execution.number(), 2)
  guard session.stop_epoch() is Some(stop) else {
    fail("re-launch should establish its first stop")
  }
  assert_eq(stop.execution(), execution)
  assert_eq(stop.number(), 1)
  assert_eq(backend.breakpoint_launches, [[1], [1]])
  guard session.next() is RunOutcome::Stopped(_) else {
    fail("next should delegate to the backend")
  }
  assert_eq(session.stop_epoch().map(stop => stop.number()), Some(2))
  guard session.step() is RunOutcome::Stopped(_) else {
    fail("step should delegate to the backend")
  }
  assert_eq(session.stop_epoch().map(stop => stop.number()), Some(3))
  guard session.finish() is RunOutcome::Stopped(_) else {
    fail("finish should delegate to the backend")
  }
  assert_eq(session.stop_epoch().map(stop => stop.number()), Some(4))
  guard session.find_variable(VariablePath::root("answer"))
    is VariableFound(variable) else {
    fail("variable lookup should delegate to the backend")
  }
  assert_eq(variable.name(), "answer")
  assert_eq(variable.value(), "42")
  guard session.local_variables().variables() is [local_summary] else {
    fail("local-variable lookup should delegate to the backend")
  }
  assert_eq(local_summary.name(), "answer")
  assert_true(session.state() is Stopped)
  assert_true(session.last_stop_snapshot() is Some(_))
  guard session.continue_execution() is RunOutcome::Exited(Some(0)) else {
    fail("recording backend should exit after continue")
  }
  assert_eq(backend.launches, 2)
  assert_eq(backend.nexts, 1)
  assert_eq(backend.steps, 1)
  assert_eq(backend.finishes, 1)
  assert_eq(backend.variable_lookups, 1)
  assert_eq(backend.local_lookups, 1)
  assert_eq(backend.continues, 1)
  assert_eq(backend.running_entries, 6)
  assert_eq(backend.invalid_running_entries, 0)
  assert_eq(backend.thread_selections, [0, 0, 0, 0, 0])
  assert_eq(backend.frame_selections, [0])
  assert_eq(backend.local_frame_selections, [0])
  assert_true(session.state() is Ready)
  assert_eq(session.execution_epoch().map(epoch => epoch.number()), Some(2))
  assert_eq(session.stop_epoch(), None)
  assert_true(session.last_stop_snapshot() is None)
  assert_eq(session.selected_thread(), None)
  assert_eq(session.selected_frame(), None)
  let second = session.add_source_breakpoint("/tmp/other.mbt", 7)
  assert_eq(second.id(), 2)
  guard session.run() is RunOutcome::Stopped(_) else {
    fail("a later launch should replay all stable breakpoints")
  }
  assert_eq(backend.breakpoint_launches, [[1], [1], [1, 2]])
  assert_eq(session.execution_epoch().map(epoch => epoch.number()), Some(3))
  assert_eq(session.stop_epoch().map(stop => stop.number()), Some(1))
  assert_eq(backend.running_entries, 7)
  assert_eq(backend.invalid_running_entries, 0)
  session.close()
  assert_true(backend.closed)
  assert_true(session.state() is Exited)
  assert_eq(session.stop_epoch(), None)
  assert_true(session.last_stop_snapshot() is None)
  assert_eq(session.selected_thread(), None)
  assert_eq(session.selected_frame(), None)
}

///|
async test "P4 backend failure invalidates the stable stop and preserves execution epoch" {
  let backend = RecordingBackend::new()
  let session = DebugSession::new("/tmp/program", backend)
  backend.observe_running_entry = Some(() => {
    session.state() is Running &&
    session.stop_epoch() is None &&
    session.last_stop_snapshot() is None &&
    session.selected_thread() is None &&
    session.selected_frame() is None
  })
  guard session.run() is RunOutcome::Stopped(_) else {
    fail("recording backend should establish an initial stop")
  }
  assert_true(session.last_stop_snapshot() is Some(_))
  assert_eq(session.execution_epoch().map(epoch => epoch.number()), Some(1))
  assert_eq(session.stop_epoch().map(stop => stop.number()), Some(1))
  backend.fail_next = true
  let failed = try {
    session.next() |> ignore
    false
  } catch {
    DebugSessionError::AdapterFailure(message) =>
      message == "recording backend failed on next"
    _ => false
  }
  assert_true(failed)
  assert_true(session.state() is Ready)
  assert_eq(session.execution_epoch().map(epoch => epoch.number()), Some(1))
  assert_eq(session.stop_epoch(), None)
  assert_true(session.last_stop_snapshot() is None)
  assert_eq(session.selected_thread(), None)
  assert_eq(session.selected_frame(), None)
  assert_eq(backend.running_entries, 2)
  assert_eq(backend.invalid_running_entries, 0)
  session.close()
}

///|
async test "stopped breakpoint additions install immediately without changing the stop" {
  let backend = RecordingBackend::new()
  let debug_context = DebugContext::new("example/app/main", [])
  let session = DebugSession::new("/tmp/program", backend, debug_context~)
  let pending = session.add_source_breakpoint("/tmp/main.mbt", 4)
  assert_true(pending.status() is Pending)
  guard session.run() is RunOutcome::Stopped(_) else {
    fail("recording backend should establish a stable stop")
  }
  let execution_epoch = session.execution_epoch()
  let stop_epoch = session.stop_epoch()
  let selected_thread = session.selected_thread()
  let selected_frame = session.selected_frame()

  let source = session.add_source_breakpoint("/tmp/other.mbt", 7)
  assert_true(source.status() is Verified)
  assert_eq(source.id(), 2)
  let function = session.add_function_breakpoint(
    FunctionBreakpointRequest::current("helper"),
  )
  assert_true(function.status() is Verified)
  assert_eq(function.id(), 3)
  assert_true(session.state() is Stopped)
  assert_eq(session.execution_epoch(), execution_epoch)
  assert_eq(session.stop_epoch(), stop_epoch)
  assert_eq(session.selected_thread(), selected_thread)
  assert_eq(session.selected_frame(), selected_frame)
  assert_eq(backend.source_installs, 1)
  assert_eq(backend.function_installs, 1)
  assert_eq(backend.breakpoints.map(item => item.id()), [1, 2])
  assert_eq(backend.function_breakpoints.map(item => item.id()), [3])

  backend.reject_installs = true
  let rejected = session.add_source_breakpoint("/tmp/rejected.mbt", 9)
  assert_true(
    rejected.status()
    is Rejected("recording backend rejected the source breakpoint"),
  )
  assert_eq(rejected.id(), 4)
  assert_true(session.state() is Stopped)
  assert_eq(session.stop_epoch(), stop_epoch)
  assert_eq(backend.breakpoints.map(item => item.id()), [1, 2, 4])
  session.close()
}

///|
async test "dynamic adapter failure retains configuration for the next execution" {
  let backend = RecordingBackend::new()
  let session = DebugSession::new("/tmp/program", backend)
  session.run() |> ignore
  backend.fail_installs = true
  let failed = try {
    session.add_source_breakpoint("/tmp/retry.mbt", 6) |> ignore
    false
  } catch {
    AdapterFailure(
      "recording backend failed to install a breakpoint; current execution was discarded"
    ) => true
    _ => false
  }
  assert_true(failed)
  assert_true(session.state() is Ready)
  assert_eq(session.stop_epoch(), None)
  assert_true(session.last_stop_snapshot() is None)
  backend.fail_installs = false
  session.run() |> ignore
  assert_eq(backend.breakpoint_launches, [[], [1]])
  assert_eq(backend.breakpoints.map(item => item.id()), [1])
  session.close()
}

///|
async test "breakpoint additions reject unstable and terminal application phases" {
  for phase in [Running, Exited, Failed] {
    let backend = RecordingBackend::new()
    let session = DebugSession::new("/tmp/program", backend)
    session.application.transition_without_stop(phase)
    let rejected = try {
      session.add_source_breakpoint("/tmp/main.mbt", 4) |> ignore
      false
    } catch {
      OperationNotAllowed(state~, action~) =>
        state == phase && action == "add source breakpoint"
      _ => false
    }
    assert_true(rejected)
    assert_eq(backend.source_installs, 0)
    assert_eq(session.next_breakpoint_id, 1)
    session.close()
  }
}

///|
async test "function breakpoints resolve package context and native symbols" {
  let backend = RecordingBackend::new()
  let debug_context = DebugContext::new("example/app/main", [
    ("util", "example/lib/util"),
  ])
  let session = DebugSession::new("/tmp/program", backend, debug_context~)
  let local_breakpoint = session.add_function_breakpoint(
    FunctionBreakpointRequest::current("helper"),
  )
  let imported = session.add_function_breakpoint(
    FunctionBreakpointRequest::imported("util", "parse"),
  )
  let entry = session.add_function_breakpoint(
    FunctionBreakpointRequest::current("main"),
  )
  assert_eq(local_breakpoint.id(), 1)
  assert_eq(imported.id(), 2)
  assert_eq(entry.id(), 3)
  session.run() |> ignore
  guard backend.function_breakpoints is [local_breakpoint, imported, entry] else {
    fail("backend should receive all stable function breakpoints")
  }
  assert_true(
    local_breakpoint.selector()
    is MoonBitFunctionFamily("_M0FP37example3app4main6helper"),
  )
  assert_true(
    imported.selector()
    is MoonBitFunctionFamily("_M0FP37example3lib4util5parse"),
  )
  assert_true(entry.selector() is ExactPhysicalFunction("moonbit_main"))
  guard session.function_breakpoints() is [one, two, three] else {
    fail("function breakpoint results should be visible through the session")
  }
  assert_true(one.status() is Verified)
  assert_true(two.status() is Verified)
  assert_true(three.status() is Verified)
  assert_eq(backend.function_breakpoint_launches, [[1, 2, 3]])
  session.run() |> ignore
  assert_eq(backend.function_breakpoint_launches, [[1, 2, 3], [1, 2, 3]])
}

///|
async test "function breakpoints reject missing and unknown package context" {
  let backend = RecordingBackend::new()
  let missing = DebugSession::new("/tmp/program", backend)
  assert_true(
    try {
      missing.add_function_breakpoint(
        FunctionBreakpointRequest::current("helper"),
      )
      |> ignore
      false
    } catch {
      MissingCurrentPackage => true
      _ => false
    },
  )
  let context = DebugContext::new("example/app", [])
  let unknown = DebugSession::new(
    "/tmp/program",
    backend,
    debug_context=context,
  )
  assert_true(
    try {
      unknown.add_function_breakpoint(
        FunctionBreakpointRequest::imported("missing", "helper"),
      )
      |> ignore
      false
    } catch {
      UnknownPackageAlias("missing") => true
      _ => false
    },
  )
}
