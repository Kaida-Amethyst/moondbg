///|
/// lldb-dap implementation of the application-level debugger backend port.
/// Protocol processes and execution-scoped identifiers remain private here.
pub struct LldbDapBackend {
  priv legacy : LldbDapSession
  priv mut imported_breakpoints : Int
}

///|
/// Starts lldb-dap initialization in the background without waiting for the
/// first user command.
pub fn[X] LldbDapBackend::start(
  group : @async.TaskGroup[X],
  adapter : String,
  preparation_timeout_ms? : Int = 10000,
) -> LldbDapBackend {
  {
    legacy: LldbDapSession::start(group, adapter, preparation_timeout_ms~),
    imported_breakpoints: 0,
  }
}

///|
fn LldbDapBackend::sync_breakpoints(
  self : LldbDapBackend,
  breakpoints : Array[@moondbg.SourceBreakpoint],
) -> Unit raise {
  for index in self.imported_breakpoints..<breakpoints.length() {
    let breakpoint = breakpoints[index]
    self.legacy.add_source_breakpoint(breakpoint) |> ignore
  }
  self.imported_breakpoints = breakpoints.length()
}

///|
impl @moondbg.DebugBackend for LldbDapBackend with fn launch(
  self,
  executable,
  breakpoints,
) {
  self.sync_breakpoints(breakpoints) catch {
    error => raise @moondbg.DebugBackendError::failure(@debug.to_string(error))
  }
  self.legacy.run(executable) catch {
    LldbDapBackendError::AdapterFailure(message) =>
      raise @moondbg.DebugBackendError::failure(message)
    error => raise @moondbg.DebugBackendError::failure(@debug.to_string(error))
  }
}

///|
impl @moondbg.DebugBackend for LldbDapBackend with fn continue_execution(
  self,
  thread,
) {
  self.legacy.continue_execution(thread) catch {
    LldbDapBackendError::AdapterFailure(message) =>
      raise @moondbg.DebugBackendError::failure(message)
    error => raise @moondbg.DebugBackendError::failure(@debug.to_string(error))
  }
}

///|
impl @moondbg.DebugBackend for LldbDapBackend with fn next(self, thread) {
  self.legacy.next(thread) catch {
    LldbDapBackendError::AdapterFailure(message) =>
      raise @moondbg.DebugBackendError::failure(message)
    error => raise @moondbg.DebugBackendError::failure(@debug.to_string(error))
  }
}

///|
impl @moondbg.DebugBackend for LldbDapBackend with fn step(self, thread) {
  self.legacy.step(thread) catch {
    LldbDapBackendError::AdapterFailure(message) =>
      raise @moondbg.DebugBackendError::failure(message)
    error => raise @moondbg.DebugBackendError::failure(@debug.to_string(error))
  }
}

///|
impl @moondbg.DebugBackend for LldbDapBackend with fn finish(self, thread) {
  self.legacy.finish(thread) catch {
    LldbDapBackendError::AdapterFailure(message) =>
      raise @moondbg.DebugBackendError::failure(message)
    error => raise @moondbg.DebugBackendError::failure(@debug.to_string(error))
  }
}

///|
impl @moondbg.DebugBackend for LldbDapBackend with fn find_variable(
  self,
  thread,
  frame,
  name,
) {
  self.legacy.find_variable(thread, frame, name) catch {
    LldbDapBackendError::AdapterFailure(message) =>
      raise @moondbg.DebugBackendError::failure(message)
    error => raise @moondbg.DebugBackendError::failure(@debug.to_string(error))
  }
}

///|
impl @moondbg.DebugBackend for LldbDapBackend with fn breakpoint_snapshots(self) {
  self.legacy.source_breakpoints()
}

///|
impl @moondbg.DebugBackend for LldbDapBackend with fn take_output(self) {
  self.legacy.take_output()
}

///|
impl @moondbg.DebugBackend for LldbDapBackend with fn disconnect(self) {
  self.legacy.disconnect() catch {
    LldbDapBackendError::AdapterFailure(message) =>
      raise @moondbg.DebugBackendError::failure(message)
    error => raise @moondbg.DebugBackendError::failure(@debug.to_string(error))
  }
}

///|
impl @moondbg.DebugBackend for LldbDapBackend with fn close(self) {
  self.legacy.close()
}

///|
/// Erases the concrete adapter behind the application backend port.
pub fn LldbDapBackend::as_debug_backend(
  self : LldbDapBackend,
) -> &@moondbg.DebugBackend {
  self
}
