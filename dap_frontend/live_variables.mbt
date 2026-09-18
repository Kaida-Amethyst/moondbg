///|
priv enum VariableTarget {
  Locals(Int)
  Children(Int, @lldb_dap.VariableNode, Int, Int, Bool)
}

///|
priv struct VariableJob {
  seq : Int
  epoch : Int
  target : VariableTarget
  start : Int
  count : Int
}

///|
priv struct InspectionState {
  mut next_frame : Int
  mut next_reference : Int
  frames : Map[Int, Int]
  reverse_frames : Map[Int, Int]
  references : Map[Int, VariableTarget]
  pending : Map[Int, VariableJob]
  jobs : @async.Queue[VariableJob]
}

///|
fn InspectionState::new() -> InspectionState {
  {
    next_frame: 1,
    next_reference: 1,
    frames: Map([]),
    reverse_frames: Map([]),
    references: Map([]),
    pending: Map([]),
    jobs: @async.Queue(kind=Blocking(64)),
  }
}

///|
fn nonnegative_argument(args : Json, key : String, default~ : Int) -> Int raise {
  guard args is Object(fields) else {
    raise LiveError("Expected request arguments")
  }
  guard fields.get(key) is Some(value) else { return default }
  guard value is Number(number, ..) &&
    number >= 0 &&
    number <= 2147483647 &&
    number == number.to_int().to_double() else {
    raise LiveError("\{key} must be a non-negative integer")
  }
  number.to_int()
}

///|
fn InspectionState::map_frames(
  self : InspectionState,
  frames : Array[Json],
) -> Unit raise {
  for frame in frames {
    let raw = nonnegative_argument(frame, "id", default=-1)
    guard raw >= 0 && frame is Object(fields) else {
      raise LiveError("Invalid stack frame")
    }
    let id = match self.reverse_frames.get(raw) {
      Some(id) => id
      None => {
        guard self.next_frame < 2147483647 else {
          raise LiveError("Frame handle space exhausted")
        }
        let id = self.next_frame
        self.next_frame += 1
        self.frames.set(id, raw)
        self.reverse_frames.set(raw, id)
        id
      }
    }
    fields.set("id", Json(id))
  }
}

///|
fn InspectionState::reference(
  self : InspectionState,
  target : VariableTarget,
) -> Int raise {
  guard self.next_reference < 2147483647 else {
    raise LiveError("Variable handle space exhausted")
  }
  let id = self.next_reference
  self.next_reference += 1
  self.references.set(id, target)
  id
}

///|
fn LiveSession::inspection_epoch(self : LiveSession) -> Int? {
  if self.stopped && !self.exited && !self.ended && !self.closing {
    Some(self.execution_revision)
  } else {
    None
  }
}

///|
async fn LiveSession::invalidate_inspection(
  self : LiveSession,
  writer : &@io.Writer,
) -> Unit {
  self.inspection.frames.clear()
  self.inspection.reverse_frames.clear()
  self.inspection.references.clear()
  for job in self.inspection.pending.values() {
    send_client(
      writer,
      self.client.response(
        job.seq,
        "variables",
        error=Some("Variable request belongs to a stale stop"),
      ),
    )
  }
  self.inspection.pending.clear()
  // Keep request IDs in the router until their responses arrive, but release
  // workers immediately; a stale reply must never fulfill a newer request.
  for request in self.pending.values() {
    if request.inspection_reply is Some(reply) {
      reply.close(error=LiveError("Variable request belongs to a stale stop"))
    }
  }
}

///|
fn InspectionState::node_json(
  self : InspectionState,
  frame : Int,
  node : @lldb_dap.VariableNode,
) -> Json raise {
  let indexed = node.indexed_children > 0
  let length = if indexed { node.indexed_children } else { node.named_children }
  let reference = if length > 0 {
    self.reference(Children(frame, node, 0, length, indexed))
  } else {
    0
  }
  let fields : Map[String, Json] = {
    "name": Json(node.name),
    "value": Json(node.value),
    "variablesReference": Json(reference),
    "namedVariables": Json(node.named_children),
    "indexedVariables": Json(node.indexed_children),
  }
  if node.type_name is Some(name) {
    fields.set("type", Json(name))
  }
  Json(fields)
}

///|
fn InspectionState::ranges(
  self : InspectionState,
  frame : Int,
  node : @lldb_dap.VariableNode,
  start : Int,
  count : Int,
  indexed : Bool,
) -> Array[Json] raise {
  let width = for width = 100; (count - 1) / width >= 100; {
    continue width * 100
  } nobreak {
    width
  }
  let result : Array[Json] = []
  for offset = 0; offset < count; {
    let size = width.min(count - offset)
    let first = start + offset
    let reference = self.reference(Children(frame, node, first, size, indexed))
    result.push({
      "name": "[\{first}..\{first + size - 1}]",
      "value": "\{size} items",
      "variablesReference": reference,
      "indexedVariables": if indexed {
        size
      } else {
        0
      },
      "namedVariables": if indexed {
        0
      } else {
        size
      },
    })
    continue offset + size
  }
  result
}

