///|
fn breakpoint_status_text(status : @debugger.BreakpointStatus) -> String {
  match status {
    @debugger.Pending => "pending"
    @debugger.Verified => "verified"
    @debugger.Rejected(message) => "rejected: \{message}"
  }
}

///|
fn breakpoint_installation_text(
  installation : @debugger.BreakpointInstallation,
) -> String {
  match installation {
    @debugger.NotInstalled => "not installed"
    @debugger.CurrentInstallation(status) =>
      "current: \{breakpoint_status_text(status)}"
    @debugger.PreviousInstallation(status) =>
      "previous: \{breakpoint_status_text(status)}"
  }
}

///|
fn breakpoint_target_text(target : @debugger.BreakpointTarget) -> String {
  match target {
    @debugger.SourceTarget(display_path~, line~, ..) =>
      "\{display_path}:\{line}"
    @debugger.FunctionTarget(display_name~, ..) => "function \{display_name}"
  }
}

///|
fn breakpoint_actual_text(location : @debugger.BreakpointLocation) -> String {
  match (location.source_path, location.line) {
    (Some(path), Some(line)) =>
      match location.column {
        Some(column) => "\{path}:\{line}:\{column}"
        None => "\{path}:\{line}"
      }
    _ => "source location unknown"
  }
}

///|
fn breakpoint_list_lines(
  entries : Array[@debugger.BreakpointListEntry],
) -> Array[String] {
  guard entries is [_, ..] else { return ["No breakpoints."] }
  let ordered = entries.copy()
  ordered.sort_by((left, right) => left.id.compare(right.id))
  let lines = ["Breakpoints:"]
  for entry in ordered {
    let enabled = if entry.enabled { "enabled" } else { "disabled" }
    lines.push(
      "  \{entry.id}  \{enabled}  requested: \{breakpoint_target_text(entry.target)}",
    )
    lines.push(
      "     installation: \{breakpoint_installation_text(entry.installation)}",
    )
    let previous = entry.installation is @debugger.PreviousInstallation(_)
    let prefix = if previous { "previous " } else { "" }
    if entry.target
      is @debugger.FunctionTarget(
        selector=@debugger.MoonBitFunctionFamily(_),
        ..
      ) {
      let count = match entry.location_count {
        Some(count) => "\{count}"
        None => "unknown"
      }
      lines.push("     \{prefix}locations: \{count}")
    }
    if entry.locations is [] {
      lines.push("     \{prefix}actual: source location unknown")
    } else {
      for index, location in entry.locations {
        guard index < 3 else { break }
        lines.push("     \{prefix}actual: \{breakpoint_actual_text(location)}")
      }
      if entry.locations.length() > 3 {
        lines.push("     ... (showing 3 representative locations)")
      }
    }
  }
  lines
}

///|
fn breakpoint_managed_line(
  result : @debugger.BreakpointManagementResult,
) -> String {
  let verb = match result.operation {
    @debugger.DeleteBreakpoint => "deleted"
    @debugger.DisableBreakpoint => "disabled"
    @debugger.EnableBreakpoint => "enabled"
  }
  guard result.changed else {
    return "Breakpoint \{result.breakpoint.id} is already \{verb}."
  }
  if result.operation is @debugger.EnableBreakpoint {
    "Breakpoint \{result.breakpoint.id} enabled (\{breakpoint_installation_text(result.breakpoint.installation)})."
  } else {
    "Breakpoint \{result.breakpoint.id} \{verb}."
  }
}

///|
fn breakpoint_management_failure_line(
  failure : BreakpointManagementFailure,
) -> String {
  match failure {
    BreakpointIdNotFound(id) => "Breakpoint \{id} was not found."
    BreakpointManagementRefused(message) =>
      "Cannot manage breakpoint: \{message}"
  }
}
