///|
fn test_stack_snapshot_from_stop(
  thread : @moondbg.ThreadSelection,
  stop : @moondbg.StopSnapshot,
) -> @moondbg.StackSnapshot raise @moondbg.StackSnapshotError {
  @moondbg.StackSnapshot::new(
    thread,
    [
      @moondbg.StackFrameSnapshot::new(
        0,
        stop.function_name(),
        stop.function_name(),
        None,
        stop.source_path(),
        stop.line(),
        stop.column(),
        @moondbg.MoonBitUserFrame,
      ),
    ],
    0,
    1,
    Some(1),
    true,
  )
}
