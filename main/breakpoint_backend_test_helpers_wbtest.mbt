///|
impl @moondbg.DebugBackend for ExecutionCommandTestBackend with fn synchronize_breakpoints(
  self,
  configuration,
) {
  self.syncs += 1
  if self.fail_sync {
    raise @moondbg.BreakpointSyncError::BreakpointSyncUncertain(
      "test synchronization was interrupted",
    )
  }
  if self.refuse_sync {
    raise @moondbg.BreakpointSyncError::BreakpointSyncRejected(
      "test rejected without changes",
    )
  }
  let sources : Array[@moondbg.BreakpointSnapshot] = []
  let functions : Array[@moondbg.FunctionBreakpointSnapshot] = []
  for breakpoint in configuration.sources() {
    if breakpoint.enabled() {
      let existing = @moondbg.DebugBackend::breakpoint_snapshots(self)
        .iter()
        .find_first(item => item.id() == breakpoint.id())
      sources.push(
        match existing {
          Some(snapshot) => snapshot
          None => self.install_source_breakpoint(breakpoint)
        },
      )
    }
  }
  for breakpoint in configuration.functions() {
    if breakpoint.enabled() {
      let existing = @moondbg.DebugBackend::function_breakpoint_snapshots(self)
        .iter()
        .find_first(item => item.id() == breakpoint.id())
      functions.push(
        match existing {
          Some(snapshot) => snapshot
          None => self.install_function_breakpoint(breakpoint)
        },
      )
    }
  }
  @moondbg.BreakpointSyncResult::new(sources, functions)
}

///|
impl @moondbg.DebugBackend for ExecutionCommandTestBackend with fn abandon_execution(
  self,
) {
  @moondbg.DebugBackend::disconnect(self)
}

///|
impl @moondbg.DebugBackend for FrameworkTestBackend with fn synchronize_breakpoints(
  self,
  configuration,
) {
  let sources : Array[@moondbg.BreakpointSnapshot] = []
  let functions : Array[@moondbg.FunctionBreakpointSnapshot] = []
  for breakpoint in configuration.sources() {
    if breakpoint.enabled() {
      sources.push(self.install_source_breakpoint(breakpoint))
    }
  }
  for breakpoint in configuration.functions() {
    if breakpoint.enabled() {
      functions.push(self.install_function_breakpoint(breakpoint))
    }
  }
  @moondbg.BreakpointSyncResult::new(sources, functions)
}

///|
impl @moondbg.DebugBackend for FrameworkTestBackend with fn abandon_execution(
  self,
) {
  @moondbg.DebugBackend::disconnect(self)
}

///|
impl @moondbg.DebugBackend for ObservationCommandTestBackend with fn synchronize_breakpoints(
  self,
  configuration,
) {
  let sources : Array[@moondbg.BreakpointSnapshot] = []
  let functions : Array[@moondbg.FunctionBreakpointSnapshot] = []
  for breakpoint in configuration.sources() {
    if breakpoint.enabled() {
      sources.push(self.install_source_breakpoint(breakpoint))
    }
  }
  for breakpoint in configuration.functions() {
    if breakpoint.enabled() {
      functions.push(self.install_function_breakpoint(breakpoint))
    }
  }
  @moondbg.BreakpointSyncResult::new(sources, functions)
}

///|
impl @moondbg.DebugBackend for ObservationCommandTestBackend with fn abandon_execution(
  self,
) {
  @moondbg.DebugBackend::disconnect(self)
}

///|
impl @moondbg.DebugBackend for StackCommandTestBackend with fn synchronize_breakpoints(
  self,
  configuration,
) {
  let sources : Array[@moondbg.BreakpointSnapshot] = []
  let functions : Array[@moondbg.FunctionBreakpointSnapshot] = []
  for breakpoint in configuration.sources() {
    if breakpoint.enabled() {
      sources.push(self.install_source_breakpoint(breakpoint))
    }
  }
  for breakpoint in configuration.functions() {
    if breakpoint.enabled() {
      functions.push(self.install_function_breakpoint(breakpoint))
    }
  }
  @moondbg.BreakpointSyncResult::new(sources, functions)
}

///|
impl @moondbg.DebugBackend for StackCommandTestBackend with fn abandon_execution(
  self,
) {
  @moondbg.DebugBackend::disconnect(self)
}
