///|
/// Errors produced while encoding, receiving, classifying or routing raw DAP
/// messages. This type contains no debugger-domain state.
pub(all) suberror DapClientError {
  AdapterClosed
  MissingContentLength
  InvalidContentLength(String)
  InvalidMessage(Json)
  DuplicateResponse(Int)
  InvalidSequence(Int)
} derive(Debug)

///|
pub extend DapClientError with @debug.Debug::{to_repr}
