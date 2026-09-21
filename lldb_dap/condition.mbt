///|
/// Adapter IDs are scoped to a target. Each file replacement replaces its
/// entire binding set, including unconditional entries and duplicate IDs.
pub struct BreakpointConditions {
  priv files : Map[String, Array[(Int, @expression.Condition?)]]
}

///|
pub fn BreakpointConditions::new() -> BreakpointConditions {
  { files: {}, }
}

///|
pub fn BreakpointConditions::replace(
  self : BreakpointConditions,
  source : String,
  bindings : Array[(Int, @expression.Condition?)],
) -> Unit {
  self.files.set(source, bindings.copy())
}

///|
/// None means preserve the stop. Missing/unknown hit IDs, signals, panic or
/// co-located unconditional/function breakpoints must never be auto-continued.
pub fn BreakpointConditions::for_stop(
  self : BreakpointConditions,
  body : Json,
) -> Array[@expression.Condition]? {
  guard body
    is { "reason": String("breakpoint"), "hitBreakpointIds": Array(ids), .. } &&
    !ids.is_empty() else {
    return None
  }
  let conditions : Array[@expression.Condition] = []
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
/// Shared, typed scalar inspection for condition evaluation. Resolve through
/// the same field/index traversal as print, without reading VariableNode.value.
pub async fn VariableInspector::read_scalar(
  self : VariableInspector,
  frame : Int,
  path : @debugger.VariablePath,
) -> @expression.ScalarValue {
  guard @debugger.VariablePath::parse(path.display_name()) == Some(path) else {
    raise @expression.ConditionError("Invalid variable path")
  }
  let identity = self.tree_identity(frame)
  let variable = match self.resolve_variable_path(identity, frame, path) {
    DapVariableResolved(variable) => variable
    DapVariableResolutionFailed(@debugger.VariableLookupFailed(failure)) =>
      raise @expression.ConditionError(failure.message())
    _ =>
      raise @expression.ConditionError(
        "Variable '\{path.display_name()}' is unavailable",
      )
  }
  guard variable.is_available() else {
    raise @expression.ConditionError(
      "Variable '\{path.display_name()}' is unavailable",
    )
  }
  guard variable.source_type_name() is Some(type_name) else {
    raise @expression.ConditionError(
      "Variable '\{path.display_name()}' has no known scalar type",
    )
  }
  let value = @expression.ScalarValue::decode(type_name, variable.value)
  self.ensure_variable_identity(identity)
  value
}

///|
async fn VariableInspector::cached_scalar(
  self : VariableInspector,
  frame : Int,
  path : @debugger.VariablePath,
  values : Map[String, @expression.ScalarValue],
) -> @expression.ScalarValue {
  let key = path.display_name()
  match values.get(key) {
    Some(value) => value
    None => {
      let value = self.read_scalar(frame, path)
      values.set(key, value)
      value
    }
  }
}

///|
/// Co-located conditional breakpoints use OR semantics. Evaluate all so a
/// failed read is never silently hidden by another hit. Cache only this stop.
pub async fn VariableInspector::test_conditions(
  self : VariableInspector,
  frame : Int,
  conditions : Array[@expression.Condition],
) -> Result[Bool, String] {
  let values : Map[String, @expression.ScalarValue] = Map([])
  let mut matches = false
  for condition in conditions {
    let result = try {
      let left = self.cached_scalar(frame, condition.left, values)
      let right = match condition.right {
        @expression.PathOperand(path) => self.cached_scalar(frame, path, values)
        _ =>
          match condition.literal_value(left) {
            Some(value) => value
            None =>
              raise @expression.ConditionError("Missing condition operand")
          }
      }
      condition.evaluate(left, right)
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
    if result {
      matches = true
    }
  }
  Ok(matches)
}
