///|
pub suberror MemoryReadError {
  MemoryReadError(String)
} derive(Debug)

///|
pub extend MemoryReadError with @debug.Debug::{to_repr}

///|
fn inspection_failure(
  path : String,
  error : Error,
) -> @debugger.VariableLookupFailure? {
  match error {
    MemoryReadError(reason) =>
      Some(@debugger.VariableLookupFailure::memory_read_failed(path, reason))
    BufferInspectionError(reason)
    | VariableEvaluationError(reason)
    | InvalidIndexedCollectionValue(reason)
    | InvalidIndexedElementValue(reason)
    | InvalidEnumValue(reason) =>
      Some(@debugger.VariableLookupFailure::inspection_failed(path, reason))
    RequestFailed(command~, message~) =>
      Some(
        @debugger.VariableLookupFailure::inspection_failed(
          path,
          "lldb-dap \{command} failed: \{message}",
        ),
      )
    _ => None
  }
}

///|
fn DapVariable::unavailable_reason(self : DapVariable) -> String? {
  if self.value.has_prefix("<error:") ||
    self.value
    is ("<variable not available>" | "<unavailable>" | "<optimized out>") {
    Some(self.value)
  } else {
    None
  }
}

///|
fn reported_unavailable(
  path : String,
  reason : String,
) -> @debugger.VariableLookupResult {
  @debugger.VariableLookupResult::failed(
    @debugger.VariableLookupFailure::reported_unavailable(path, reason),
  )
}
