///|
fn panic_test_outcome() -> RunOutcome {
  RunOutcome::stopped(
    StopSnapshot::new("MoonBit panic", "moonbit_panic", None, None, None),
  )
}

///|
async test "panic selects the nearest project frame and aligns source locals and print" {
  let backend = RecordingBackend::new()
  backend.stack = Some(test_stack_snapshot(ThreadSelection::initial()))
  let session = DebugSession::new("/tmp/program", backend, project_sources=[
    "/tmp/main.mbt",
  ])
  guard session.accept_outcome(panic_test_outcome()) is Stopped(stop) else {
    fail("stop")
  }
  assert_eq(stop.function_name(), "main")
  assert_eq(stop.source_path(), Some("/tmp/main.mbt"))
  assert_eq(stop.notice(), None)
  assert_eq(session.selected_frame().map(frame => frame.index()), Some(4))
  assert_eq(
    session.stack_snapshot().map(stack => stack.frames().length()),
    Some(5),
  )
  session.find_variable(VariablePath::root("answer")) |> ignore
  session.local_variables() |> ignore
  assert_eq(backend.frame_selections, [4])
  assert_eq(backend.local_frame_selections, [4])
  session.select_frame(0) |> ignore
  assert_eq(session.selected_frame().map(frame => frame.index()), Some(0))
  // Each subsequent panic reselects the project frame, not the old manual one.
  session.accept_outcome(panic_test_outcome()) |> ignore
  assert_eq(session.selected_frame().map(frame => frame.index()), Some(4))
}

///|
async test "panic without matching project sources never selects a library frame" {
  for sources in [[], ["/tmp/leaf.mbt.extra"], ["/another/main.mbt"]] {
    let backend = RecordingBackend::new()
    backend.stack = Some(test_stack_snapshot(ThreadSelection::initial()))
    let session = DebugSession::new(
      "/tmp/program",
      backend,
      project_sources=sources,
    )
    guard session.accept_outcome(panic_test_outcome()) is Stopped(stop) else {
      fail("stop")
    }
    assert_eq(stop.source_path(), None)
    assert_eq(stop.line(), None)
    assert_true(stop.notice() is Some(_))
    assert_eq(session.selected_frame(), None)
    assert_eq(
      session.stack_snapshot().map(stack => stack.frames().length()),
      Some(5),
    )
    assert_true(
      try {
        session.find_variable(VariablePath::root("answer")) |> ignore
        false
      } catch {
        NoFrameSelected => true
        _ => false
      },
    )
    assert_eq(backend.variable_lookups, 0)
    session.select_frame(1) |> ignore
    session.find_variable(VariablePath::root("answer")) |> ignore
    assert_eq(backend.frame_selections, [1])
  }
}

///|
async test "panic searches later stack pages past library frames" {
  let backend = RecordingBackend::new()
  let frames = [test_stack_frame(0, "core_abort", MoonBitUserFrame)]
  backend.stack_responses.push(
    StackSnapshot::new(
      ThreadSelection::initial(),
      frames.copy(),
      0,
      1,
      Some(3),
      false,
    ),
  )
  frames.push(
    StackFrameSnapshot::new(
      1,
      "bad_line",
      "bad_line",
      None,
      Some("/tmp/leaf.mbt"),
      Some(0),
      None,
      MoonBitUserFrame,
    ),
  )
  frames.push(test_stack_frame(2, "leaf", MoonBitUserFrame))
  backend.stack_responses.push(
    StackSnapshot::new(ThreadSelection::initial(), frames, 0, 3, Some(3), true),
  )
  let session = DebugSession::new("/tmp/program", backend, project_sources=[
    "/tmp/leaf.mbt",
  ])
  session.accept_outcome(panic_test_outcome()) |> ignore
  assert_eq(session.selected_frame().map(frame => frame.index()), Some(2))
  assert_eq(backend.stack_windows, [
    StackWindow::initial(),
    StackWindow::new(1, 20),
  ])
  assert_eq(
    session.stack_snapshot().map(stack => stack.frames().length()),
    Some(3),
  )
}

///|
async test "manual stack expansion does not reselect a frame after missing panic context" {
  let backend = RecordingBackend::new()
  let frames = [test_stack_frame(0, "native", NativeFrame)]
  backend.stack_responses.push(
    StackSnapshot::new(
      ThreadSelection::initial(),
      frames.copy(),
      0,
      1,
      Some(2),
      false,
    ),
  )
  frames.push(test_stack_frame(1, "core_abort", MoonBitUserFrame))
  backend.stack_responses.push(
    StackSnapshot::new(ThreadSelection::initial(), frames, 0, 2, Some(2), true),
  )
  let session = DebugSession::new("/tmp/program", backend)
  session.accept_outcome(panic_test_outcome()) |> ignore
  session.complete_stack_snapshot() |> ignore
  assert_eq(session.selected_frame(), None)
  assert_eq(backend.stack_requests, 2)
}

///|
async test "ordinary breakpoints keep existing selection independent of project source context" {
  let backend = RecordingBackend::new()
  backend.stack = Some(test_stack_snapshot(ThreadSelection::initial()))
  let session = DebugSession::new("/tmp/program", backend, project_sources=[
    "/tmp/main.mbt",
  ])
  session.run() |> ignore
  assert_eq(session.selected_frame().map(frame => frame.index()), Some(1))
}
