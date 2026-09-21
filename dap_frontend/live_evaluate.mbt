///|
fn inspection_error_message(error : Error) -> String {
  match error {
    @lldb_dap.MemoryReadError(message) => "Memory read failed: \{message}"
    LiveError(message)
    | @lldb_dap.VariableEvaluationError(message)
    | @lldb_dap.BufferInspectionError(message) => message
    _ => @debug.to_string(error)
  }
}

///|
fn LiveSession::enqueue_evaluate(
  self : LiveSession,
  seq : Int,
  epoch : Int,
  args : Json,
) -> Unit raise {
  guard args is { "expression": String(expression), .. } else {
    raise LiveError("evaluate requires an expression string")
  }
  guard @debugger.VariablePath::parse(expression.trim()) is Some(path) else {
    raise LiveError(
      "Only read-only variable paths are supported, e.g. point.x, arr[0].x or text[0:128]. No calls, arithmetic, assignments or REPL commands.",
    )
  }
  // DAP specifies global scope when frameId is absent. Do not silently pick a
  // frame from a previous scopes request or a different thread.
  let frame = nonnegative_argument(args, "frameId", default=-1)
  guard frame >= 0 else {
    raise LiveError(
      "Select a stopped stack frame; global evaluation is not supported",
    )
  }
  guard self.inspection.frames.get(frame) is Some(raw) else {
    raise LiveError("Unknown or stale frameId; request stackTrace again")
  }
  let job = VariableJob::{
    seq,
    epoch,
    target: Evaluate(raw, path),
    start: 0,
    count: 0,
  }
  guard self.inspection.jobs.try_put(job) else {
    raise LiveError(
      "Too many pending variable requests; retry after current requests finish",
    )
  }
  self.inspection.pending.set(seq, job)
}
