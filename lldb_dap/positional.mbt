///|
fn DapVariable::is_tuple_type(self : DapVariable) -> Bool {
  self.source_type_name() is Some(name) && tuple_arity(name) is Some(_)
}

///|
fn tuple_arity(name : String) -> Int? {
  guard name.strip_prefix("(") is Some(rest) &&
    rest.strip_suffix(")") is Some(items) else {
    return None
  }
  guard items.trim() != "" else { return Some(0) }
  let chars = items.iter()
  for depth = 0, count = 1 {
    guard chars.next() is Some(ch) else {
      break if depth == 0 { Some(count) } else { None }
    }
    match ch {
      '(' | '[' => continue depth + 1, count
      ')' | ']' => {
        guard depth > 0 else { return None }
        continue depth - 1, count
      }
      ',' if depth == 0 => continue depth, count + 1
      _ => continue depth, count
    }
  }
}

///|
// DWARF member order is not the source position. Require an unambiguous,
// contiguous set of .N names and sort it before exposing it to either frontend.
fn ordered_position_members(
  children : Array[DapVariable],
) -> Array[DapVariable] raise {
  let positions : Map[Int, DapVariable] = Map([])
  for child in children {
    guard child.name.strip_prefix(".") is Some(digits) &&
      digits != "" &&
      digits.iter().all(ch => ch is ('0'..='9')) else {
      raise VariableEvaluationError(
        "Positional debug information has an invalid member name",
      )
    }
    let position = @string.parse_int(digits, base=10) catch {
      _ =>
        raise VariableEvaluationError("Positional member number is too large")
    }
    guard position >= 0 &&
      position < children.length() &&
      !positions.contains(position) else {
      raise VariableEvaluationError(
        "Positional debug information has duplicate or missing members",
      )
    }
    positions.set(position, { ..child, name: ".\{position}", })
  }
  Array::makei(children.length(), index => {
    guard positions.get(index) is Some(child) else {
      raise VariableEvaluationError(
        "Positional debug information has a missing member",
      )
    }
    child
  })
}

///|
/// Only the active enum constructor is consulted. This is shared by path
/// evaluation, REPL tuple rendering, and DAP expansion/re-resolution.
async fn VariableInspector::positional_members(
  self : VariableInspector,
  identity : VariableCacheIdentity,
  variable : DapVariable,
) -> (String, Array[DapVariable])? {
  guard variable.variables_reference > 0 else {
    if variable.is_tuple_type() {
      raise VariableEvaluationError("Tuple debug members are unavailable")
    }
    if variable.is_option_type() {
      raise VariableEvaluationError("Option debug members are unavailable")
    }
    return None
  }
  let children = self.load_variables(identity, variable.variables_reference)
  if optimized_option_members(variable, children) is Some(members) {
    return Some(members)
  }
  match detect_dap_enum_layout(children) {
    DapEnum(variants) => {
      let active = self.active_enum_variant(variants)
      let payload = if active.payload_reference > 0 {
        self.load_variables(identity, active.payload_reference)
      } else {
        []
      }
      Some((active.variant_name, ordered_position_members(payload)))
    }
    NotDapEnum if variable.is_tuple_type() => {
      guard variable.source_type_name() is Some(name) &&
        tuple_arity(name) == Some(children.length()) else {
        raise VariableEvaluationError("Tuple debug members are incomplete")
      }
      Some(("tuple", ordered_position_members(children)))
    }
    NotDapEnum => {
      if variable.is_option_type() {
        raise VariableEvaluationError(
          "Option debug representation is missing; rebuild with a compiler supporting the Option contract",
        )
      }
      None
    }
  }
}

///|
async fn VariableInspector::resolve_position(
  self : VariableInspector,
  identity : VariableCacheIdentity,
  variable : DapVariable,
  owner : String,
  position : Int,
) -> DapVariableResolution {
  let path = "\{owner}.\{position}"
  guard self.positional_members(identity, variable) is Some((kind, children)) else {
    return DapVariableResolutionFailed(
      @debugger.VariableLookupResult::inspection_failed(
        path, "Position access requires a tuple or an enum payload",
      ),
    )
  }
  guard position >= 0 && children.get(position) is Some(child) else {
    return DapVariableResolutionFailed(
      @debugger.VariableLookupResult::inspection_failed(
        path,
        "\{kind} has \{children.length()} positional member(s); .\{position} is out of bounds",
      ),
    )
  }
  guard child.is_available() else {
    return DapVariableResolutionFailed(
      @debugger.VariableLookupResult::unavailable(path),
    )
  }
  DapVariableResolved(child)
}

///|
async fn VariableInspector::materialize_tuple(
  self : VariableInspector,
  identity : VariableCacheIdentity,
  variable : DapVariable,
  depth : Int,
  budget : VariableMaterializationBudget,
) -> @debugger.VariableSnapshot {
  if budget.is_empty() ||
    depth >= budget.max_depth ||
    budget.is_visiting(variable.variables_reference) {
    return @debugger.VariableSnapshot::tuple(
      variable.name,
      variable.type_name,
      [],
      truncated=true,
    )
  }
  guard self.positional_members(identity, variable) is Some((_, members)) else {
    raise VariableEvaluationError("Tuple debug members are unavailable")
  }
  budget.enter_reference(variable.variables_reference)
  defer budget.leave_reference(variable.variables_reference)
  let children = []
  for item in members {
    guard !budget.is_empty() else { break }
    children.push(self.materialize_variable(identity, item, depth + 1, budget))
  }
  @debugger.VariableSnapshot::tuple(
    variable.name,
    variable.type_name,
    children,
    truncated=children.length() < members.length(),
  )
}
