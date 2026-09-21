///|
fn DapVariable::is_option_type(self : DapVariable) -> Bool {
  self.type_name is Some(name) &&
  name.trim().has_prefix("moonbitlang/core/option/Option[")
}

///|
/// Versioned compiler contract, not a heuristic on a bare integer or pointer.
/// None's overlapping .0 view must never be inspected or expanded.
/// Experimental until compiler review lands; see docs/option_view.md for the
/// producer/consumer mapping. No marker means the existing boxed enum path;
/// erased stable-toolchain integers/pointers are not inferred to be Options.
fn optimized_option_members(
  variable : DapVariable,
  children : Array[DapVariable],
) -> (String, Array[DapVariable])? raise {
  guard variable.is_option_type() else { return None }
  let markers = children.filter(child => {
    child.name.has_prefix("__moonbit_option_")
  })
  guard markers is [marker] else {
    if !markers.is_empty() {
      raise VariableEvaluationError(
        "Option debug information has duplicate representation markers",
      )
    }
    return None
  }
  guard children.length() == 2 &&
    children.named_child(".0") is Some(payload) &&
    payload.type_name is Some(_) else {
    raise VariableEvaluationError(
      "Option debug information has an invalid payload layout",
    )
  }
  let (sentinel, expected_type) = match marker.name {
    "__moonbit_option_v1_null" => (0UL, @runtime_value.NativeUInt64)
    "__moonbit_option_v1_i64_4294967296" =>
      (4294967296UL, @runtime_value.NativeUInt64)
    "__moonbit_option_v1_i32_4294967295" =>
      (4294967295UL, @runtime_value.NativeUInt)
    "__moonbit_option_v1_i32_65536" => (65536UL, @runtime_value.NativeUInt)
    _ =>
      raise VariableEvaluationError(
        "Unsupported Option debug representation or version",
      )
  }
  guard marker.is_available() &&
    marker.type_name is Some(raw_type) &&
    @runtime_value.native_scalar_from_debug_type(raw_type) ==
    Some(expected_type) else {
    raise VariableEvaluationError(
      "Option discriminator is unavailable or has the wrong storage type",
    )
  }
  let raw = @string.parse_uint64(marker.value, base=10) catch {
    _ =>
      raise VariableEvaluationError(
        "Option discriminator is not an unsigned integer",
      )
  }
  guard expected_type != @runtime_value.NativeUInt || raw <= 4294967295UL else {
    raise VariableEvaluationError(
      "Option discriminator exceeds its storage width",
    )
  }
  if raw == sentinel {
    return Some(("None", []))
  }
  // Validate the widened scalar domain; a corrupt representation is not Some.
  let valid = match (marker.name, payload.source_type_name()) {
    ("__moonbit_option_v1_i64_4294967296", Some("Int" | "UInt")) =>
      raw <= 2147483647UL || raw >= 18446744071562067968UL
    ("__moonbit_option_v1_i32_4294967295", Some("Bool")) => raw <= 1UL
    _ => true
  }
  guard valid else {
    raise VariableEvaluationError("Invalid Option scalar representation")
  }
  guard payload.is_available() else {
    raise VariableEvaluationError("Some payload is unavailable")
  }
  Some(("Some", [payload]))
}
