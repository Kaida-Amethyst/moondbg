///|
/// lldb-dap implementation of the application-level debugger backend port.
/// Protocol processes and execution-scoped identifiers remain private here.
pub struct LldbDapBackend {
  priv session : LldbDapSession
  priv mut imported_source_breakpoints : Int
  priv mut imported_function_breakpoints : Int
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
    session: LldbDapSession::start(group, adapter, preparation_timeout_ms~),
    imported_source_breakpoints: 0,
    imported_function_breakpoints: 0,
  }
}

///|
fn LldbDapBackend::sync_source_breakpoints(
  self : LldbDapBackend,
  breakpoints : Array[@moondbg.SourceBreakpoint],
) -> Unit raise {
  for index in self.imported_source_breakpoints..<breakpoints.length() {
    let breakpoint = breakpoints[index]
    self.session.import_source_breakpoint(breakpoint) |> ignore
  }
  self.imported_source_breakpoints = breakpoints.length()
}

///|
fn LldbDapBackend::sync_function_breakpoints(
  self : LldbDapBackend,
  breakpoints : Array[@moondbg.FunctionBreakpoint],
) -> Unit raise {
  for index in self.imported_function_breakpoints..<breakpoints.length() {
    let breakpoint = breakpoints[index]
    self.session.import_function_breakpoint(breakpoint) |> ignore
  }
  self.imported_function_breakpoints = breakpoints.length()
}

///|
impl @moondbg.DebugBackend for LldbDapBackend with fn launch(
  self,
  executable,
  source_breakpoints,
  function_breakpoints,
) {
  self.sync_source_breakpoints(source_breakpoints) catch {
    error => raise @moondbg.DebugBackendError::failure(@debug.to_string(error))
  }
  self.sync_function_breakpoints(function_breakpoints) catch {
    error => raise @moondbg.DebugBackendError::failure(@debug.to_string(error))
  }
  self.session.run(executable) catch {
    LldbDapBackendError::AdapterFailure(message) =>
      raise @moondbg.DebugBackendError::failure(message)
    error => raise @moondbg.DebugBackendError::failure(@debug.to_string(error))
  }
}

///|
impl @moondbg.DebugBackend for LldbDapBackend with fn install_source_breakpoint(
  self,
  breakpoint,
) {
  defer {
    self.imported_source_breakpoints = self.session.source_breakpoints.length()
  }
  self.session.install_source_breakpoint(
    LogicalSourceBreakpoint::from_domain(breakpoint),
  ) catch {
    LldbDapBackendError::AdapterFailure(message) =>
      raise @moondbg.DebugBackendError::failure(message)
    error => raise @moondbg.DebugBackendError::failure(@debug.to_string(error))
  }
}

///|
impl @moondbg.DebugBackend for LldbDapBackend with fn install_function_breakpoint(
  self,
  breakpoint,
) {
  defer {
    self.imported_function_breakpoints = self.session.function_breakpoints.length()
  }
  self.session.install_function_breakpoint(
    LogicalFunctionBreakpoint::from_domain(breakpoint),
  ) catch {
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
  self.session.continue_execution(thread) catch {
    LldbDapBackendError::AdapterFailure(message) =>
      raise @moondbg.DebugBackendError::failure(message)
    error => raise @moondbg.DebugBackendError::failure(@debug.to_string(error))
  }
}

///|
impl @moondbg.DebugBackend for LldbDapBackend with fn next(self, thread) {
  self.session.next(thread) catch {
    LldbDapBackendError::AdapterFailure(message) =>
      raise @moondbg.DebugBackendError::failure(message)
    error => raise @moondbg.DebugBackendError::failure(@debug.to_string(error))
  }
}

///|
impl @moondbg.DebugBackend for LldbDapBackend with fn step(self, thread) {
  self.session.step(thread) catch {
    LldbDapBackendError::AdapterFailure(message) =>
      raise @moondbg.DebugBackendError::failure(message)
    error => raise @moondbg.DebugBackendError::failure(@debug.to_string(error))
  }
}

///|
impl @moondbg.DebugBackend for LldbDapBackend with fn finish(self, thread) {
  self.session.finish(thread) catch {
    LldbDapBackendError::AdapterFailure(message) =>
      raise @moondbg.DebugBackendError::failure(message)
    error => raise @moondbg.DebugBackendError::failure(@debug.to_string(error))
  }
}

///|
impl @moondbg.DebugBackend for LldbDapBackend with fn stack_snapshot(
  self,
  thread,
  window,
) {
  self.session.stack_snapshot(thread, window) catch {
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
  path,
) {
  self.session.find_variable(thread, frame, path) catch {
    LldbDapBackendError::AdapterFailure(message) =>
      raise @moondbg.DebugBackendError::failure(message)
    error => raise @moondbg.DebugBackendError::failure(@debug.to_string(error))
  }
}

///|
impl @moondbg.DebugBackend for LldbDapBackend with fn local_variables(
  self,
  thread,
  frame,
) {
  self.session.local_variables(thread, frame) catch {
    LldbDapBackendError::AdapterFailure(message) =>
      raise @moondbg.DebugBackendError::failure(message)
    error => raise @moondbg.DebugBackendError::failure(@debug.to_string(error))
  }
}

///|
impl @moondbg.DebugBackend for LldbDapBackend with fn breakpoint_snapshots(self) {
  self.session.source_breakpoints()
}

///|
impl @moondbg.DebugBackend for LldbDapBackend with fn function_breakpoint_snapshots(
  self,
) {
  self.session.function_breakpoints()
}

///|
impl @moondbg.DebugBackend for LldbDapBackend with fn take_output(self) {
  self.session.take_output()
}

///|
impl @moondbg.DebugBackend for LldbDapBackend with fn disconnect(self) {
  self.session.disconnect() catch {
    LldbDapBackendError::AdapterFailure(message) =>
      raise @moondbg.DebugBackendError::failure(message)
    error => raise @moondbg.DebugBackendError::failure(@debug.to_string(error))
  }
}

///|
impl @moondbg.DebugBackend for LldbDapBackend with fn close(self) {
  self.session.close()
}

///|
/// Erases the concrete adapter behind the application backend port.
pub fn LldbDapBackend::as_debug_backend(
  self : LldbDapBackend,
) -> &@moondbg.DebugBackend {
  self
}
