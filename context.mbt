///|
/// Shared frontend dependencies. Individual command objects only retain their
/// parsed input and receive this context when they execute.
priv struct ReplContext {
  session : @debugger.DebugSession
  registry : CommandRegistry
  renderer : &PresentationRenderer
}

///|
fn ReplContext::new(
  session : @debugger.DebugSession,
  registry : CommandRegistry,
  renderer : &PresentationRenderer,
) -> ReplContext {
  { session, registry, renderer, }
}

///|
async fn ReplContext::render(
  self : ReplContext,
  events : Array[PresentationEvent],
) -> Unit {
  self.renderer.render(events)
}
