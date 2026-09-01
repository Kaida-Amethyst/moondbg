///|
/// Owns the currently prepared or active lldb-dap execution and its
/// adapter-scoped mappings. Stable configuration remains owned by DebugSession.
priv struct LldbDapSession {
  source_breakpoints : Array[LogicalSourceBreakpoint]
  function_breakpoints : Array[LogicalFunctionBreakpoint]
  spawn_preparation : () -> @async.Task[DebugExecution]
  mut preparation : @async.Task[DebugExecution]?
  preparation_timeout_ms : Int
  mut execution : DebugExecution?
  mut detached_state : DapSessionState
  last_source_breakpoint_snapshots : Map[Int, @moondbg.BreakpointSnapshot]
  last_function_breakpoint_snapshots : Map[
    Int,
    @moondbg.FunctionBreakpointSnapshot,
  ]
  pending_output : Array[@moondbg.DebugOutput]
}

///|
fn LldbDapSession::begin_preparation(self : LldbDapSession) -> Unit {
  self.preparation = Some((self.spawn_preparation)())
  self.detached_state = Ready
}

///|
/// Returns the current stable or transitional debugger state.
fn LldbDapSession::state(self : LldbDapSession) -> DapSessionState {
  match self.execution {
    Some(execution) => execution.state()
    None => self.detached_state
  }
}

///|
async fn LldbDapSession::stack_snapshot(
  self : LldbDapSession,
  thread : @moondbg.ThreadSelection,
  window : @moondbg.StackWindow,
) -> @moondbg.StackSnapshot raise LldbDapBackendError {
  guard self.execution is Some(execution) else {
    raise LldbDapBackendError::OperationNotAllowed(
      state=self.detached_state,
      action="inspect the stack",
    )
  }
  execution.load_stack_window(thread, window) catch {
    error => {
      let message = @debug.to_string(error)
      self.recover_failed_execution(execution, try_disconnect=true) catch {
        _ => ()
      }
      raise LldbDapBackendError::AdapterFailure(message)
    }
  }
}

///|
async fn LldbDapSession::prepared_execution(
  self : LldbDapSession,
) -> DebugExecution raise LldbDapBackendError {
  match self.execution {
    Some(execution) => return execution
    None => ()
  }
  guard self.preparation is Some(preparation) else {
    raise LldbDapBackendError::OperationNotAllowed(
      state=self.detached_state,
      action="run the program",
    )
  }
  let completed = @async.with_timeout_opt(self.preparation_timeout_ms, () => {
    preparation.wait()
  }) catch {
    error => {
      let message = @debug.to_string(error)
      self.preparation = None
      self.begin_preparation()
      raise LldbDapBackendError::AdapterFailure(message)
    }
  }
  guard completed is Some(execution) else {
    self.preparation = None
    preparation.cancel()
    (preparation.wait() |> ignore) catch {
      _ => ()
    }
    self.begin_preparation()
    raise LldbDapBackendError::AdapterFailure(
      "lldb-dap initialize timed out after \{self.preparation_timeout_ms} ms",
    )
  }
  self.preparation = None
  self.execution = Some(execution)
  execution
}

///|
fn LldbDapSession::archive_execution(
  self : LldbDapSession,
  execution : DebugExecution,
) -> Unit {
  for output in execution.take_output() {
    self.pending_output.push(output)
  }
  self.last_source_breakpoint_snapshots.clear()
  for breakpoint in self.source_breakpoints {
    let snapshot = execution.breakpoint_state.source_snapshot(breakpoint)
    self.last_source_breakpoint_snapshots.set(snapshot.id(), snapshot)
  }
  self.last_function_breakpoint_snapshots.clear()
  for breakpoint in self.function_breakpoints {
    let snapshot = execution.breakpoint_state.function_snapshot(breakpoint)
    self.last_function_breakpoint_snapshots.set(snapshot.id(), snapshot)
  }
}

///|
fn LldbDapSession::complete_finished_execution(
  self : LldbDapSession,
  execution : DebugExecution,
) -> Unit {
  self.archive_execution(execution)
  execution.close()
  self.execution = None
  self.begin_preparation()
}

