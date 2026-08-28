///|
/// Shared frontend dependencies. Individual command objects only retain their
/// parsed input and receive this context when they execute.
priv struct ReplContext {
  session : @moondbg.DebugSession
  registry : CommandRegistry
  renderer : &PresentationRenderer
  debug_context : @moondbg.DebugContext
}

///|
fn ReplContext::new(
  session : @moondbg.DebugSession,
  registry : CommandRegistry,
  renderer : &PresentationRenderer,
  debug_context? : @moondbg.DebugContext = @moondbg.DebugContext::empty(),
) -> ReplContext {
  { session, registry, renderer, debug_context, }
}

///|
async fn ReplContext::render(
  self : ReplContext,
  events : Array[PresentationEvent],
) -> Unit {
  self.renderer.render(events)
}
