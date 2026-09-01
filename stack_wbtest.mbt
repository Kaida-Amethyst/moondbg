///|
fn test_stack_frame(
  physical_index : Int,
  function_name : String,
  kind : FrameKind,
) -> StackFrameSnapshot raise StackSnapshotError {
  StackFrameSnapshot::new(
    physical_index,
    function_name,
    function_name,
    None,
    Some("/tmp/\{function_name}.mbt"),
    Some(physical_index + 1),
    Some(1),
    kind,
  )
}

///|
fn test_stack_snapshot(
  thread : ThreadSelection,
) -> StackSnapshot raise StackSnapshotError {
  StackSnapshot::new(
    thread,
    [
      test_stack_frame(0, "native_entry", NativeFrame),
      test_stack_frame(1, "leaf", MoonBitUserFrame),
      test_stack_frame(2, "runtime_bridge", MoonBitRuntimeFrame),
      test_stack_frame(3, "unknown_bridge", UnknownFrame),
      test_stack_frame(4, "main", MoonBitUserFrame),
    ],
    0,
    5,
    Some(5),
    true,
  )
}

///|
test "P2 stack snapshot preserves physical indices and partial range metadata" {
  let thread = ThreadSelection::at(3)
  let stack = test_stack_snapshot(thread)
  assert_eq(stack.thread(), thread)
  assert_eq(stack.loaded_start(), 0)
  assert_eq(stack.loaded_count(), 5)
  assert_eq(stack.loaded_end(), 5)
  assert_eq(stack.total_frames_hint(), Some(5))
  assert_true(stack.is_complete())
  assert_true(stack.is_loaded(0))
  assert_true(!stack.is_loaded(5))
  assert_eq(stack.visible_frames().map(frame => frame.physical_index()), [1, 4])
  assert_eq(stack.default_selection().map(frame => frame.index()), Some(1))
  guard stack.default_selection() is Some(leaf) else {
    fail("the nearest MoonBit user frame should be selected")
  }
  assert_true(stack.visible_caller(leaf) is FrameAvailable({ index: 4, }))
  guard stack.selection(4) is Some(main) else {
    fail("physical frame four should be selectable")
  }
  assert_true(stack.visible_callee(main) is FrameAvailable({ index: 1, }))
  assert_true(stack.visible_caller(main) is VisibleFrameBoundary)
  assert_true(stack.visible_callee(leaf) is VisibleFrameBoundary)

  let partial = StackSnapshot::new(
    thread,
    [
      test_stack_frame(20, "deep", MoonBitUserFrame),
      test_stack_frame(21, "native", NativeFrame),
      test_stack_frame(22, "deeper", MoonBitUserFrame),
    ],
    20,
    3,
    Some(40),
    false,
  )
  guard partial.selection(22) is Some(deeper) else {
    fail("the loaded physical frame should be selectable")
  }
  assert_true(
    partial.visible_caller(deeper) is MoreFramesRequired(start_frame=23),
  )
  guard partial.selection(20) is Some(deep) else {
    fail("the first loaded physical frame should be selectable")
  }
  assert_true(partial.visible_callee(deep) is MoreFramesRequired(start_frame=0))
}

///|
test "P2 default selection falls back when no user frame is available" {
  let thread = ThreadSelection::initial()
  let partial = StackSnapshot::new(
    thread,
    [
      test_stack_frame(0, "native", NativeFrame),
      test_stack_frame(1, "runtime", MoonBitRuntimeFrame),
    ],
    0,
    2,
    Some(40),
    false,
  )
  assert_eq(partial.default_selection(), None)
  let native_only = StackSnapshot::new(
    thread,
    [test_stack_frame(0, "native", NativeFrame)],
    0,
    1,
    Some(1),
    true,
  )
  assert_eq(
    native_only.default_selection().map(frame => frame.index()),
    Some(0),
  )
  let empty = StackSnapshot::new(thread, [], 0, 0, Some(0), true)
  assert_eq(empty.default_selection(), None)
  assert_eq(empty.visible_frames(), [])
}

