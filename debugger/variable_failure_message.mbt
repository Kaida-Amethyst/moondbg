///|
pub fn VariableLookupFailure::message(
  failure : VariableLookupFailure,
) -> String {
  match failure {
    VariableRootNotFound(root) =>
      "Variable '\{root}' was not found in the current frame."
    VariableFieldNotFound(owner, field) =>
      "Field '\{field}' was not found in '\{owner}'."
    VariableFieldAccessOnNonStruct(owner, field, _) =>
      "Cannot access field '\{field}' because '\{owner}' is not a struct."
    VariableIndexAccessOnNonCollection(owner, index, _) =>
      "Cannot access index \{index} because '\{owner}' is not an Array or FixedArray."
    VariableIndexOutOfBounds(owner, index, total_length) =>
      "Index \{index} is out of bounds for '\{owner}' with length \{total_length}."
    VariableUnavailable(path) =>
      "Variable '\{path}' is unavailable at the current location."
  }
}
