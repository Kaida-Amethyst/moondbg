///|
/// Source ownership is supplied by the build system, not inferred from .mbt
/// suffixes, a directory prefix, or the function's display name. Keep physical
/// frame indices and all library/runtime frames intact for manual inspection.
fn DebugSession::panic_project_frame(
  self : DebugSession,
  stack : StackSnapshot,
) -> FrameSelection? {
  for frame in stack.frames() {
    if frame.source_path() is Some(path) &&
      self.project_sources.contains(path) &&
      frame.line() is Some(line) &&
      line > 0 {
      return stack.selection(frame.physical_index())
    }
  }
  None
}