///|
test "P2 stack construction rejects ranges with inconsistent physical frames" {
  let thread = ThreadSelection::initial()
  assert_true(
    try {
      StackSnapshot::new(
        thread,
        [
          test_stack_frame(1, "one", MoonBitUserFrame),
          test_stack_frame(0, "zero", MoonBitUserFrame),
        ],
        0,
        2,
        None,
        true,
      )
      |> ignore
      false
    } catch {
      UnexpectedPhysicalFrameIndex(expected=0, actual=1) => true
      _ => false
    },
  )
  assert_true(
    try {
      StackSnapshot::new(
        thread,
        [test_stack_frame(0, "zero", MoonBitUserFrame)],
        0,
        2,
        None,
        false,
      )
      |> ignore
      false
    } catch {
      LoadedFrameCountMismatch(expected=2, actual=1) => true
      _ => false
    },
  )
  assert_true(
    try {
      StackSnapshot::new(
        thread,
        [test_stack_frame(2, "two", MoonBitUserFrame)],
        2,
        1,
        None,
        true,
      )
      |> ignore
      false
    } catch {
      CompleteStackStartsAfterZero(2) => true
      _ => false
    },
  )
}

///|
test "P2 logical thread selection rejects negative indices" {
  assert_true(
    try {
      ThreadSelection::at(-1) |> ignore
      false
    } catch {
      InvalidLogicalThreadIndex(-1) => true
      _ => false
    },
  )
}

///|
async test "P2 session owns default explicit and visible frame selection" {
  let backend = RecordingBackend::new()
  backend.stack = Some(test_stack_snapshot(ThreadSelection::initial()))
  let session = DebugSession::new("/tmp/program", backend)
  guard session.run() is RunOutcome::Stopped(_) else {
    fail("the fake backend should stop")
  }
  assert_eq(session.selected_thread().map(thread => thread.index()), Some(0))
  assert_eq(session.selected_frame().map(frame => frame.index()), Some(1))
  assert_eq(
    session.stack_snapshot().map(stack => stack.loaded_count()),
    Some(5),
  )
  assert_eq(backend.stack_requests, 1)
  assert_eq(backend.stack_windows, [StackWindow::initial()])

  let runtime = session.select_frame(2)
  assert_eq(runtime.physical_index(), 2)
  assert_eq(session.selected_frame().map(frame => frame.index()), Some(2))
  session.find_variable(VariablePath::root("answer")) |> ignore
  assert_eq(backend.frame_selections, [2])
  let caller = session.select_visible_caller_frame()
  assert_eq(caller.physical_index(), 4)
  assert_eq(session.selected_frame().map(frame => frame.index()), Some(4))
  assert_true(
    try {
      session.select_visible_caller_frame() |> ignore
      false
    } catch {
      NoVisibleCaller(4) => true
      _ => false
    },
  )
  let callee = session.select_visible_callee_frame()
  assert_eq(callee.physical_index(), 1)
  assert_true(
    try {
      session.select_visible_callee_frame() |> ignore
      false
    } catch {
      NoVisibleCallee(1) => true
      _ => false
    },
  )
  assert_true(
    try {
      session.select_frame(5) |> ignore
      false
    } catch {
      FrameNotLoaded(5) => true
      _ => false
    },
  )

  session.select_frame(4) |> ignore
  guard session.next() is RunOutcome::Stopped(_) else {
    fail("the fake backend should establish a new stop")
  }
  assert_eq(session.stop_epoch().map(stop => stop.number()), Some(2))
  assert_eq(session.selected_frame().map(frame => frame.index()), Some(1))
  assert_eq(backend.stack_requests, 2)
  guard session.continue_execution() is RunOutcome::Exited(Some(0)) else {
    fail("the fake backend should exit")
  }
  assert_eq(session.stack_snapshot(), None)
  assert_eq(session.selected_frame(), None)
  assert_true(
    try {
      session.select_frame(0) |> ignore
      false
    } catch {
      OperationNotAllowed(state=Ready, action="select a frame") => true
      _ => false
    },
  )
  guard session.run() is RunOutcome::Stopped(_) else {
    fail("a replacement execution should establish a new stop")
  }
  assert_eq(session.execution_epoch().map(epoch => epoch.number()), Some(2))
  assert_eq(session.stop_epoch().map(stop => stop.number()), Some(1))
  assert_eq(session.selected_frame().map(frame => frame.index()), Some(1))
  session.close()
}