///|
async fn LldbDapSession::recover_failed_execution(
  self : LldbDapSession,
  execution : DebugExecution,
  try_disconnect~ : Bool,
) -> Unit {
  defer {
    self.archive_execution(execution)
    execution.close()
    self.execution = None
    self.begin_preparation()
  }
  if try_disconnect {
    (@async.with_timeout_opt(1000, () => execution.disconnect()) catch {
      _ => None
    })
    |> ignore
  }
}

///|
async fn LldbDapSession::restart_stopped_execution(
  self : LldbDapSession,
  execution : DebugExecution,
) -> Unit raise LldbDapBackendError {
  execution.disconnect() catch {
    error => {
      self.recover_failed_execution(execution, try_disconnect=false) catch {
        _ => ()
      }
      raise LldbDapBackendError::AdapterFailure(@debug.to_string(error))
    }
  }
  execution.close()
  self.execution = None
  self.begin_preparation()
}

///|
async fn LldbDapSession::run(
  self : LldbDapSession,
  executable : String,
) -> @moondbg.RunOutcome {
  if self.execution is Some(execution) && execution.state() is Stopped {
    self.restart_stopped_execution(execution)
  }
  let execution = self.prepared_execution()
  let outcome = execution.run(
    executable,
    self.source_breakpoints,
    self.function_breakpoints,
  ) catch {
    LldbDapBackendError::AdapterFailure(message) => {
      self.recover_failed_execution(execution, try_disconnect=true) catch {
        _ => ()
      }
      raise LldbDapBackendError::AdapterFailure(message)
    }
    error => raise error
  }
  if outcome is @moondbg.Exited(_) {
    self.complete_finished_execution(execution)
  }
  outcome
}

///|
async fn LldbDapSession::resume_execution(
  self : LldbDapSession,
  kind : ExecutionResumeKind,
  thread : @moondbg.ThreadSelection,
) -> @moondbg.RunOutcome {
  guard self.execution is Some(execution) else {
    raise LldbDapBackendError::OperationNotAllowed(
      state=self.detached_state,
      action=kind.action(),
    )
  }
  let outcome = execution.resume_execution(kind, thread) catch {
    LldbDapBackendError::AdapterFailure(message) => {
      self.recover_failed_execution(execution, try_disconnect=true) catch {
        _ => ()
      }
      raise LldbDapBackendError::AdapterFailure(message)
    }
    error => raise error
  }
  if outcome is @moondbg.Exited(_) {
    self.complete_finished_execution(execution)
  }
  outcome
}

///|
async fn LldbDapSession::continue_execution(
  self : LldbDapSession,
  thread : @moondbg.ThreadSelection,
) -> @moondbg.RunOutcome {
  self.resume_execution(ContinueExecution, thread)
}

///|
async fn LldbDapSession::next(
  self : LldbDapSession,
  thread : @moondbg.ThreadSelection,
) -> @moondbg.RunOutcome {
  self.resume_execution(StepExecution(@dap.DapNext), thread)
}

///|
async fn LldbDapSession::step(
  self : LldbDapSession,
  thread : @moondbg.ThreadSelection,
) -> @moondbg.RunOutcome {
  self.resume_execution(StepExecution(@dap.DapStepIn), thread)
}

///|
async fn LldbDapSession::finish(
  self : LldbDapSession,
  thread : @moondbg.ThreadSelection,
) -> @moondbg.RunOutcome {
  self.resume_execution(StepExecution(@dap.DapStepOut), thread)
}

///|
/// Requests a graceful shutdown of the current execution.
async fn LldbDapSession::disconnect(self : LldbDapSession) -> Unit {
  guard self.execution is Some(execution) else { return }
  defer {
    execution.close()
    self.execution = None
    self.detached_state = Exited
  }
  (@async.with_timeout_opt(1000, () => execution.disconnect()) catch {
    _ => None
  })
  |> ignore
}

///|
/// Closes the current execution and detaches all adapter-scoped resources.
fn LldbDapSession::close(self : LldbDapSession) -> Unit {
  match self.execution {
    Some(execution) => {
      execution.close()
      self.detached_state = execution.state()
      self.execution = None
    }
    None => ()
  }
  guard self.preparation is Some(preparation) else { return }
  let completed = preparation.try_wait() catch { _ => None }
  preparation.cancel()
  if completed is Some(execution) {
    execution.close()
    self.detached_state = execution.state()
  }
  self.preparation = None
}
