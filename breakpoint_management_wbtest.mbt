///|
impl DebugBackend for RecordingBackend with fn synchronize_breakpoints(
  self,
  configuration,
) {
  self.syncs += 1
  if self.reject_sync {
    raise BreakpointSyncError::BreakpointSyncRejected(
      "management rejected without changes",
    )
  }
  if self.uncertain_sync {
    raise BreakpointSyncError::BreakpointSyncUncertain(
      "partial synchronization",
    )
  }
  if self.malformed_sync {
    return BreakpointSyncResult::new([], [])
  }
  let sources : Array[BreakpointSnapshot] = []
  let functions : Array[FunctionBreakpointSnapshot] = []
  let old_sources = self.breakpoints.copy()
  let old_functions = self.function_breakpoints.copy()
  for breakpoint in configuration.sources() {
    if breakpoint.enabled() {
      if old_sources
        .iter()
        .find_first(item => item.id() == breakpoint.id() && item.enabled())
        is Some(_) {
        sources.push(
          BreakpointSnapshot::verified(
            breakpoint.id(),
            breakpoint.source_path(),
            breakpoint.requested_line(),
            Some(breakpoint.requested_line()),
          ),
        )
      } else {
        sources.push(self.install_source_breakpoint(breakpoint))
      }
    }
  }
  for breakpoint in configuration.functions() {
    if breakpoint.enabled() {
      if old_functions
        .iter()
        .find_first(item => item.id() == breakpoint.id() && item.enabled())
        is Some(_) {
        functions.push(
          FunctionBreakpointSnapshot::verified(
            breakpoint.id(),
            breakpoint.display_name(),
          ),
        )
      } else {
        functions.push(self.install_function_breakpoint(breakpoint))
      }
    }
  }
  self.breakpoints.clear()
  self.breakpoints.append(configuration.sources())
  self.function_breakpoints.clear()
  self.function_breakpoints.append(configuration.functions())
  BreakpointSyncResult::new(sources, functions)
}

///|
impl DebugBackend for RecordingBackend with fn abandon_execution(self) {
  self.abandons += 1
  self.closed = true
}

///|
async test "management keeps monotonic mixed ids and desired state across launches" {
  let backend = RecordingBackend::new()
  let session = DebugSession::new(
    "/tmp/program",
    backend,
    debug_context=DebugContext::new("example/main", []),
  )
  session.add_source_breakpoint("/tmp/main.mbt", 4, display_path="main.mbt")
  |> ignore
  session.add_function_breakpoint(FunctionBreakpointRequest::current("main"))
  |> ignore
  session.add_source_breakpoint("/tmp/main.mbt", 4) |> ignore
  session.manage_breakpoint(2, DeleteBreakpoint) |> ignore
  session.manage_breakpoint(1, DisableBreakpoint) |> ignore
  let added = session.add_function_breakpoint(
    FunctionBreakpointRequest::current("foo"),
  )
  assert_eq(added.id(), 4)
  assert_eq(session.breakpoints().map(item => item.id), [1, 3, 4])
  assert_eq(session.breakpoints()[0].enabled, false)
  assert_true(
    session.breakpoints()[0].target is SourceTarget(display_path="main.mbt", ..),
  )
  assert_eq(backend.syncs, 0)
  let copied = session.breakpoint_configuration().sources()
  copied.clear()
  assert_eq(session.breakpoint_configuration().sources().length(), 2)
  session.run() |> ignore
  assert_eq(backend.breakpoint_launches[0], [3])
  assert_eq(backend.function_breakpoint_launches[0], [4])
  assert_true(session.breakpoints()[0].installation is NotInstalled)
  session.continue_execution() |> ignore
  assert_true(
    session.breakpoints()[1].installation is PreviousInstallation(Verified),
  )
  session.run() |> ignore
  assert_eq(backend.breakpoint_launches[1], [3])
  assert_eq(backend.function_breakpoint_launches[1], [4])
}

