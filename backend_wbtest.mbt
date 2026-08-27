///|
priv struct RecordingBackend {
  mut launches : Int
  mut continues : Int
  mut nexts : Int
  mut steps : Int
  mut finishes : Int
  mut variable_lookups : Int
  mut executable : String?
  breakpoints : Array[SourceBreakpoint]
  mut fail_next : Bool
  mut observe_running_entry : (() -> Bool)?
  mut running_entries : Int
  mut invalid_running_entries : Int
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
    executable: None,
    breakpoints: [],
    fail_next: false,
    observe_running_entry: None,
    running_entries: 0,
    invalid_running_entries: 0,
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
impl DebugBackend for RecordingBackend with fn launch(
  self,
  executable,
  breakpoints,
) {
  self.record_running_entry()
  self.launches += 1
  self.executable = Some(executable)
  self.breakpoints.clear()
  for breakpoint in breakpoints {
    self.breakpoints.push(breakpoint)
  }
  Stopped(recording_stop())
}

///|
impl DebugBackend for RecordingBackend with fn continue_execution(self) {
  self.record_running_entry()
  self.continues += 1
  Exited(Some(0))
}

///|
impl DebugBackend for RecordingBackend with fn next(self) {
  self.record_running_entry()
  self.nexts += 1
  if self.fail_next {
    raise DebugBackendError::BackendFailure("recording backend failed on next")
  }
  Stopped(recording_stop())
}

///|
impl DebugBackend for RecordingBackend with fn step(self) {
  self.record_running_entry()
  self.steps += 1
  Stopped(recording_stop())
}

///|
impl DebugBackend for RecordingBackend with fn finish(self) {
  self.record_running_entry()
  self.finishes += 1
  Stopped(recording_stop())
}

///|
impl DebugBackend for RecordingBackend with fn find_variable(self, name) {
  self.variable_lookups += 1
  VariableFound({ name, value: "42", type_name: Some("Int"), })
}

///|
impl DebugBackend for RecordingBackend with fn breakpoint_snapshots(self) {
  self.breakpoints.map(breakpoint => {
    id: breakpoint.id(),
    source_path: breakpoint.source_path(),
    requested_line: breakpoint.requested_line(),
    actual_line: Some(breakpoint.requested_line()),
    status: Verified,
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
async test "P1 DebugSession owns configuration and delegates capabilities through the backend port" {
  let backend = RecordingBackend::new()
  let session = DebugSession::new("/tmp/program", backend)
  backend.observe_running_entry = Some(() => {
    session.state() is Running && session.last_stop_snapshot() is None
  })
  let pending = session.add_source_breakpoint("/tmp/main.mbt", 4)
  assert_eq(pending.id(), 1)
  assert_true(pending.status() is Pending)
  assert_true(session.state() is Ready)
  guard session.run() is Stopped(snapshot) else {
    fail("recording backend should stop")
  }
  assert_eq(snapshot.source_path(), Some("/tmp/main.mbt"))
  assert_true(session.state() is Stopped)
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
  guard session.run() is Stopped(_) else {
    fail("re-running should delegate another launch")
  }
  guard session.next() is Stopped(_) else {
    fail("next should delegate to the backend")
  }
  guard session.step() is Stopped(_) else {
    fail("step should delegate to the backend")
  }
  guard session.finish() is Stopped(_) else {
    fail("finish should delegate to the backend")
  }
  guard session.find_variable("answer") is VariableFound(variable) else {
    fail("variable lookup should delegate to the backend")
  }
  assert_eq(variable.name(), "answer")
  assert_eq(variable.value(), "42")
  assert_true(session.state() is Stopped)
  assert_true(session.last_stop_snapshot() is Some(_))
  guard session.continue_execution() is Exited(Some(0)) else {
    fail("recording backend should exit after continue")
  }
  assert_eq(backend.launches, 2)
  assert_eq(backend.nexts, 1)
  assert_eq(backend.steps, 1)
  assert_eq(backend.finishes, 1)
  assert_eq(backend.variable_lookups, 1)
  assert_eq(backend.continues, 1)
  assert_eq(backend.running_entries, 6)
  assert_eq(backend.invalid_running_entries, 0)
  assert_true(session.state() is Ready)
  assert_true(session.last_stop_snapshot() is None)
  session.close()
  assert_true(backend.closed)
  assert_true(session.state() is Exited)
}

///|
async test "P1 backend failure maps to a session error and clears the previous stop" {
  let backend = RecordingBackend::new()
  let session = DebugSession::new("/tmp/program", backend)
  backend.observe_running_entry = Some(() => {
    session.state() is Running && session.last_stop_snapshot() is None
  })
  guard session.run() is Stopped(_) else {
    fail("recording backend should establish an initial stop")
  }
  assert_true(session.last_stop_snapshot() is Some(_))
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
  assert_true(session.last_stop_snapshot() is None)
  assert_eq(backend.running_entries, 2)
  assert_eq(backend.invalid_running_entries, 0)
  session.close()
}
