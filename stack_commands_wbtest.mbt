///|
priv struct StackCommandTestBackend {
  mut exit_on_launch : Bool
  mut fail_stack : Bool
  stack_responses : Array[@debugger.StackSnapshot]
  mut next_stack_response : Int
  stack_windows : Array[@debugger.StackWindow]
  variable_frames : Array[Int]
  local_frames : Array[Int]
  local_results : Map[Int, @debugger.LocalVariablesSnapshot]
  mut fail_locals : Bool
}

///|
fn StackCommandTestBackend::new() -> StackCommandTestBackend {
  {
    exit_on_launch: false,
    fail_stack: false,
    stack_responses: [],
    next_stack_response: 0,
    stack_windows: [],
    variable_frames: [],
    local_frames: [],
    local_results: Map([]),
    fail_locals: false,
  }
}

///|
fn stack_command_frame(
  physical_index : Int,
  name : String,
  source_path : String?,
  line : Int?,
  kind : @debugger.FrameKind,
) -> @debugger.StackFrameSnapshot raise @debugger.StackSnapshotError {
  @debugger.StackFrameSnapshot::new(
    physical_index,
    name,
    name,
    None,
    source_path,
    line,
    Some(1),
    kind,
  )
}

///|
fn stack_command_frames() -> Array[@debugger.StackFrameSnapshot] raise @debugger.StackSnapshotError {
  [
    stack_command_frame(0, "native_entry", None, None, @debugger.NativeFrame),
    stack_command_frame(
      1,
      "leaf",
      Some("/tmp/leaf.mbt"),
      Some(10),
      @debugger.MoonBitUserFrame,
    ),
    stack_command_frame(
      2,
      "runtime_bridge",
      Some("/tmp/runtime.c"),
      Some(20),
      @debugger.MoonBitRuntimeFrame,
    ),
    stack_command_frame(3, "caller", None, None, @debugger.MoonBitUserFrame),
    stack_command_frame(
      4,
      "main",
      Some("/tmp/main.mbt"),
      Some(40),
      @debugger.MoonBitUserFrame,
    ),
  ]
}

///|
fn stack_command_snapshot(
  loaded_count : Int,
  complete : Bool,
) -> @debugger.StackSnapshot raise @debugger.StackSnapshotError {
  @debugger.StackSnapshot::new(
    @debugger.ThreadSelection::initial(),
    stack_command_frames().filter(frame => frame.physical_index() < loaded_count),
    0,
    loaded_count,
    Some(5),
    complete,
  )
}

///|
fn stack_command_stop() -> @debugger.StopSnapshot {
  @debugger.StopSnapshot::new(
    "breakpoint",
    "leaf",
    Some("/tmp/leaf.mbt"),
    Some(10),
    Some(1),
  )
}

///|
impl @debugger.DebugBackend for StackCommandTestBackend with fn launch(
  self,
  _executable,
  _breakpoints,
  _function_breakpoints,
) {
  if self.exit_on_launch {
    @debugger.RunOutcome::exited(Some(0))
  } else {
    @debugger.RunOutcome::stopped(stack_command_stop())
  }
}

