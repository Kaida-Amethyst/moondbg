///|
/// lldb-dap implementation of the application-level debugger backend port.
/// Protocol processes and execution-scoped identifiers remain private here.
pub struct LldbDapBackend {
  priv session : LldbDapSession
}

///|
/// Starts lldb-dap initialization in the background without waiting for the
/// first user command.
pub fn[X] LldbDapBackend::start(
  group : @async.TaskGroup[X],
  adapter : String,
  preparation_timeout_ms? : Int = 10000,
) -> LldbDapBackend {
  { session: LldbDapSession::start(group, adapter, preparation_timeout_ms~), }
}

///|
fn LldbDapBackend::replace_launch_breakpoints(
  self : LldbDapBackend,
  breakpoints : Array[@debugger.SourceBreakpoint],
  functions : Array[@debugger.FunctionBreakpoint],
) -> Unit {
  self.session.source_breakpoints.clear()
  for breakpoint in breakpoints {
    if breakpoint.enabled() {
      self.session.source_breakpoints.push(
        LogicalSourceBreakpoint::from_domain(breakpoint),
      )
    }
  }
  self.session.function_breakpoints.clear()
  for breakpoint in functions {
    if breakpoint.enabled() {
      self.session.function_breakpoints.push(
        LogicalFunctionBreakpoint::from_domain(breakpoint),
      )
    }
  }
}

///|
impl @debugger.DebugBackend for LldbDapBackend with fn launch(
  self,
  executable,
  source_breakpoints,
  function_breakpoints,
) {
  self.replace_launch_breakpoints(source_breakpoints, function_breakpoints)
  self.session.run(executable) catch {
    LldbDapBackendError::AdapterFailure(message) =>
      raise @debugger.DebugBackendError::failure(message)
    error => raise @debugger.DebugBackendError::failure(@debug.to_string(error))
  }
}

///|
impl @debugger.DebugBackend for LldbDapBackend with fn synchronize_breakpoints(
  self,
  configuration,
) {
  self.session.synchronize_breakpoints(
    configuration
    .sources()
    .filter(item => item.enabled())
    .map(LogicalSourceBreakpoint::from_domain),
    configuration
    .functions()
    .filter(item => item.enabled())
    .map(LogicalFunctionBreakpoint::from_domain),
    families=configuration
      .functions()
      .filter(item => item.selector() is @debugger.MoonBitFunctionFamily(_))
      .map(FamilyConfiguration::from_domain),
  )
}

///|
impl @debugger.DebugBackend for LldbDapBackend with fn abandon_execution(self) {
  if self.session.execution is Some(execution) {
    self.session.recover_failed_execution(execution, try_disconnect=true)
  }
}

///|
impl @debugger.DebugBackend for LldbDapBackend with fn continue_execution(
  self,
  thread,
) {
  self.session.continue_execution(thread) catch {
    LldbDapBackendError::AdapterFailure(message) =>
      raise @debugger.DebugBackendError::failure(message)
    error => raise @debugger.DebugBackendError::failure(@debug.to_string(error))
  }
}

///|
impl @debugger.DebugBackend for LldbDapBackend with fn next(self, thread) {
  self.session.next(thread) catch {
    LldbDapBackendError::AdapterFailure(message) =>
      raise @debugger.DebugBackendError::failure(message)
    error => raise @debugger.DebugBackendError::failure(@debug.to_string(error))
  }
}

///|
impl @debugger.DebugBackend for LldbDapBackend with fn step(self, thread) {
  self.session.step(thread) catch {
    LldbDapBackendError::AdapterFailure(message) =>
      raise @debugger.DebugBackendError::failure(message)
    error => raise @debugger.DebugBackendError::failure(@debug.to_string(error))
  }
}

///|
impl @debugger.DebugBackend for LldbDapBackend with fn finish(self, thread) {
  self.session.finish(thread) catch {
    LldbDapBackendError::AdapterFailure(message) =>
      raise @debugger.DebugBackendError::failure(message)
    error => raise @debugger.DebugBackendError::failure(@debug.to_string(error))
  }
}

///|
impl @debugger.DebugBackend for LldbDapBackend with fn stack_snapshot(
  self,
  thread,
  window,
) {
  self.session.stack_snapshot(thread, window) catch {
    LldbDapBackendError::AdapterFailure(message) =>
      raise @debugger.DebugBackendError::failure(message)
    error => raise @debugger.DebugBackendError::failure(@debug.to_string(error))
  }
}

///|
impl @debugger.DebugBackend for LldbDapBackend with fn find_variable(
  self,
  thread,
  frame,
  path,
) {
  self.session.find_variable(thread, frame, path) catch {
    LldbDapBackendError::AdapterFailure(message) =>
      raise @debugger.DebugBackendError::failure(message)
    error => raise @debugger.DebugBackendError::failure(@debug.to_string(error))
  }
}

///|
impl @debugger.DebugBackend for LldbDapBackend with fn local_variables(
  self,
  thread,
  frame,
) {
  self.session.local_variables(thread, frame) catch {
    LldbDapBackendError::AdapterFailure(message) =>
      raise @debugger.DebugBackendError::failure(message)
    error => raise @debugger.DebugBackendError::failure(@debug.to_string(error))
  }
}

///|
impl @debugger.DebugBackend for LldbDapBackend with fn breakpoint_snapshots(
  self,
) {
  self.session.source_breakpoints()
}

///|
impl @debugger.DebugBackend for LldbDapBackend with fn function_breakpoint_snapshots(
  self,
) {
  self.session.function_breakpoints()
}

///|
impl @debugger.DebugBackend for LldbDapBackend with fn take_output(self) {
  self.session.take_output()
}

///|
impl @debugger.DebugBackend for LldbDapBackend with fn disconnect(self) {
  self.session.disconnect() catch {
    LldbDapBackendError::AdapterFailure(message) =>
      raise @debugger.DebugBackendError::failure(message)
    error => raise @debugger.DebugBackendError::failure(@debug.to_string(error))
  }
}

///|
impl @debugger.DebugBackend for LldbDapBackend with fn close(self) {
  self.session.close()
}

///|
/// Erases the concrete adapter behind the application backend port.
pub fn LldbDapBackend::as_debug_backend(
  self : LldbDapBackend,
) -> &@debugger.DebugBackend {
  self
}
