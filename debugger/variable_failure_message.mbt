///|
pub fn VariableLookupFailure::message(
  failure : VariableLookupFailure,
) -> String {
  match failure {
    VariableRootNotFound(root) =>
      "Variable '\{root}' was not found in the current frame. Cannot distinguish an out-of-scope variable from missing debug information."
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
    VariableReportedUnavailable(path, reason) =>
      "Variable '\{path}' is unavailable: lldb-dap reported \{reason}"
    VariableMemoryReadFailed(path, reason) =>
      "Memory read failed for '\{path}': \{reason}"
    VariableInspectionFailed(path, message) =>
      "Cannot inspect '\{path}': \{message}"
  }
}
