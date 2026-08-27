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
fn parse_stack_frame(frame : Json) -> ParsedStackFrame? {
  guard frame is { "id": Number(id, ..), "name": String(name), .. } else {
    return None
  }
  Some({
    id: id.to_int(),
    name,
    source_path: stack_frame_source_path(frame),
    line: stack_frame_line(frame),
    column: stack_frame_column(frame),
  })
}

///|
fn select_stack_frame(body : Json) -> ParsedStackFrame? {
  guard body is { "stackFrames": Array(frames), .. } else { return None }
  let mut first : ParsedStackFrame? = None
  for frame in frames {
    guard parse_stack_frame(frame) is Some(parsed) else { continue }
    if first is None {
      first = Some(parsed)
    }
    if parsed.source_path is Some(source_path) && source_path.has_suffix(".mbt") {
      return Some(parsed)
    }
  }
  first
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
  guard select_stack_frame(response.body()) is Some(frame) else {
    raise InvalidMessage(response.body())
  }
  self.machine.select_frame(frame.id)
  @moondbg.StopSnapshot::new(
    self.stop_reason,
    frame.name,
    frame.source_path,
    frame.line,
    frame.column,
  )
}
