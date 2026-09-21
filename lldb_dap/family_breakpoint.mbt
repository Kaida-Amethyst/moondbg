///|
/// Keep CLI handle ownership distinct from protocol bookkeeping. LLDB-DAP's
/// hitBreakpointIds uses the same SBTarget IDs for CLI-created breakpoints.
priv enum LldbBreakpointId {
  LldbBreakpointId(Int)
}

///|
priv struct FamilyHandle {
  id : LldbBreakpointId
  enabled : Bool
}

///|
priv struct FamilyConfiguration {
  breakpoint : LogicalFunctionBreakpoint
  enabled : Bool
}

///|
fn FamilyConfiguration::from_domain(
  value : @debugger.FunctionBreakpoint,
) -> FamilyConfiguration {
  {
    breakpoint: LogicalFunctionBreakpoint::from_domain(value),
    enabled: value.enabled(),
  }
}

///|
async fn DebugExecution::family_command(
  self : DebugExecution,
  command : String,
) -> String? {
  self.function_driver().command(command)
}

///|
async fn DebugExecution::change_family(
  self : DebugExecution,
  id : LldbBreakpointId,
  operation : String,
) -> Unit {
  self.function_driver().change(id, operation)
}

///|
async fn FunctionBreakpointDriver::change(
  self : FunctionBreakpointDriver,
  id : LldbBreakpointId,
  operation : String,
) -> Unit {
  let LldbBreakpointId(number) = id
  let expected = match operation {
    "delete" => "1 breakpoints deleted; 0 breakpoint locations disabled."
    "disable" => "1 breakpoints disabled."
    "enable" => "1 breakpoints enabled."
    _ =>
      raise @debugger.BreakpointSyncError::BreakpointSyncRejected(
        "invalid family operation",
      )
  }
  guard self.command("breakpoint \{operation} \{number}") is Some(result) &&
    result.trim() == expected else {
    raise @debugger.BreakpointSyncError::BreakpointSyncUncertain(
      "LLDB did not confirm family breakpoint \{operation}",
    )
  }
}

///|
async fn DebugExecution::synchronize_families(
  self : DebugExecution,
  configuration : Array[FamilyConfiguration],
) -> Unit {
  let desired : Map[Int, FamilyConfiguration] = Map([])
  for item in configuration {
    desired.set(item.breakpoint.id, item)
  }
  let old_ids = self.breakpoint_state.families.keys().collect()
  for id in old_ids {
    guard self.breakpoint_state.families.get(id) is Some(handle) else {
      continue
    }
    match desired.get(id) {
      None => {
        self.change_family(handle.id, "delete")
        self.breakpoint_state.families.remove(id)
        self.breakpoint_state.outcomes.remove(id)
      }
      Some(item) if item.enabled != handle.enabled => {
        self.change_family(
          handle.id,
          if item.enabled {
            "enable"
          } else {
            "disable"
          },
        )
        self.breakpoint_state.families.set(id, {
          id: handle.id,
          enabled: item.enabled,
        })
        if item.enabled {
          self.refresh_family_details(id, handle.id)
        }
      }
      _ => ()
    }
  }
  for item in configuration {
    if item.enabled &&
      self.breakpoint_state.families.get(item.breakpoint.id) is None {
      self.configure_family_function_breakpoint(item.breakpoint)
    }
  }
}

///|
fn family_location_count(result : StringView, id : LldbBreakpointId) -> Int? {
  let LldbBreakpointId(number) = id
  guard result.trim().has_prefix("\{number}:") &&
    result.split_once("locations = ") is Some((_, rest)) else {
    return None
  }
  let digits = family_token(rest, ch => ch >= '0' && ch <= '9')
  guard rest.strip_prefix(digits) is Some(tail) &&
    (tail.trim().is_empty() || tail.has_prefix(",")) else {
    return None
  }
  Some(@string.parse_int(digits, base=10)) catch {
    _ => None
  }
}

///|
fn family_token(text : StringView, accepts : (Char) -> Bool) -> String {
  let output = StringBuilder()
  for ch in text {
    guard accepts(ch) else { break }
    output.write_char(ch)
  }
  output.to_string()
}

///|
fn family_address_value(text : StringView) -> UInt64? {
  let digits = match text.strip_prefix("0x") {
    Some(digits) => digits
    None =>
      match text.strip_prefix("0X") {
        Some(digits) => digits
        None => return None
      }
  }
  guard !digits.is_empty() &&
    digits
    .iter()
    .all(ch => {
      (ch >= '0' && ch <= '9') ||
      (ch >= 'a' && ch <= 'f') ||
      (ch >= 'A' && ch <= 'F')
    }) else {
    return None
  }
  Some(@string.parse_uint64(digits, base=16)) catch {
    _ => None
  }
}

