///|
pub suberror VariableEvaluationError {
  VariableEvaluationError(String)
}

///|
/// A source-level expression suitable for Watch, never an LLDB evaluateName.
/// Omit paths the current grammar cannot express (e.g. enum positional payloads).
pub fn VariableNode::evaluate_name(self : VariableNode) -> String? {
  let steps = self.access.map(step => {
    match step {
      Member(name) => @debugger.VariablePathStep::Field(name)
      Element(index) => @debugger.VariablePathStep::Index(index)
    }
  })
  let path = @debugger.VariablePath::new(self.root, steps)
  let text = path.display_name()
  guard @debugger.VariablePath::parse(text) == Some(path) else { return None }
  Some(text)
}

///|
/// Resolve only a parsed read-only path, then describe one level. Descendants
/// reuse the same tree locators and paging as the Locals view.
pub async fn VariableInspector::tree_evaluate(
  self : VariableInspector,
  frame_id : Int,
  path : @debugger.VariablePath,
) -> VariableNode {
  guard @debugger.VariablePath::parse(path.display_name()) == Some(path) else {
    raise VariableEvaluationError("Invalid variable path")
  }
  let identity = self.tree_identity(frame_id)
  let variable = match self.resolve_variable_path(identity, frame_id, path) {
    DapVariableResolved(variable) => variable
    DapVariableResolutionFailed(@debugger.VariableLookupFailed(failure)) =>
      raise VariableEvaluationError(failure.message())
    DapVariableResolutionFailed(_) =>
      raise VariableEvaluationError("Variable is unavailable")
  }
  let access = path
    .steps()
    .iter()
    .map(step => {
      match step {
        @debugger.VariablePathStep::Field(name) => Member(name)
        @debugger.VariablePathStep::Index(index) => Element(index)
      }
    })
    .collect()
  let node = self.describe_node(identity, variable, path.root_name(), access)
  self.ensure_variable_identity(identity)
  node
}
