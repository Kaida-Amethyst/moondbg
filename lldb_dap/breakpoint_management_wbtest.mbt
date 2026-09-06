///|
async test "P2 unsupported destructive synchronization emits no requests or context changes" {
  @async.with_task_group(async fn(group) {
    let transport = @dap_testkit.ScriptedTransport::new(lifecycle_script())
    let lldb_session = LldbDapSession::start_with_dispatcher_factory(
      group,
      () => @dap.DapDispatcher::from_transport(transport.as_transport()),
      preparation_timeout_ms=10000,
    )
    let backend = LldbDapBackend::{ session: lldb_session, }
    let session = @moondbg.DebugSession::new("/tmp/program", backend)
    defer session.close()
    session.add_source_breakpoint("/tmp/main.mbt", 4) |> ignore
    session.run() |> ignore
    let sent_before = transport.sent_messages().length()
    let frame_before = session.selected_frame()
    let epoch_before = session.stop_epoch()
    for operation in [@moondbg.DeleteBreakpoint, @moondbg.DisableBreakpoint] {
      try {
        session.manage_breakpoint(1, operation) |> ignore
        fail("unsupported management should reject")
      } catch {
        @moondbg.BreakpointManagementRejected(_) => ()
        error => raise error
      }
      assert_eq(transport.sent_messages().length(), sent_before)
      assert_eq(session.selected_frame(), frame_before)
      assert_eq(session.stop_epoch(), epoch_before)
      assert_true(session.state() is @moondbg.Stopped)
      assert_eq(lldb_session.source_breakpoints.map(item => item.id), [1])
      assert_true(session.breakpoints()[0].enabled)
    }
  })
}
