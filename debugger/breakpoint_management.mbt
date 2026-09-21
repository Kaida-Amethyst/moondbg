///|
/// A detached desired-configuration value. Accessors return copies: a backend
/// cannot mutate the session's authoritative arrays.
pub struct BreakpointConfiguration {
  priv sources : Array[SourceBreakpoint]
  priv functions : Array[FunctionBreakpoint]
}

///|
fn BreakpointConfiguration::new(
  sources : Array[SourceBreakpoint],
  functions : Array[FunctionBreakpoint],
) -> BreakpointConfiguration {
  { sources: sources.copy(), functions: functions.copy(), }
}

///|
pub fn BreakpointConfiguration::sources(
  self : BreakpointConfiguration,
) -> Array[SourceBreakpoint] {
  self.sources.copy()
}

///|
pub fn BreakpointConfiguration::functions(
  self : BreakpointConfiguration,
) -> Array[FunctionBreakpoint] {
  self.functions.copy()
}

///|
pub struct BreakpointSyncResult {
  priv sources : Array[BreakpointSnapshot]
  priv functions : Array[FunctionBreakpointSnapshot]
}

///|
pub fn BreakpointSyncResult::new(
  sources : Array[BreakpointSnapshot],
  functions : Array[FunctionBreakpointSnapshot],
) -> BreakpointSyncResult {
  { sources: sources.copy(), functions: functions.copy(), }
}

///|
pub fn BreakpointSyncResult::sources(
  self : BreakpointSyncResult,
) -> Array[BreakpointSnapshot] {
  self.sources.copy()
}

///|
pub fn BreakpointSyncResult::functions(
  self : BreakpointSyncResult,
) -> Array[FunctionBreakpointSnapshot] {
  self.functions.copy()
}

///|
pub(all) suberror BreakpointSyncError {
  BreakpointSyncRejected(String)
  BreakpointSyncUncertain(String)
} derive(Debug)

///|
pub extend BreakpointSyncError with @debug.Debug::{to_repr}

///|
pub enum BreakpointTarget {
  SourceTarget(display_path~ : String, source_path~ : String, line~ : Int)
  FunctionTarget(display_name~ : String, selector~ : FunctionBreakpointSelector)
} derive(Debug, Eq)

///|
pub extend BreakpointTarget with @debug.Debug::{to_repr}

///|
pub extend BreakpointTarget with Eq::{equal, not_equal}

///|
/// Installation freshness is independent from the desired enabled flag.
pub enum BreakpointInstallation {
  NotInstalled
  CurrentInstallation(BreakpointStatus)
  PreviousInstallation(BreakpointStatus)
} derive(Debug, Eq)

///|
pub extend BreakpointInstallation with @debug.Debug::{to_repr}

///|
pub extend BreakpointInstallation with Eq::{equal, not_equal}

///|
pub struct BreakpointListEntry {
  id : Int
  condition : String?
  target : BreakpointTarget
  enabled : Bool
  installation : BreakpointInstallation
  actual_line : Int?
  location_count : Int?
  locations : Array[BreakpointLocation]
} derive(Debug)

///|
pub extend BreakpointListEntry with @debug.Debug::{to_repr}

///|
pub(all) enum BreakpointOperation {
  DeleteBreakpoint
  DisableBreakpoint
  EnableBreakpoint
} derive(Debug, Eq)

///|
pub extend BreakpointOperation with @debug.Debug::{to_repr}

///|
pub extend BreakpointOperation with Eq::{equal, not_equal}

///|
pub struct BreakpointManagementResult {
  operation : BreakpointOperation
  breakpoint : BreakpointListEntry
  changed : Bool
} derive(Debug)

///|
pub extend BreakpointManagementResult with @debug.Debug::{to_repr}

///|
pub fn DebugSession::breakpoint_configuration(
  self : DebugSession,
) -> BreakpointConfiguration {
  BreakpointConfiguration::new(
    self.source_breakpoints,
    self.function_breakpoints,
  )
}

///|
fn installation_freshness(
  status : BreakpointStatus,
  current : Bool,
) -> BreakpointInstallation {
  if status is Pending {
    NotInstalled
  } else if current {
    CurrentInstallation(status)
  } else {
    PreviousInstallation(status)
  }
}

///|
/// This query performs no async work and never waits for adapter preparation.
pub fn DebugSession::breakpoints(
  self : DebugSession,
) -> Array[BreakpointListEntry] {
  let sources : Map[Int, BreakpointSnapshot] = Map([])
  let functions : Map[Int, FunctionBreakpointSnapshot] = Map([])
  for snapshot in self.source_breakpoints() {
    sources.set(snapshot.id(), snapshot)
  }
  for snapshot in self.function_breakpoints() {
    functions.set(snapshot.id(), snapshot)
  }
  let entries : Array[BreakpointListEntry] = []
  for breakpoint in self.source_breakpoints {
    let snapshot = sources
      .get(breakpoint.id())
      .unwrap_or(breakpoint.pending_snapshot())
    entries.push({
      id: breakpoint.id(),
      condition: breakpoint.condition().map(value => value.text),
      target: SourceTarget(
        display_path=breakpoint.display_path(),
        source_path=breakpoint.source_path(),
        line=breakpoint.requested_line(),
      ),
      enabled: breakpoint.enabled(),
      installation: installation_freshness(
        snapshot.status(),
        self.state() is Stopped && breakpoint.enabled(),
      ),
      actual_line: snapshot.actual_line(),
      location_count: None,
      locations: snapshot.locations(),
    })
  }
  for breakpoint in self.function_breakpoints {
    let snapshot = functions
      .get(breakpoint.id())
      .unwrap_or(breakpoint.pending_snapshot())
    entries.push({
      id: breakpoint.id(),
      condition: None,
      target: FunctionTarget(
        display_name=breakpoint.display_name(),
        selector=breakpoint.selector(),
      ),
      enabled: breakpoint.enabled(),
      installation: installation_freshness(
        snapshot.status(),
        self.state() is Stopped && breakpoint.enabled(),
      ),
      actual_line: match snapshot.locations().get(0) {
        Some(location) => location.line
        None => None
      },
      location_count: snapshot.location_count(),
      locations: snapshot.locations(),
    })
  }
  entries.sort_by((left, right) => left.id.compare(right.id))
  entries
}