///|
fn family_addresses(
  result : StringView,
  count : Int,
  id : LldbBreakpointId,
) -> Array[String]? {
  let LldbBreakpointId(number) = id
  guard result.trim().has_prefix("\{number}:") else { return None }
  let addresses : Array[String] = []
  let indices : Map[Int, Bool] = Map([])
  for line in result.split("\n") {
    guard line.split_once("address = ") is Some((prefix, part)) else {
      continue
    }
    guard prefix.trim().strip_prefix("\{number}.") is Some(location) &&
      location.split_once(":") is Some((index_text, _)) else {
      return None
    }
    let index = Some(@string.parse_int(index_text, base=10)) catch { _ => None }
    guard index is Some(index) && index > 0 && indices.get(index) is None else {
      return None
    }
    indices.set(index, true)
    guard addresses.length() < count && part.strip_prefix("0x") is Some(hex) else {
      return None
    }
    let digits = family_token(hex, ch => {
      (ch >= '0' && ch <= '9') ||
      (ch >= 'a' && ch <= 'f') ||
      (ch >= 'A' && ch <= 'F')
    })
    guard !digits.is_empty() &&
      hex.strip_prefix(digits) is Some(tail) &&
      (tail.trim().is_empty() || tail.has_prefix(",") || tail.has_prefix(" ")) else {
      return None
    }
    addresses.push("0x\{digits}")
  }
  if addresses.length() == count {
    Some(addresses)
  } else {
    None
  }
}

///|
async fn DebugExecution::family_source_location(
  self : DebugExecution,
  address : String,
) -> @debugger.BreakpointLocation? {
  let seq = self.dispatcher.send_request("disassemble", {
    "memoryReference": address,
    "instructionCount": 1,
    "resolveSymbols": false,
  })
  guard self.wait_for_response(seq, "disassemble") is Some(response) else {
    raise @debugger.BreakpointSyncError::BreakpointSyncUncertain(
      "lldb-dap exited while reading family locations",
    )
  }
  guard response.success() &&
    response.body() is { "instructions": [instruction], .. } else {
    return None
  }
  try {
    guard instruction is Object(fields) else { return None }
    match fields.get("address") {
      Some(String(actual)) => {
        guard family_address_value(actual) is Some(actual_value) &&
          family_address_value(address) is Some(requested_value) &&
          actual_value == requested_value else {
          return None
        }
      }
      None => ()
      _ => return None
    }
    let source_path = match fields.get("location") {
      Some(Object(_) as location) =>
        breakpoint_optional_string(location, "path")
      None => None
      _ => return None
    }
    Some({
      source_path,
      line: breakpoint_optional_int(instruction, "line", minimum=1),
      column: breakpoint_optional_int(instruction, "column", minimum=1),
      instruction_reference: Some(address),
    })
  } catch {
    _ => None
  }
}

///|
async fn DebugExecution::refresh_family_details(
  self : DebugExecution,
  logical_id : Int,
  id : LldbBreakpointId,
  created_count? : Int? = None,
) -> Unit {
  let LldbBreakpointId(number) = id
  let count = match self.family_command("breakpoint list --brief \{number}") {
    Some(result) => family_location_count(result, id)
    None => None
  }
  let locations : Array[@debugger.BreakpointLocation] = []
  if count is Some(count) && count > 0 && count <= 8 {
    if self.family_command("breakpoint list --full \{number}") is Some(result) &&
      family_addresses(result, count, id) is Some(addresses) {
      for address in addresses {
        if self.family_source_location(address) is Some(location) {
          locations.push(location)
        }
      }
    }
  }
  let known_count = match count {
    Some(_) => count
    None => created_count
  }
  self.breakpoint_state.outcomes.set(logical_id, {
    actual_line: match locations {
      [first, ..] => first.line
      [] => None
    },
    dap_id: None,
    location_count: known_count,
    locations,
    status: match known_count {
      Some(0) => AdapterRejected("no matching function instances were found")
      Some(_) => AdapterVerified
      None =>
        match self.breakpoint_state.outcomes.get(logical_id) {
          Some(previous) => previous.status
          None => AdapterRejected("family location information is unavailable")
        }
    },
  })
}