///|
fn StackCommandTestBackend::install_source_breakpoint(
  _self : StackCommandTestBackend,
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
fn StackCommandTestBackend::install_function_breakpoint(
  _self : StackCommandTestBackend,
  breakpoint : @debugger.FunctionBreakpoint,
) -> @debugger.FunctionBreakpointSnapshot {
  @debugger.FunctionBreakpointSnapshot::verified(
    breakpoint.id(),
    breakpoint.display_name(),
  )
}

///|
impl @debugger.DebugBackend for StackCommandTestBackend with fn continue_execution(
  _self,
  _thread,
) {
  @debugger.RunOutcome::exited(Some(0))
}

///|
impl @debugger.DebugBackend for StackCommandTestBackend with fn next(
  _self,
  _thread,
) {
  @debugger.RunOutcome::stopped(stack_command_stop())
}

///|
impl @debugger.DebugBackend for StackCommandTestBackend with fn step(
  _self,
  _thread,
) {
  @debugger.RunOutcome::stopped(stack_command_stop())
}

///|
impl @debugger.DebugBackend for StackCommandTestBackend with fn finish(
  _self,
  _thread,
) {
  @debugger.RunOutcome::stopped(stack_command_stop())
}

///|
impl @debugger.DebugBackend for StackCommandTestBackend with fn stack_snapshot(
  self,
  thread,
  window,
) {
  self.stack_windows.push(window)
  if self.fail_stack {
    raise @debugger.DebugBackendError::failure("stack command backend failed")
  }
  guard self.next_stack_response < self.stack_responses.length() else {
    return @debugger.StackSnapshot::new(thread, [], 0, 0, Some(0), true)
  }
  let response = self.stack_responses[self.next_stack_response]
  self.next_stack_response += 1
  response
}

///|
impl @debugger.DebugBackend for StackCommandTestBackend with fn find_variable(
  self,
  _thread,
  frame,
  path,
) {
  self.variable_frames.push(frame.index())
  @debugger.VariableLookupResult::found(
    @debugger.VariableSnapshot::new(path.display_name(), "42", Some("Int")),
  )
}

///|
impl @debugger.DebugBackend for StackCommandTestBackend with fn local_variables(
  self,
  thread,
  frame,
) {
  self.local_frames.push(frame.index())
  if self.fail_locals {
    raise @debugger.DebugBackendError::failure("locals adapter failed")
  }
  self.local_results
  .get(frame.index())
  .unwrap_or(@debugger.LocalVariablesSnapshot::scope_unavailable(thread, frame))
}

///|
impl @debugger.DebugBackend for StackCommandTestBackend with fn breakpoint_snapshots(
  _self,
) {
  []
}

///|
impl @debugger.DebugBackend for StackCommandTestBackend with fn function_breakpoint_snapshots(
  _self,
) {
  []
}

///|
impl @debugger.DebugBackend for StackCommandTestBackend with fn take_output(
  _self,
) {
  []
}

///|
impl @debugger.DebugBackend for StackCommandTestBackend with fn disconnect(
  _self,
) {
  ()
}

///|
impl @debugger.DebugBackend for StackCommandTestBackend with fn close(_self) {
  ()
}

///|
fn stack_command_context(
  backend : StackCommandTestBackend,
) -> ReplContext raise {
  let session = @debugger.DebugSession::new("/tmp/program", backend)
  ReplContext::new(session, default_command_registry(), HumanRenderer::new())
}

///|
test "P4 stack command parsers and aliases are strict" {
  let registry = default_command_registry()
  for
    valid in [
      "backtrace", "bt", "bt --all", "frame 0", "frame 001", "up", "down",
    ] {
    assert_true(registry.parse_line(valid) is RegistryCommand(_), msg=valid)
  }
  for
    invalid in [
      "bt all", "bt --all more", "bt -a", "frame", "frame -1", "frame +1", "frame 1 2",
      "frame 999999999999999999999999999999999", "up 1", "down 1",
    ] {
    assert_true(registry.parse_line(invalid) is RegistryInvalid(_), msg=invalid)
  }
  assert_true(registry.parse_line("btr") is RegistryUnknown)
  assert_true(registry.parse_line("back") is RegistryUnknown)
  assert_true(registry.parse_line("fra 0") is RegistryUnknown)
  guard registry.lookup("bt") is Some(backtrace) else {
    fail("bt should be a fixed alias")
  }
  assert_eq(backtrace.name, "backtrace")
  assert_eq(backtrace.aliases, ["bt"])
}

///|
async test "P4 backtrace loads the complete stack and preserves physical gaps" {
  let backend = StackCommandTestBackend::new()
  backend.stack_responses.push(stack_command_snapshot(2, false))
  backend.stack_responses.push(stack_command_snapshot(5, true))
  let context = stack_command_context(backend)
  context.session.run() |> ignore
  let result = execute_framework_command(context, "bt")
  guard result.events is [BacktracePresentation(view)] else {
    fail("backtrace should return one structured view")
  }
  assert_eq(view.frames.map(frame => frame.physical_index()), [1, 3, 4])
  assert_eq(view.selected_frame, Some(1))
  assert_eq(backend.stack_windows, [
    @debugger.StackWindow::initial(),
    @debugger.StackWindow::new(2, 20),
  ])
  let all = execute_framework_command(context, "bt --all")
  guard all.events is [BacktracePresentation(all_view)] else {
    fail("backtrace --all should return one structured view")
  }
  assert_eq(all_view.frames.map(frame => frame.physical_index()), [
    0, 1, 2, 3, 4,
  ])
  assert_eq(backend.stack_windows.length(), 2)
}

///|
async test "P4 frame up and down return selection and source events" {
  let backend = StackCommandTestBackend::new()
  backend.stack_responses.push(stack_command_snapshot(5, true))
  let context = stack_command_context(backend)
  context.session.run() |> ignore
  let hidden = execute_framework_command(context, "frame 0")
  guard hidden.events
    is [
      FrameSelectedPresentation(native),
      SourceViewPresentation(native_source),
    ] else {
    fail("frame should select hidden physical frames")
  }
  assert_eq(native.physical_index(), 0)
  assert_eq(native_source.source_path, None)
  assert_eq(
    frame_selected_line(native),
    "Selected frame #0: native_entry at source unavailable",
  )
  let up = execute_framework_command(context, "up")
  guard up.events
    is [FrameSelectedPresentation(leaf), SourceViewPresentation(leaf_source)] else {
    fail("up should select the next visible MoonBit caller")
  }
  assert_eq(leaf.physical_index(), 1)
  assert_eq(leaf_source.line_count, DEFAULT_SOURCE_LINE_COUNT)
  let caller_result = execute_framework_command(context, "up")
  guard caller_result.events
    is [
      FrameSelectedPresentation(caller),
      SourceViewPresentation(caller_source),
    ] else {
    fail("a second up should skip the runtime frame")
  }
  assert_eq(caller.physical_index(), 3)
  assert_eq(caller_source.source_path, None)
  assert_eq(
    frame_selected_line(caller),
    "Selected frame #3: caller at source unavailable",
  )
  let down = execute_framework_command(context, "down")
  guard down.events is [FrameSelectedPresentation(down), _] else {
    fail("down should return to the visible callee")
  }
  assert_eq(down.physical_index(), 1)
  let listed = execute_framework_command(context, "list")
  guard listed.events is [SourceViewPresentation(list_source)] else {
    fail("list should follow frame navigation")
  }
  assert_eq(list_source.source_path, Some("/tmp/leaf.mbt"))
  assert_eq(list_source.line, Some(10))
  execute_framework_command(context, "p answer") |> ignore
  assert_eq(backend.variable_frames, [1])
}

///|
async test "P4 navigation reports boundaries missing frames and no selection" {
  let backend = StackCommandTestBackend::new()
  backend.stack_responses.push(stack_command_snapshot(5, true))
  let context = stack_command_context(backend)
  context.session.run() |> ignore
  let missing = execute_framework_command(context, "frame 99")
  assert_true(
    missing.events is [FrameSelectionFailurePresentation(FrameUnavailable(99))],
  )
  context.session.select_frame(4) |> ignore
  let caller_boundary = execute_framework_command(context, "up")
  assert_true(
    caller_boundary.events
    is [FrameSelectionFailurePresentation(CallerBoundary(4))],
  )
  context.session.select_frame(1) |> ignore
  let callee_boundary = execute_framework_command(context, "down")
  assert_true(
    callee_boundary.events
    is [FrameSelectionFailurePresentation(CalleeBoundary(1))],
  )

  let empty_backend = StackCommandTestBackend::new()
  empty_backend.stack_responses.push(
    @debugger.StackSnapshot::new(
      @debugger.ThreadSelection::initial(),
      [],
      0,
      0,
      Some(0),
      true,
    ),
  )
  let empty_context = stack_command_context(empty_backend)
  empty_context.session.run() |> ignore
  let no_selection = execute_framework_command(empty_context, "up")
  assert_true(
    no_selection.events
    is [FrameSelectionFailurePresentation(CurrentFrameUnavailable)],
  )
  assert_true(
    execute_framework_command(empty_context, "down").events
    is [FrameSelectionFailurePresentation(CurrentFrameUnavailable)],
  )
}

///|
async test "P4 default backtrace falls back for complete non-MoonBit stacks" {
  let backend = StackCommandTestBackend::new()
  backend.stack_responses.push(
    @debugger.StackSnapshot::new(
      @debugger.ThreadSelection::initial(),
      [
        stack_command_frame(
          0,
          "native_entry",
          Some("/tmp/native.c"),
          Some(1),
          @debugger.NativeFrame,
        ),
        stack_command_frame(
          1,
          "runtime",
          Some("/tmp/runtime.c"),
          Some(2),
          @debugger.MoonBitRuntimeFrame,
        ),
      ],
      0,
      2,
      Some(2),
      true,
    ),
  )
  let context = stack_command_context(backend)
  context.session.run() |> ignore
  let result = execute_framework_command(context, "bt")
  guard result.events is [BacktracePresentation(view)] else {
    fail("native-only backtrace should remain diagnostic")
  }
  assert_eq(view.frames.map(frame => frame.physical_index()), [0])
  assert_eq(view.selected_frame, Some(0))
}

///|
async test "P4 stack commands map states and adapter failures to presentations" {
  let ready_backend = StackCommandTestBackend::new()
  let ready = stack_command_context(ready_backend)
  assert_true(
    execute_framework_command(ready, "bt").events
    is [
      OperationNotAllowedPresentation(
        @debugger.Ready,
        "load the complete stack"
      ),
    ],
  )
  assert_true(
    execute_framework_command(ready, "frame 0").events
    is [OperationNotAllowedPresentation(@debugger.Ready, "select a frame")],
  )

  let exited_backend = StackCommandTestBackend::new()
  exited_backend.exit_on_launch = true
  let exited = stack_command_context(exited_backend)
  exited.session.run() |> ignore
  exited.session.disconnect()
  assert_true(
    execute_framework_command(exited, "up").events
    is [
      OperationNotAllowedPresentation(@debugger.Exited, "select a caller frame"),
    ],
  )

  let failed_backend = StackCommandTestBackend::new()
  failed_backend.stack_responses.push(stack_command_snapshot(2, false))
  let failed = stack_command_context(failed_backend)
  failed.session.run() |> ignore
  failed_backend.fail_stack = true
  assert_true(
    execute_framework_command(failed, "bt").events
    is [AdapterFailurePresentation("stack command backend failed")],
  )
}

///|
test "P4 backtrace and frame presentation text is stable" {
  let stack = stack_command_snapshot(5, true)
  let view = BacktraceView::from_stack(stack, Some(1), show_all=false)
  assert_eq(backtrace_lines(view), [
    "* #1 [moonbit] leaf at /tmp/leaf.mbt:10", "  #3 [moonbit] caller at source unavailable",
    "  #4 [moonbit] main at /tmp/main.mbt:40",
  ])
  let hidden = BacktraceView::from_stack(stack, Some(0), show_all=false)
  assert_eq(backtrace_lines(hidden), [
    "  #1 [moonbit] leaf at /tmp/leaf.mbt:10", "  #3 [moonbit] caller at source unavailable",
    "  #4 [moonbit] main at /tmp/main.mbt:40", "  Current frame #0 is hidden; use 'bt --all' to show it.",
  ])
}