///|
async test "P2 empty and failed stack acquisition never create a stable selection" {
  let empty_backend = RecordingBackend::new()
  empty_backend.stack = Some(
    StackSnapshot::new(ThreadSelection::initial(), [], 0, 0, Some(0), true),
  )
  let empty_session = DebugSession::new("/tmp/program", empty_backend)
  empty_session.run() |> ignore
  assert_true(empty_session.state() is Stopped)
  assert_eq(empty_session.selected_frame(), None)
  assert_true(
    try {
      empty_session.select_visible_caller_frame() |> ignore
      false
    } catch {
      NoFrameSelected => true
      _ => false
    },
  )
  empty_session.close()

  let failed_backend = RecordingBackend::new()
  failed_backend.fail_stack = true
  let failed_session = DebugSession::new("/tmp/program", failed_backend)
  assert_true(
    try {
      failed_session.run() |> ignore
      false
    } catch {
      AdapterFailure("recording backend failed to inspect the stack") => true
      _ => false
    },
  )
  assert_true(failed_session.state() is Ready)
  assert_eq(
    failed_session.execution_epoch().map(epoch => epoch.number()),
    Some(1),
  )
  assert_eq(failed_session.stop_epoch(), None)
  assert_eq(failed_session.stack_snapshot(), None)
  assert_eq(failed_session.selected_thread(), None)
  assert_eq(failed_session.selected_frame(), None)
}

///|
async test "P2 partial stack without a user frame stays unselected" {
  let backend = RecordingBackend::new()
  backend.stack = Some(
    StackSnapshot::new(
      ThreadSelection::initial(),
      [
        test_stack_frame(0, "native", NativeFrame),
        test_stack_frame(1, "runtime", MoonBitRuntimeFrame),
      ],
      0,
      2,
      Some(40),
      false,
    ),
  )
  let session = DebugSession::new("/tmp/program", backend)
  session.run() |> ignore
  assert_true(session.state() is Stopped)
  assert_eq(session.selected_frame(), None)
  assert_eq(
    session.stack_snapshot().map(stack => stack.is_complete()),
    Some(false),
  )
  let native = session.select_frame(0)
  assert_eq(native.physical_index(), 0)
  assert_eq(session.selected_frame().map(frame => frame.index()), Some(0))
  session.close()
}

///|
async test "P2 rejects a stack snapshot for another logical thread" {
  let backend = RecordingBackend::new()
  backend.stack = Some(test_stack_snapshot(ThreadSelection::at(1)))
  let session = DebugSession::new("/tmp/program", backend)
  assert_true(
    try {
      session.run() |> ignore
      false
    } catch {
      AdapterFailure("backend returned a stack for a different logical thread") =>
        true
      _ => false
    },
  )
  assert_true(session.state() is Ready)
  assert_eq(session.stop_epoch(), None)
  assert_eq(session.stack_snapshot(), None)
}

///|
test "P2 frame selection is rejected outside a stable stop" {
  for phase in [Ready, Running, Exited, Failed] {
    let backend = RecordingBackend::new()
    let session = DebugSession::new("/tmp/program", backend)
    session.application.transition_without_stop(phase)
    assert_true(
      try {
        session.select_frame(0) |> ignore
        false
      } catch {
        OperationNotAllowed(state~, action="select a frame") => state == phase
        _ => false
      },
    )
    session.close()
  }
}