///|
async fn DebugSession::synchronize_breakpoints(
  self : DebugSession,
  configuration : BreakpointConfiguration,
) -> BreakpointSyncResult {
  try {
    let result = self.backend.synchronize_breakpoints(configuration)
    let expected_sources = configuration
      .sources()
      .filter(item => item.enabled())
    let expected_functions = configuration
      .functions()
      .filter(item => item.enabled())
    let sources_by_id : Map[Int, SourceBreakpoint] = Map([])
    let functions_by_id : Map[Int, FunctionBreakpoint] = Map([])
    for item in expected_sources {
      sources_by_id.set(item.id(), item)
    }
    for item in expected_functions {
      functions_by_id.set(item.id(), item)
    }
    let seen : Map[Int, Bool] = Map([])
    guard result.sources.length() == expected_sources.length() &&
      result.functions.length() == expected_functions.length() else {
      raise BreakpointSyncError::BreakpointSyncUncertain(
        "incomplete breakpoint synchronization result",
      )
    }
    for snapshot in result.sources {
      guard seen.get(snapshot.id()) is None &&
        sources_by_id.get(snapshot.id()) is Some(expected) &&
        expected.source_path() == snapshot.source_path() &&
        expected.requested_line() == snapshot.requested_line() else {
        raise BreakpointSyncError::BreakpointSyncUncertain(
          "invalid source breakpoint synchronization result",
        )
      }
      seen.set(snapshot.id(), true)
    }
    for snapshot in result.functions {
      guard seen.get(snapshot.id()) is None &&
        functions_by_id.get(snapshot.id()) is Some(expected) &&
        expected.display_name() == snapshot.display_name() else {
        raise BreakpointSyncError::BreakpointSyncUncertain(
          "invalid function breakpoint synchronization result",
        )
      }
      seen.set(snapshot.id(), true)
    }
    for snapshot in result.sources {
      self.source_sync_results.set(snapshot.id(), snapshot)
    }
    for snapshot in result.functions {
      self.function_sync_results.set(snapshot.id(), snapshot)
    }
    result
  } catch {
    BreakpointSyncError::BreakpointSyncRejected(message) =>
      raise BreakpointManagementRejected(message)
    error => {
      let message = match error {
        BreakpointSyncError::BreakpointSyncUncertain(message) => message
        DebugBackendError::BackendFailure(message) => message
        _ => @debug.to_string(error)
      }
      self.backend.abandon_execution() catch {
        _ => ()
      }
      self.backend_failed(
        "\{message}; current execution was discarded",
        next_state=Ready,
      )
    }
  }
}

///|
pub async fn DebugSession::manage_breakpoint(
  self : DebugSession,
  id : Int,
  operation : BreakpointOperation,
) -> BreakpointManagementResult {
  guard self.state() is Ready || self.state() is Stopped else {
    raise OperationNotAllowed(state=self.state(), action="manage breakpoints")
  }
  guard id > 0 &&
    self.breakpoints().iter().find_first(item => item.id == id)
    is Some(previous) else {
    raise BreakpointNotFound(id)
  }
  let desired_enabled = operation is EnableBreakpoint
  if !(operation is DeleteBreakpoint) && previous.enabled == desired_enabled {
    return { operation, breakpoint: previous, changed: false, }
  }
  let sources = self.source_breakpoints.filter_map(item => {
    if item.id() != id {
      Some(item)
    } else if operation is DeleteBreakpoint {
      None
    } else {
      Some(item.with_enabled(desired_enabled))
    }
  })
  let functions = self.function_breakpoints.filter_map(item => {
    if item.id() != id {
      Some(item)
    } else if operation is DeleteBreakpoint {
      None
    } else {
      Some(item.with_enabled(desired_enabled))
    }
  })
  if self.state() is Stopped {
    let old_sources = self.source_breakpoints
    let old_functions = self.function_breakpoints
    if operation is EnableBreakpoint {
      // Like adding an enabled breakpoint, resolution failure and uncertain
      // execution loss retain the user's enabled intent for the next run.
      self.source_breakpoints = sources
      self.function_breakpoints = functions
    }
    try
      self.synchronize_breakpoints(
        BreakpointConfiguration::new(sources, functions),
      )
      |> ignore
    catch {
      BreakpointManagementRejected(message) => {
        self.source_breakpoints = old_sources
        self.function_breakpoints = old_functions
        raise BreakpointManagementRejected(message)
      }
      error => raise error
    }
  }
  // Commit only after the backend has confirmed the desired configuration.
  self.source_breakpoints = sources
  self.function_breakpoints = functions
  let entry = self
    .breakpoints()
    .iter()
    .find_first(item => item.id == id)
    .unwrap_or(previous)
  { operation, breakpoint: entry, changed: true, }
}
