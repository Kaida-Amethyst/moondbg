///|
fn test_stack_snapshot_from_stop(
  thread : @debugger.ThreadSelection,
  stop : @debugger.StopSnapshot,
) -> @debugger.StackSnapshot raise @debugger.StackSnapshotError {
  @debugger.StackSnapshot::new(
    thread,
    [
      @debugger.StackFrameSnapshot::new(
        0,
        stop.function_name(),
        stop.function_name(),
        None,
        stop.source_path(),
        stop.line(),
        stop.column(),
        @debugger.MoonBitUserFrame,
      ),
    ],
    0,
    1,
    Some(1),
    true,
  )
}
