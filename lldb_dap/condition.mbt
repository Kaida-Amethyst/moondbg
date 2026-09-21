///|
/// Adapter IDs are scoped to a target. Each file replacement replaces its
/// entire binding set, including unconditional entries and duplicate IDs.
pub struct BreakpointConditions {
  priv files : Map[String, Array[(Int, @expression.IntCondition?)]]
}

///|
pub fn BreakpointConditions::new() -> BreakpointConditions {
  { files: {}, }
}

///|
pub fn BreakpointConditions::replace(
  self : BreakpointConditions,
  source : String,
  bindings : Array[(Int, @expression.IntCondition?)],
) -> Unit {
  self.files.set(source, bindings.copy())
}

///|
/// None means preserve the stop. Missing/unknown hit IDs, signals, panic or
/// co-located unconditional/function breakpoints must never be auto-continued.
pub fn BreakpointConditions::for_stop(
  self : BreakpointConditions,
  body : Json,
) -> Array[@expression.IntCondition]? {
  guard body
    is { "reason": String("breakpoint"), "hitBreakpointIds": Array(ids), .. } &&
    !ids.is_empty() else {
    return None
  }
  let conditions : Array[@expression.IntCondition] = []
  for id in ids {
    guard id is Number(id, ..) &&
      id >= 0 &&
      id <= 2147483647 &&
      id == id.to_int().to_double() else {
      return None
    }
    let before = conditions.length()
    for entries in self.files.values() {
      for (raw, condition) in entries {
        if raw == id.to_int() {
          guard condition is Some(condition) else { return None }
          conditions.push(condition)
        }
      }
    }
    guard before < conditions.length() else { return None }
  }
  Some(conditions)
}

///|
pub async fn VariableInspector::read_condition_int(
  self : VariableInspector,
  frame : Int,
  name : String,
) -> Int {
  let identity = self.tree_identity(frame)
  let path = @debugger.VariablePath::new(name, [])
  let variable = match self.resolve_variable_path(identity, frame, path) {
    DapVariableResolved(variable) => variable
    DapVariableResolutionFailed(@debugger.VariableLookupFailed(failure)) =>
      raise @expression.ConditionError(failure.message())
    _ => raise @expression.ConditionError("Variable '\{name}' is unavailable")
  }
  guard variable.is_available() else {
    raise @expression.ConditionError("Variable '\{name}' is unavailable")
  }
  guard variable.source_type_name() == Some("Int") else {
    raise @expression.ConditionError(
      "Variable '\{name}' must be Int, got \{variable.source_type_name().unwrap_or(variable.type_name.unwrap_or("unknown type"))}",
    )
  }
  let value = @expression.decimal_int(variable.value.trim())
  self.ensure_variable_identity(identity)
  value
}

///|
/// Multiple conditional breakpoints at the same instruction use OR semantics.
/// Evaluate all to ensure a failed read is not silently hidden by another hit.
pub async fn VariableInspector::test_conditions(
  self : VariableInspector,
  frame : Int,
  conditions : Array[@expression.IntCondition],
) -> Result[Bool, String] {
  let values : Map[String, Int] = Map([])
  let mut matches = false
  for condition in conditions {
    let value = try {
      match values.get(condition.variable) {
        Some(value) => value
        None => {
          let value = self.read_condition_int(frame, condition.variable)
          values.set(condition.variable, value)
          value
        }
      }
    } catch {
      error => {
        if @async.is_cancellation_error(error) {
          raise error
        }
        let message = match error {
          @expression.ConditionError(message) => message
          _ => @debug.to_string(error)
        }
        return Err("Condition '\{condition.text}' failed: \{message}")
      }
    }
    if condition.evaluate(value) {
      matches = true
    }
  }
  Ok(matches)
}
