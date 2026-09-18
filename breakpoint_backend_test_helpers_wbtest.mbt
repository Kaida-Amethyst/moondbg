///|
impl @debugger.DebugBackend for ExecutionCommandTestBackend with fn synchronize_breakpoints(
  self,
  configuration,
) {
  self.syncs += 1
  if self.fail_sync {
    raise @debugger.BreakpointSyncError::BreakpointSyncUncertain(
      "test synchronization was interrupted",
    )
  }
  if self.refuse_sync {
    raise @debugger.BreakpointSyncError::BreakpointSyncRejected(
      "test rejected without changes",
    )
  }
  let sources : Array[@debugger.BreakpointSnapshot] = []
  let functions : Array[@debugger.FunctionBreakpointSnapshot] = []
  for breakpoint in configuration.sources() {
    if breakpoint.enabled() {
      let existing = @debugger.DebugBackend::breakpoint_snapshots(self)
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
      let existing = @debugger.DebugBackend::function_breakpoint_snapshots(self)
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
  @debugger.BreakpointSyncResult::new(sources, functions)
}

///|
impl @debugger.DebugBackend for ExecutionCommandTestBackend with fn abandon_execution(
  self,
) {
  @debugger.DebugBackend::disconnect(self)
}

///|
impl @debugger.DebugBackend for FrameworkTestBackend with fn synchronize_breakpoints(
  self,
  configuration,
) {
  let sources : Array[@debugger.BreakpointSnapshot] = []
  let functions : Array[@debugger.FunctionBreakpointSnapshot] = []
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
  @debugger.BreakpointSyncResult::new(sources, functions)
}

///|
impl @debugger.DebugBackend for FrameworkTestBackend with fn abandon_execution(
  self,
) {
  @debugger.DebugBackend::disconnect(self)
}

///|
impl @debugger.DebugBackend for ObservationCommandTestBackend with fn synchronize_breakpoints(
  self,
  configuration,
) {
  let sources : Array[@debugger.BreakpointSnapshot] = []
  let functions : Array[@debugger.FunctionBreakpointSnapshot] = []
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
  @debugger.BreakpointSyncResult::new(sources, functions)
}

///|
impl @debugger.DebugBackend for ObservationCommandTestBackend with fn abandon_execution(
  self,
) {
  @debugger.DebugBackend::disconnect(self)
}

///|
impl @debugger.DebugBackend for StackCommandTestBackend with fn synchronize_breakpoints(
  self,
  configuration,
) {
  let sources : Array[@debugger.BreakpointSnapshot] = []
  let functions : Array[@debugger.FunctionBreakpointSnapshot] = []
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
  @debugger.BreakpointSyncResult::new(sources, functions)
}

///|
impl @debugger.DebugBackend for StackCommandTestBackend with fn abandon_execution(
  self,
) {
  @debugger.DebugBackend::disconnect(self)
}
