///|
/// Shared MoonBit value interpretation, independent of execution ownership.
/// The caller owns request routing and stop validity; this object never reads
/// from a transport or launches/resumes a target. One inspector is used serially.
pub struct VariableInspector {
  priv request_value : async (String, Json) -> @dap.DapResponse
  priv current_epoch : () -> Int?
  priv remember_reference : (Int) -> Unit raise
  priv variable_cache : StopVariableCache
  priv capabilities : Json
}

///|
pub fn VariableInspector::new(
  request : async (String, Json) -> @dap.DapResponse,
  current_epoch : () -> Int?,
  capabilities : Json,
) -> VariableInspector {
  {
    request_value: request,
    current_epoch,
    capabilities,
    remember_reference: _ => (),
    variable_cache: StopVariableCache::new(),
  }
}

///|
fn DebugExecution::variable_inspector(
  self : DebugExecution,
) -> VariableInspector {
  {
    request_value: (command, args) => self.request_allow_failure(command, args),
    current_epoch: () => self.machine.current_stop_epoch(),
    remember_reference: reference => {
      self.machine.remember_variable_reference(reference)
    },
    variable_cache: self.variable_cache,
    capabilities: self.capabilities,
  }
}

///|
async fn VariableInspector::request_allow_failure(
  self : VariableInspector,
  command : String,
  arguments : Json,
) -> @dap.DapResponse {
  (self.request_value)(command, arguments)
}

///|
async fn VariableInspector::request(
  self : VariableInspector,
  command : String,
  arguments : Json,
) -> @dap.DapResponse {
  validate_response(self.request_allow_failure(command, arguments), command)
}
