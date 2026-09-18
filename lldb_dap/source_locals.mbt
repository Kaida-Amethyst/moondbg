///|
// Both frontends share lexical shadow resolution, including unavailable locals.
async fn VariableInspector::source_locals(
  self : VariableInspector,
  identity : VariableCacheIdentity,
  frame_id : Int,
  scopes : Array[DapScope],
) -> Array[DapVariable] {
  let groups : Map[String, Array[DapVariable]] = Map([])
  let order : Array[String] = []
  for scope in scopes {
    guard scope.is_locals() else { continue }
    for variable in self.load_variables(identity, scope.variables_reference) {
      let name = variable.source_local_name()
      match groups.get(name) {
        Some(group) => group.push(variable)
        None => {
          groups.set(name, [variable])
          order.push(name)
        }
      }
    }
  }
  let variables = []
  for name in order {
    guard groups.get(name) is Some([first, .. rest]) else { continue }
    let variable = if rest.length() == 0 {
      { ..first, name, }
    } else {
      match self.evaluate_shadowed_root(identity, frame_id, name) {
        DapVariableResolved(variable) => variable
        DapVariableResolutionFailed(_) =>
          {
            ..first,
            name,
            type_name: unavailable_shadowed_local_summary(name, [first, ..rest]).type_name(),
            value: "<variable not available>",
          }
      }
    }
    variables.push(variable)
  }
  self.ensure_variable_identity(identity)
  variables
}
