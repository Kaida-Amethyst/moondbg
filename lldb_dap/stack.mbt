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
fn parse_stack_frames(body : Json) -> (Array[ParsedStackFrame], Int) {
  guard body is { "stackFrames": Array(frames), .. } else { return ([], 0) }
  let parsed : Array[ParsedStackFrame] = []
  for physical_index, frame in frames {
    guard parse_stack_frame(frame, physical_index) is Some(item) else {
      continue
    }
    parsed.push(item)
  }
  (parsed, frames.length())
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
fn stack_frame_kind(frame : ParsedStackFrame) -> @moondbg.FrameKind {
  match frame.source_path {
    Some(source_path) if source_path.has_suffix(".mbt") =>
      @moondbg.MoonBitUserFrame
    Some(_) => @moondbg.NativeFrame
    None => @moondbg.UnknownFrame
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
) -> @moondbg.StackFrameSnapshot raise @moondbg.StackSnapshotError {
  @moondbg.StackFrameSnapshot::new(
    self.physical_index,
    self.name,
    self.name,
    None,
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
async fn DebugExecution::build_stop_snapshot(
  self : DebugExecution,
) -> @moondbg.StopSnapshot {
  let thread_id = self.resolve_stopped_thread()
  let response = self.request("stackTrace", {
    "threadId": thread_id,
    "startFrame": 0,
    "levels": 20,
  })
  let (frames, loaded_count) = parse_stack_frames(response.body())
  guard select_parsed_stack_frame(frames) is Some(frame) else {
    raise InvalidMessage(response.body())
  }
  self.machine.select_frame(frame.id, physical_index=frame.physical_index)
  self.stack_snapshot = Some(
    @moondbg.StackSnapshot::new(
      @moondbg.ThreadSelection::initial(),
      frames.map(item => item.snapshot()),
      0,
      loaded_count,
      stack_total_frames_hint(response.body()),
      loaded_count < 20,
    ),
  )
  @moondbg.StopSnapshot::new(
    self.stop_reason,
    frame.name,
    frame.source_path,
    frame.line,
    frame.column,
  )
}