///|
async test "management is idempotent and preserves stopped selections and observations" {
  let backend = RecordingBackend::new()
  backend.stack = Some(
    StackSnapshot::new(
      ThreadSelection::initial(),
      [
        StackFrameSnapshot::new(
          0,
          "leaf",
          "leaf",
          None,
          Some("/tmp/main.mbt"),
          Some(4),
          Some(1),
          MoonBitUserFrame,
        ),
        StackFrameSnapshot::new(
          1,
          "caller",
          "caller",
          None,
          Some("/tmp/main.mbt"),
          Some(8),
          Some(1),
          MoonBitUserFrame,
        ),
      ],
      0,
      2,
      Some(2),
      true,
    ),
  )
  let session = DebugSession::new("/tmp/program", backend)
  session.add_source_breakpoint("/tmp/main.mbt", 4) |> ignore
  session.add_source_breakpoint("/tmp/main.mbt", 4) |> ignore
  session.run() |> ignore
  session.select_frame(1) |> ignore
  let epoch = session.stop_epoch()
  let frame = session.selected_frame()
  let stack_requests = backend.stack_requests
  session.find_variable(VariablePath::root("x")) |> ignore
  assert_eq(session.manage_breakpoint(1, EnableBreakpoint).changed, false)
  assert_eq(backend.syncs, 0)
  assert_eq(session.manage_breakpoint(1, DisableBreakpoint).changed, true)
  assert_eq(backend.syncs, 1)
  assert_eq(session.manage_breakpoint(1, DisableBreakpoint).changed, false)
  assert_eq(backend.syncs, 1)
  assert_eq(
    backend.breakpoints.filter(item => item.enabled()).map(item => item.id()),
    [2],
  )
  session.manage_breakpoint(1, EnableBreakpoint) |> ignore
  session.manage_breakpoint(2, DeleteBreakpoint) |> ignore
  assert_eq(session.stop_epoch(), epoch)
  assert_eq(session.selected_frame(), frame)
  assert_eq(backend.stack_requests, stack_requests)
  assert_eq(backend.abandons, 0)
  session.find_variable(VariablePath::root("x")) |> ignore
  assert_eq(backend.frame_selections, [1, 1])
}

///|
async test "enabling unresolved targets retains enabled configuration and rejected result" {
  let backend = RecordingBackend::new()
  let session = DebugSession::new(
    "/tmp/program",
    backend,
    debug_context=DebugContext::new("example/main", []),
  )
  session.add_source_breakpoint("/tmp/main.mbt", 4) |> ignore
  session.add_function_breakpoint(FunctionBreakpointRequest::current("missing"))
  |> ignore
  session.manage_breakpoint(1, DisableBreakpoint) |> ignore
  session.manage_breakpoint(2, DisableBreakpoint) |> ignore
  session.run() |> ignore
  backend.reject_installs = true
  let source = session.manage_breakpoint(1, EnableBreakpoint)
  assert_true(source.breakpoint.enabled)
  assert_true(
    source.breakpoint.installation is CurrentInstallation(Rejected(_)),
  )
  let function = session.manage_breakpoint(2, EnableBreakpoint)
  assert_true(function.breakpoint.enabled)
  assert_true(
    function.breakpoint.installation is CurrentInstallation(Rejected(_)),
  )
  assert_true(session.state() is Stopped)
  assert_eq(backend.abandons, 0)
  session.run() |> ignore
  assert_eq(backend.breakpoint_launches[1], [1])
  assert_eq(backend.function_breakpoint_launches[1], [2])
}

