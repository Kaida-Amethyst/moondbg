///|
fn breakpoint_optional_int(
  result : Json,
  field : String,
  minimum~ : Int,
) -> Int? raise {
  guard result is Object(fields) else {
    raise @moondbg.BreakpointSyncError::BreakpointSyncUncertain(
      "breakpoint result is not an object",
    )
  }
  match fields.get(field) {
    None => None
    Some(Number(value, ..)) if value >= minimum.to_double() &&
      value <= 2147483647.0 &&
      value.to_int().to_double() == value => Some(value.to_int())
    _ =>
      raise @moondbg.BreakpointSyncError::BreakpointSyncUncertain(
        "invalid breakpoint \{field} field",
      )
  }
}

///|
fn breakpoint_optional_string(result : Json, field : String) -> String? raise {
  guard result is Object(fields) else {
    raise @moondbg.BreakpointSyncError::BreakpointSyncUncertain(
      "breakpoint result is not an object",
    )
  }
  match fields.get(field) {
    None => None
    Some(String(value)) => Some(value)
    _ =>
      raise @moondbg.BreakpointSyncError::BreakpointSyncUncertain(
        "invalid breakpoint \{field} field",
      )
  }
}

///|
fn parse_breakpoint_outcome(result : Json) -> AdapterBreakpointOutcome raise {
  guard result is Object(fields) else {
    raise @moondbg.BreakpointSyncError::BreakpointSyncUncertain(
      "breakpoint result is not an object",
    )
  }
  let verified = match fields.get("verified") {
    Some(True) => true
    Some(False) => false
    _ =>
      raise @moondbg.BreakpointSyncError::BreakpointSyncUncertain(
        "breakpoint result has no boolean verified field",
      )
  }
  let message = breakpoint_optional_string(result, "message")
  let id = breakpoint_optional_int(result, "id", minimum=0)
  let line = breakpoint_optional_int(result, "line", minimum=1)
  let column = breakpoint_optional_int(result, "column", minimum=1)
  let instruction_reference = breakpoint_optional_string(
    result, "instructionReference",
  )
  let source_path = match fields.get("source") {
    None => None
    Some(Object(_) as source) => breakpoint_optional_string(source, "path")
    _ =>
      raise @moondbg.BreakpointSyncError::BreakpointSyncUncertain(
        "invalid breakpoint source field",
      )
  }
  let locations : Array[@moondbg.BreakpointLocation] = if source_path is None &&
    line is None &&
    column is None &&
    instruction_reference is None {
    []
  } else {
    [{ source_path, line, column, instruction_reference, }]
  }
  {
    actual_line: line,
    dap_id: id,
    location_count: None,
    locations,
    status: if verified {
      AdapterVerified
    } else {
      AdapterRejected(
        message.unwrap_or("lldb-dap could not verify this breakpoint"),
      )
    },
  }
}

///|
/// Parse the entire replacement before installing any outcome. Request-level
/// failure is not proof that LLDB left the previous set untouched.
fn parse_breakpoint_replacement(
  response : @dap.DapResponse,
  expected : Int,
) -> Array[AdapterBreakpointOutcome] raise {
  guard response.success() else {
    raise @moondbg.BreakpointSyncError::BreakpointSyncUncertain(
      response
      .message()
      .unwrap_or("lldb-dap rejected breakpoint synchronization"),
    )
  }
  guard response.body() is { "breakpoints": Array(results), .. } &&
    results.length() == expected else {
    raise @moondbg.BreakpointSyncError::BreakpointSyncUncertain(
      "lldb-dap returned an incomplete breakpoint replacement",
    )
  }
  results.map(parse_breakpoint_outcome)
}

///|
async fn LldbDapSession::synchronize_breakpoints(
  self : LldbDapSession,
  sources : Array[LogicalSourceBreakpoint],
  functions : Array[LogicalFunctionBreakpoint],
  families? : Array[FamilyConfiguration] = family_function_breakpoints(
    functions,
  ).map(breakpoint => { breakpoint, enabled: true, }),
) -> @moondbg.BreakpointSyncResult {
  guard self.state() is Stopped && self.execution is Some(execution) else {
    raise @moondbg.BreakpointSyncError::BreakpointSyncRejected(
      "breakpoint synchronization requires a stopped execution",
    )
  }
  let affected : Map[String, Bool] = Map([])
  let all_paths : Array[String] = []
  let considered = self.source_breakpoints.copy()
  considered.append(sources)
  for breakpoint in considered {
    guard affected.get(breakpoint.source_path) is None else { continue }
    affected.set(breakpoint.source_path, true)
    let previous = breakpoints_for_source(
      self.source_breakpoints,
      breakpoint.source_path,
    )
    let current = breakpoints_for_source(sources, breakpoint.source_path)
    if previous != current {
      all_paths.push(breakpoint.source_path)
    }
  }
  let previous_exact = exact_function_breakpoints(self.function_breakpoints)
  let current_exact = exact_function_breakpoints(functions)
  // Source replacements and exact replacement use the same strict parser for
  // additions, removals and enable/disable changes, including empty arrays.
  for source_path in all_paths {
    execution.configure_source_breakpoints(sources, source_path)
  }
  if previous_exact != current_exact {
    execution.configure_exact_function_breakpoints(current_exact)
  }
  execution.synchronize_families(families)
  // Only now can this execution's applied configuration be replaced. Shared
  // DAP ids are never deleted individually: group replacement owns them.
  let active : Map[Int, Bool] = Map([])
  for breakpoint in sources {
    active.set(breakpoint.id, true)
  }
  for breakpoint in functions {
    active.set(breakpoint.id, true)
  }
  let removed = execution.breakpoint_state.outcomes
    .keys()
    .filter(id => {
      active.get(id) is None &&
      execution.breakpoint_state.families.get(id) is None
    })
    .collect()
  for id in removed {
    execution.breakpoint_state.outcomes.remove(id)
  }
  self.source_breakpoints.clear()
  self.source_breakpoints.append(sources)
  self.function_breakpoints.clear()
  self.function_breakpoints.append(functions)
  @moondbg.BreakpointSyncResult::new(
    self.source_breakpoints(),
    self.function_breakpoints(),
  )
}