///|
async fn LiveSession::inspect_client(
  self : LiveSession,
  writer : &@io.Writer,
  seq : Int,
  command : String,
  args : Json,
) -> Unit {
  try {
    guard self.inspection_epoch() is Some(epoch) else {
      raise LiveError("Variables require a stopped program")
    }
    if command == "scopes" {
      let frame = nonnegative_argument(args, "frameId", default=-1)
      guard self.inspection.frames.get(frame) is Some(raw) else {
        raise LiveError("Unknown or stale frameId; request stackTrace again")
      }
      let reference = self.inspection.reference(Locals(raw))
      send_client(
        writer,
        self.client.response(seq, command, body={
          "scopes": [
            {
              "name": "Locals",
              "presentationHint": "locals",
              "expensive": false,
              "variablesReference": reference,
            },
          ],
        }),
      )
      return
    }
    let id = nonnegative_argument(args, "variablesReference", default=-1)
    guard self.inspection.references.get(id) is Some(target) else {
      raise LiveError("Unknown or stale variablesReference")
    }
    let start = nonnegative_argument(args, "start", default=0)
    let count = nonnegative_argument(args, "count", default=0)
    let filter = match args {
      { "filter": String("indexed"), .. } => Some(true)
      { "filter": String("named"), .. } => Some(false)
      Object(fields) if !fields.contains("filter") => None
      _ => raise LiveError("Variable filter must be named or indexed")
    }
    let (actual_start, actual_count) = match target {
      Locals(_) => {
        if filter == Some(true) {
          send_client(
            writer,
            self.client.response(seq, command, body={ "variables": [] }),
          )
          return
        }
        (start, count)
      }
      Children(frame, node, base, length, indexed) => {
        if (filter is Some(wanted) && wanted != indexed) || start >= length {
          send_client(
            writer,
            self.client.response(seq, command, body={ "variables": [] }),
          )
          return
        }
        let available = length - start
        let size = if count == 0 { available } else { count.min(available) }
        if size > 100 {
          let ranges = self.inspection.ranges(
            frame,
            node,
            base + start,
            size,
            indexed,
          )
          send_client(
            writer,
            self.client.response(seq, command, body={ "variables": ranges }),
          )
          return
        }
        (base + start, size)
      }
    }
    let job = { seq, epoch, target, start: actual_start, count: actual_count, }
    guard self.inspection.jobs.try_put(job) else {
      raise LiveError(
        "Too many pending variable requests; retry after current requests finish",
      )
    }
    self.inspection.pending.set(seq, job)
  } catch {
    error =>
      send_client(
        writer,
        self.client.response(seq, command, error=Some(@debug.to_string(error))),
      )
  }
}

///|
async fn LiveSession::inspect_worker(
  self : LiveSession,
  inbox : @async.Queue[LiveInput],
) -> Unit {
  for ;; {
    let job = self.inspection.jobs.get()
    let result = try {
      guard self.inspection_epoch() == Some(job.epoch) else {
        raise LiveError("Stale variable job")
      }
      let inspector = @lldb_dap.VariableInspector::new(
        (command, args) => {
          let reply : @async.Queue[Json] = @async.Queue(kind=Blocking(1))
          defer reply.close()
          inbox.put(InspectRead(job.epoch, command, args, reply))
          let message = reply.get()
          guard self.inspection_epoch() == Some(job.epoch) else {
            raise LiveError("Stale variable reply")
          }
          guard @dap.classify_message(message) is @dap.Response(response) else {
            raise LiveError("Invalid inspection response")
          }
          response
        },
        () => self.inspection_epoch(),
        self.capabilities,
      )
      let nodes = @async.with_timeout(12000, () => {
        match job.target {
          Locals(frame) => inspector.tree_locals(frame)
          Children(frame, node, _, _, _) =>
            inspector.tree_children(
              frame,
              node,
              start=job.start,
              count=job.count,
            )
        }
      })
      Ok(nodes)
    } catch {
      error => {
        if @async.is_cancellation_error(error) {
          raise error
        }
        Err(@debug.to_string(error))
      }
    }
    inbox.put(InspectDone(job.seq, result))
  }
}

///|
async fn LiveSession::complete_inspection(
  self : LiveSession,
  writer : &@io.Writer,
  seq : Int,
  result : Result[Array[@lldb_dap.VariableNode], String],
) -> Unit {
  guard self.inspection.pending.get(seq) is Some(job) else { return }
  self.inspection.pending.remove(seq)
  try {
    guard self.inspection_epoch() == Some(job.epoch) else {
      raise LiveError("Stale variable result")
    }
    let nodes = match result {
      Ok(nodes) => nodes
      Err(error) => raise LiveError(error)
    }
    let frame = match job.target {
      Locals(frame) | Children(frame, _, _, _, _) => frame
    }
    let selected = match job.target {
      Locals(_) => {
        let count = if job.count == 0 { nodes.length() } else { job.count }
        nodes.iter().drop(job.start).take(count).collect()
      }
      Children(_, _, _, _, _) => nodes
    }
    let values = selected.map(node => self.inspection.node_json(frame, node))
    send_client(
      writer,
      self.client.response(seq, "variables", body={ "variables": values }),
    )
  } catch {
    error =>
      send_client(
        writer,
        self.client.response(
          seq,
          "variables",
          error=Some(@debug.to_string(error)),
        ),
      )
  }
}
