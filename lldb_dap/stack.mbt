///|
fn first_thread_id(body : Json) -> Int? {
  guard body is { "threads": Array(threads), .. } else { return None }
  for thread in threads {
    if thread is { "id": Number(id, ..), .. } {
      return Some(id.to_int())
    }
  }
  None
}

///|
priv struct ParsedStackFrame {
  physical_index : Int
  id : Int
  name : String
  source_path : String?
  line : Int?
  column : Int?
}

///|
fn stack_frame_source_path(frame : Json) -> String? {
  match frame {
    { "source": { "path": String(source_path), .. }, .. } => Some(source_path)
    _ => None
  }
}

///|
fn stack_frame_line(frame : Json) -> Int? {
  match frame {
    { "line": Number(line, ..), .. } => Some(line.to_int())
    _ => None
  }
}

///|
fn stack_frame_column(frame : Json) -> Int? {
  match frame {
    { "column": Number(column, ..), .. } => Some(column.to_int())
    _ => None
  }
}

///|
fn parse_stack_frame(frame : Json, physical_index : Int) -> ParsedStackFrame? {
  guard frame is { "id": Number(id, ..), "name": String(name), .. } else {
    return None
  }
  Some({
    physical_index,
    id: id.to_int(),
    name,
    source_path: stack_frame_source_path(frame),
    line: stack_frame_line(frame),
    column: stack_frame_column(frame),
  })
}

///|
fn parse_stack_frames(
  body : Json,
  start_frame : Int,
) -> Array[ParsedStackFrame] raise DapSessionError {
  guard body is { "stackFrames": Array(frames), .. } else {
    raise InvalidMessage(body)
  }
  let parsed : Array[ParsedStackFrame] = []
  for offset, frame in frames {
    guard parse_stack_frame(frame, start_frame + offset) is Some(item) else {
      raise InvalidMessage(frame)
    }
    parsed.push(item)
  }
  parsed
}

///|
fn select_parsed_stack_frame(
  frames : Array[ParsedStackFrame],
) -> ParsedStackFrame? {
  for parsed in frames {
    if parsed.source_path is Some(source_path) && source_path.has_suffix(".mbt") {
      return Some(parsed)
    }
  }
  guard frames.length() > 0 else { return None }
  Some(frames[0])
}

///|
fn stack_frame_kind(frame : ParsedStackFrame) -> @debugger.FrameKind {
  match frame.source_path {
    Some(source_path) if source_path.has_suffix(".mbt") =>
      @debugger.MoonBitUserFrame
    Some(_) => @debugger.NativeFrame
    None => @debugger.UnknownFrame
  }
}

///|
fn moonbit_frame_identity(frame : ParsedStackFrame) -> (String, String?) {
  guard stack_frame_kind(frame) is @debugger.MoonBitUserFrame else {
    return (frame.name, None)
  }
  if frame.name == "moonbit_main" {
    return ("main", Some(frame.name))
  }
  let decoded = Some(@name_mangle.demangle_top_level_function(frame.name)) catch {
    _ => None
  }
  match decoded {
    Some(symbol) => (symbol.source_name(), Some(frame.name))
    None => (frame.name, None)
  }
}

///|
fn stack_total_frames_hint(body : Json) -> Int? {
  match body {
    { "totalFrames": Number(total, ..), .. } => Some(total.to_int())
    _ => None
  }
}

///|
fn ParsedStackFrame::snapshot(
  self : ParsedStackFrame,
) -> @debugger.StackFrameSnapshot raise @debugger.StackSnapshotError {
  let (display_name, linkage_name) = moonbit_frame_identity(self)
  @debugger.StackFrameSnapshot::new(
    self.physical_index,
    self.name,
    display_name,
    linkage_name,
    self.source_path,
    self.line,
    self.column,
    stack_frame_kind(self),
  )
}

///|
async fn DebugExecution::resolve_stopped_thread(self : DebugExecution) -> Int {
  match self.machine.selected_thread_id() {
    Some(thread_id) => thread_id
    None => {
      let response = self.request("threads", {})
      guard first_thread_id(response.body()) is Some(thread_id) else {
        raise InvalidMessage(response.body())
      }
      self.machine.select_thread(thread_id)
      thread_id
    }
  }
}