///|
async test "uncertain enable retains desired enabled state for a new execution" {
  let backend = RecordingBackend::new()
  let session = DebugSession::new("/tmp/program", backend)
  session.add_source_breakpoint("/tmp/main.mbt", 4) |> ignore
  session.manage_breakpoint(1, DisableBreakpoint) |> ignore
  session.run() |> ignore
  backend.uncertain_sync = true
  try {
    session.manage_breakpoint(1, EnableBreakpoint) |> ignore
    fail("expected uncertain enable")
  } catch {
    AdapterFailure(_) => ()
    error => raise error
  }
  assert_true(session.breakpoints()[0].enabled)
  assert_true(session.state() is Ready)
  assert_eq(backend.abandons, 1)
  backend.uncertain_sync = false
  session.run() |> ignore
  assert_eq(backend.breakpoint_launches[1], [1])
}

///|
async test "management failures preserve delete disable configuration and recover uncertainty" {
  let backend = RecordingBackend::new()
  let session = DebugSession::new("/tmp/program", backend)
  session.add_source_breakpoint("/tmp/main.mbt", 4) |> ignore
  session.run() |> ignore
  backend.reject_sync = true
  try {
    session.manage_breakpoint(1, DisableBreakpoint) |> ignore
    fail("expected confirmed rejection")
  } catch {
    BreakpointManagementRejected(_) => ()
    error => raise error
  }
  assert_true(session.state() is Stopped)
  assert_true(session.breakpoints()[0].enabled)
  assert_eq(backend.abandons, 0)
  backend.reject_sync = false
  backend.uncertain_sync = true
  try {
    session.manage_breakpoint(1, DeleteBreakpoint) |> ignore
    fail("expected uncertain failure")
  } catch {
    AdapterFailure(message) =>
      assert_true(message.contains("current execution was discarded"))
    error => raise error
  }
  assert_true(session.state() is Ready)
  assert_eq(backend.abandons, 1)
  assert_eq(session.breakpoints().map(item => item.id), [1])
  assert_true(session.breakpoints()[0].enabled)
  backend.uncertain_sync = false
  session.run() |> ignore
  assert_eq(backend.breakpoint_launches[1], [1])
}

///|
async test "incomplete domain synchronization result cannot confirm disable success" {
  let backend = RecordingBackend::new()
  let session = DebugSession::new("/tmp/program", backend)
  session.add_source_breakpoint("/tmp/main.mbt", 4) |> ignore
  session.add_source_breakpoint("/tmp/main.mbt", 5) |> ignore
  session.run() |> ignore
  backend.malformed_sync = true
  try {
    session.manage_breakpoint(1, DisableBreakpoint) |> ignore
    fail("incomplete reply")
  } catch {
    AdapterFailure(message) =>
      assert_eq(
        message, "incomplete breakpoint synchronization result; current execution was discarded",
      )
    error => raise error
  }
  assert_true(session.state() is Ready)
  assert_eq(session.breakpoints().map(item => item.enabled), [true, true])
  assert_eq(backend.abandons, 1)
}

///|
async test "management rejects invalid ids and forbidden phases without synchronization" {
  let backend = RecordingBackend::new()
  let session = DebugSession::new("/tmp/program", backend)
  session.add_source_breakpoint("/tmp/main.mbt", 4) |> ignore
  for id in [-1, 0, 2] {
    try {
      session.manage_breakpoint(id, DeleteBreakpoint) |> ignore
      fail("invalid id")
    } catch {
      BreakpointNotFound(actual) => assert_eq(actual, id)
      error => raise error
    }
  }
  session.manage_breakpoint(1, DeleteBreakpoint) |> ignore
  try {
    session.manage_breakpoint(1, DeleteBreakpoint) |> ignore
    fail("deleted id")
  } catch {
    BreakpointNotFound(1) => ()
    error => raise error
  }
  for phase in [Running, Failed, Exited] {
    session.application.transition_without_stop(phase)
    try {
      session.manage_breakpoint(1, EnableBreakpoint) |> ignore
      fail("invalid phase")
    } catch {
      OperationNotAllowed(state~, ..) => assert_eq(state, phase)
      error => raise error
    }
  }
  assert_eq(backend.syncs, 0)
}
