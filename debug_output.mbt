///|
pub enum DebugOutputKind {
  StandardOutput
  StandardError
  OtherOutput
} derive(Debug, Eq)

///|
pub extend DebugOutputKind with @debug.Debug::{to_repr}

///|
pub extend DebugOutputKind with Eq::{equal, not_equal}

///|
pub struct DebugOutput {
  priv kind : DebugOutputKind
  priv text : String
}

///|
/// Creates standard output after an adapter has classified its channel.
pub fn DebugOutput::standard_output(text : String) -> DebugOutput {
  { kind: StandardOutput, text, }
}

///|
/// Creates standard error after an adapter has classified its channel.
pub fn DebugOutput::standard_error(text : String) -> DebugOutput {
  { kind: StandardError, text, }
}

///|
/// Creates output which is neither stdout nor stderr.
pub fn DebugOutput::other(text : String) -> DebugOutput {
  { kind: OtherOutput, text, }
}

///|
pub fn DebugOutput::kind(self : DebugOutput) -> DebugOutputKind {
  self.kind
}

///|
pub fn DebugOutput::text(self : DebugOutput) -> String {
  self.text
}
