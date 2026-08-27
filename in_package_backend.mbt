///|
/// Temporary adapter used while the DAP implementation still lives in the
/// root package. P3 replaces this bridge with the lldb_dap package.
priv struct InPackageDebugBackend {
  legacy : LegacyDapSession
  mut imported_breakpoints : Int
}

///|
fn[X] InPackageDebugBackend::start(
  group : @async.TaskGroup[X],
  adapter : String,
  preparation_timeout_ms~ : Int,
) -> InPackageDebugBackend {
  {
    legacy: LegacyDapSession::start(group, adapter, preparation_timeout_ms~),
    imported_breakpoints: 0,
  }
}

///|
fn InPackageDebugBackend::sync_breakpoints(
  self : InPackageDebugBackend,
  breakpoints : Array[SourceBreakpoint],
) -> Unit raise {
  for index in self.imported_breakpoints..<breakpoints.length() {
    let breakpoint = breakpoints[index]
    self.legacy.add_source_breakpoint(
      breakpoint.source_path(),
      breakpoint.requested_line(),
    )
    |> ignore
  }
  self.imported_breakpoints = breakpoints.length()
}

///|
impl DebugBackend for InPackageDebugBackend with fn launch(
  self,
  executable,
  breakpoints,
) {
  // LegacyDapSession still duplicates the current launch configuration while
  // the DAP monolith remains in the root package. DebugSession is authoritative:
  // every launch refreshes this temporary copy from the port input. P3/P4
  // remove the duplicate together with the legacy session.
  self.legacy.set_launch_executable(executable)
  self.sync_breakpoints(breakpoints) catch {
    error => raise DebugBackendError::BackendFailure(@debug.to_string(error))
  }
  self.legacy.run() catch {
    LegacyDapSessionError::AdapterFailure(message) =>
      raise DebugBackendError::BackendFailure(message)
    error => raise DebugBackendError::BackendFailure(@debug.to_string(error))
  }
}

///|
impl DebugBackend for InPackageDebugBackend with fn continue_execution(self) {
  self.legacy.continue_execution() catch {
    LegacyDapSessionError::AdapterFailure(message) =>
      raise DebugBackendError::BackendFailure(message)
    error => raise DebugBackendError::BackendFailure(@debug.to_string(error))
  }
}

///|
impl DebugBackend for InPackageDebugBackend with fn next(self) {
  self.legacy.next() catch {
    LegacyDapSessionError::AdapterFailure(message) =>
      raise DebugBackendError::BackendFailure(message)
    error => raise DebugBackendError::BackendFailure(@debug.to_string(error))
  }
}

///|
impl DebugBackend for InPackageDebugBackend with fn step(self) {
  self.legacy.step() catch {
    LegacyDapSessionError::AdapterFailure(message) =>
      raise DebugBackendError::BackendFailure(message)
    error => raise DebugBackendError::BackendFailure(@debug.to_string(error))
  }
}

///|
impl DebugBackend for InPackageDebugBackend with fn finish(self) {
  self.legacy.finish() catch {
    LegacyDapSessionError::AdapterFailure(message) =>
      raise DebugBackendError::BackendFailure(message)
    error => raise DebugBackendError::BackendFailure(@debug.to_string(error))
  }
}

///|
impl DebugBackend for InPackageDebugBackend with fn find_variable(self, name) {
  self.legacy.find_variable(name) catch {
    LegacyDapSessionError::AdapterFailure(message) =>
      raise DebugBackendError::BackendFailure(message)
    error => raise DebugBackendError::BackendFailure(@debug.to_string(error))
  }
}

///|
impl DebugBackend for InPackageDebugBackend with fn breakpoint_snapshots(self) {
  self.legacy.source_breakpoints()
}

///|
impl DebugBackend for InPackageDebugBackend with fn take_output(self) {
  self.legacy.take_output()
}

///|
impl DebugBackend for InPackageDebugBackend with fn disconnect(self) {
  self.legacy.disconnect() catch {
    LegacyDapSessionError::AdapterFailure(message) =>
      raise DebugBackendError::BackendFailure(message)
    error => raise DebugBackendError::BackendFailure(@debug.to_string(error))
  }
}

///|
impl DebugBackend for InPackageDebugBackend with fn close(self) {
  self.legacy.close()
}