///|
async fn DebugExecution::load_stack_window(
  self : DebugExecution,
  thread : @debugger.ThreadSelection,
  window : @debugger.StackWindow,
) -> @debugger.StackSnapshot {
  let thread_id = self.selected_thread_id(thread, "inspect the stack")
  guard self.machine.current_stop_epoch() is Some(expected_epoch) else {
    raise InvalidSessionTransition(
      state=self.machine.state,
      action="load stack frames",
    )
  }
  let loaded_end = match self.stack_snapshot {
    Some(stack) => stack.loaded_end()
    None => 0
  }
  if window.start() < loaded_end {
    guard self.stack_snapshot is Some(stack) else {
      raise InvalidSessionTransition(
        state=self.machine.state,
        action="reuse cached stack frames",
      )
    }
    if stack.is_complete() {
      return stack
    }
    let requested_end = window.start() + window.count()
    guard requested_end <= loaded_end else {
      raise OverlappingStackRequest(loaded_end~, requested_end~)
    }
    return stack
  }
  guard window.start() == loaded_end else {
    raise NonContiguousStackRequest(expected=loaded_end, actual=window.start())
  }
  if self.stack_snapshot is Some(stack) && stack.is_complete() {
    return stack
  }

  let response = self.request("stackTrace", {
    "threadId": thread_id,
    "startFrame": window.start(),
    "levels": window.count(),
  })
  guard self.machine.current_stop_epoch() == Some(expected_epoch) else {
    raise StaleStackPage(
      expected_epoch~,
      actual_epoch=self.machine.current_stop_epoch(),
    )
  }
  let page = parse_stack_frames(response.body(), window.start())
  guard page.length() <= window.count() else {
    raise StackPageTooLarge(requested=window.count(), actual=page.length())
  }
  let page_ids : Map[Int, Bool] = Map([])
  for frame in page {
    guard self.machine.frame_id(frame.physical_index) is None else {
      raise DuplicatePhysicalFrameIndex(frame.physical_index)
    }
    guard self.machine.frame_index(frame.id) is None &&
      page_ids.get(frame.id) is None else {
      raise DuplicateStackFrameId(frame.id)
    }
    page_ids.set(frame.id, true)
  }

  let frames : Array[@debugger.StackFrameSnapshot] = []
  let previous_hint = match self.stack_snapshot {
    Some(stack) => {
      for frame in stack.frames() {
        frames.push(frame)
      }
      stack.total_frames_hint()
    }
    None => None
  }
  for frame in page {
    frames.push(frame.snapshot())
  }
  let total_frames_hint = match stack_total_frames_hint(response.body()) {
    Some(total) => Some(total)
    None => previous_hint
  }
  let snapshot = @debugger.StackSnapshot::new(
    thread,
    frames,
    0,
    frames.length(),
    total_frames_hint,
    page.length() < window.count(),
  )
  for frame in page {
    self.machine.remember_frame(frame.physical_index, frame.id)
  }
  self.stack_snapshot = Some(snapshot)
  snapshot
}

///|
async fn DebugExecution::build_stop_snapshot(
  self : DebugExecution,
) -> @debugger.StopSnapshot {
  self.resolve_stopped_thread() |> ignore
  let stack = self.load_stack_window(
    @debugger.ThreadSelection::initial(),
    @debugger.StackWindow::initial(),
  )
  let frames : Array[ParsedStackFrame] = []
  for snapshot in stack.frames() {
    guard self.machine.frame_id(snapshot.physical_index()) is Some(frame_id) else {
      raise InvalidSessionTransition(
        state=self.machine.state,
        action="select the stopped frame",
      )
    }
    frames.push({
      physical_index: snapshot.physical_index(),
      id: frame_id,
      name: snapshot.raw_name(),
      source_path: snapshot.source_path(),
      line: snapshot.line(),
      column: snapshot.column(),
    })
  }
  guard select_parsed_stack_frame(frames) is Some(frame) else {
    raise InvalidMessage({ "stackFrames": [] })
  }
  @debugger.StopSnapshot::new(
    self.stop_reason,
    frame.snapshot().display_name(),
    frame.source_path,
    frame.line,
    frame.column,
  )
}
