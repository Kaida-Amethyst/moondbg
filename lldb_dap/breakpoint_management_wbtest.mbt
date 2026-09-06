///|
async test "P3 unsupported family mutation emits no requests or context changes" {
  @async.with_task_group(async fn(group) {
    let transport = @dap_testkit.ScriptedTransport::new(
      function_family_script(),
    )
    let lldb_session = LldbDapSession::start_with_dispatcher_factory(
      group,
      () => @dap.DapDispatcher::from_transport(transport.as_transport()),
      preparation_timeout_ms=10000,
    )
    let backend = LldbDapBackend::{ session: lldb_session, }
    let session = @moondbg.DebugSession::new(
      "/tmp/program",
      backend,
      debug_context=@moondbg.DebugContext::new("example/main", []),
    )
    defer session.close()
    session.add_function_breakpoint(
      @moondbg.FunctionBreakpointRequest::current("identity"),
    )
    |> ignore
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
      assert_eq(lldb_session.function_breakpoints.map(item => item.id), [1])
      assert_true(session.breakpoints()[0].enabled)
    }
    // A full configuration could combine source additions with a forbidden
    // family deletion. Validate the whole plan before even the source request.
    let candidate = @moondbg.DebugSession::new("/tmp/program", backend)
    candidate.add_source_breakpoint("/tmp/new.mbt", 4) |> ignore
    try {
      @moondbg.DebugBackend::synchronize_breakpoints(
        backend,
        candidate.breakpoint_configuration(),
      )
      |> ignore
      fail("mixed unsupported family mutation")
    } catch {
      @moondbg.BreakpointSyncError::BreakpointSyncRejected(_) => ()
      error => raise error
    }
    assert_eq(transport.sent_messages().length(), sent_before)
    assert_eq(lldb_session.source_breakpoints.length(), 0)
    assert_eq(lldb_session.function_breakpoints.map(item => item.id), [1])
  })
}

///|
fn management_entry_script() -> Array[@dap_testkit.ScriptedInput] {
  let script = stopped_execution_script(7000)
  script[0] = scripted_response(7000, 1, "initialize", {
    "supportsConfigurationDoneRequest": true,
    "supportsFunctionBreakpoints": true,
  })
  script[5] = scripted_response(
    7005,
    4,
    "stackTrace",
    scripted_stack_body_with_runtime(40, 3),
  )
  script
}

///|
fn management_reply(
  request_seq : Int,
  command : String,
  results : Array[Json],
) -> @dap_testkit.ScriptedInput {
  scripted_response(7100 + request_seq, request_seq, command, {
    "breakpoints": results,
  })
}

///|
fn management_location(id : Int, line : Int) -> Json {
  {
    "verified": true,
    "id": id,
    "source": { "path": "/tmp/actual.mbt" },
    "line": line,
    "column": 2,
    "instructionReference": "0x1000",
  }
}

///|
async test "source management replaces duplicate groups and clears the final enabled location" {
  @async.with_task_group(async fn(group) {
    let script = management_entry_script()
    script.append([
      management_reply(5, "setBreakpoints", [management_location(10, 5)]),
      management_reply(6, "setBreakpoints", [
        management_location(10, 5),
        management_location(10, 5),
      ]),
      management_reply(7, "setBreakpoints", [management_location(10, 5)]),
      management_reply(8, "setBreakpoints", []),
      management_reply(9, "setBreakpoints", [
        { "verified": false, "id": 11, "message": "no code" },
      ]),
      management_reply(10, "setBreakpoints", []),
      management_reply(11, "setBreakpoints", [management_location(90, 10)]),
      management_reply(12, "setBreakpoints", []),
      management_reply(13, "setBreakpoints", [management_location(91, 10)]),
    ])
    let transport = @dap_testkit.ScriptedTransport::new(script)
    let lldb_session = LldbDapSession::start_with_dispatcher_factory(
      group,
      () => @dap.DapDispatcher::from_transport(transport.as_transport()),
      preparation_timeout_ms=10000,
    )
    let session = @moondbg.DebugSession::new("/tmp/program", LldbDapBackend::{
      session: lldb_session,
    })
    defer session.close()
    session.run() |> ignore
    let frame = session.selected_frame()
    let epoch = session.stop_epoch()
    assert_eq(frame.map(item => item.index()), Some(1))
    let first = session.add_source_breakpoint("/tmp/main.mbt", 4)
    assert_eq(first.actual_line(), Some(5))
    assert_eq(first.locations()[0].source_path, Some("/tmp/actual.mbt"))
    session.add_source_breakpoint("/tmp/main.mbt", 4) |> ignore
    session.manage_breakpoint(1, @moondbg.DisableBreakpoint) |> ignore
    guard lldb_session.execution is Some(execution) else {
      fail("stopped execution")
    }
    assert_true(execution.breakpoint_state.outcomes.get(1) is None)
    assert_eq(
      execution.breakpoint_state.outcomes.get(2).map(item => item.dap_id),
      Some(Some(10)),
    )
    session.manage_breakpoint(2, @moondbg.DeleteBreakpoint) |> ignore
    let rejected = session.manage_breakpoint(1, @moondbg.EnableBreakpoint)
    assert_true(rejected.breakpoint.enabled)
    assert_true(
      rejected.breakpoint.installation
      is @moondbg.CurrentInstallation(@moondbg.Rejected("no code")),
    )
    session.manage_breakpoint(1, @moondbg.DeleteBreakpoint) |> ignore
    let added = session.add_source_breakpoint("/tmp/main.mbt", 9)
    assert_eq(added.id(), 3)
    session.manage_breakpoint(3, @moondbg.DisableBreakpoint) |> ignore
    let enabled = session.manage_breakpoint(3, @moondbg.EnableBreakpoint)
    assert_eq(enabled.breakpoint.locations[0].line, Some(10))
    assert_eq(
      execution.breakpoint_state.outcomes.get(3).map(item => item.dap_id),
      Some(Some(91)),
    )
    assert_eq(session.selected_frame(), frame)
    assert_eq(session.stop_epoch(), epoch)
    assert_eq(transport.remaining_inputs(), 0)
    let sets = transport
      .sent_messages()
      .filter_map(message => {
        match message {
          {
            "command": String("setBreakpoints"),
            "arguments": { "breakpoints": Array(items), .. },
            ..
          } => Some(items.length())
          _ => None
        }
      })
    assert_eq(sets, [1, 2, 1, 0, 1, 0, 1, 0, 1])
  })
}

///|
async test "exact management clears shared targets without disturbing source replacements" {
  @async.with_task_group(async fn(group) {
    let script = management_entry_script()
    script.append([
      management_reply(5, "setBreakpoints", [management_location(10, 4)]),
      management_reply(6, "setFunctionBreakpoints", [
        management_location(20, 15),
      ]),
      management_reply(7, "setFunctionBreakpoints", [
        management_location(20, 15),
        management_location(20, 15),
      ]),
      management_reply(8, "setFunctionBreakpoints", [
        management_location(20, 15),
      ]),
      management_reply(9, "setFunctionBreakpoints", []),
      management_reply(10, "setFunctionBreakpoints", [
        management_location(21, 16),
      ]),
    ])
    let transport = @dap_testkit.ScriptedTransport::new(script)
    let lldb_session = LldbDapSession::start_with_dispatcher_factory(
      group,
      () => @dap.DapDispatcher::from_transport(transport.as_transport()),
      preparation_timeout_ms=10000,
    )
    let session = @moondbg.DebugSession::new(
      "/tmp/program",
      LldbDapBackend::{ session: lldb_session, },
      debug_context=@moondbg.DebugContext::new("example/main", []),
    )
    defer session.close()
    session.run() |> ignore
    session.add_source_breakpoint("/tmp/main.mbt", 4) |> ignore
    session.add_function_breakpoint(
      @moondbg.FunctionBreakpointRequest::current("main"),
    )
    |> ignore
    session.add_function_breakpoint(
      @moondbg.FunctionBreakpointRequest::current("main"),
    )
    |> ignore
    session.manage_breakpoint(2, @moondbg.DisableBreakpoint) |> ignore
    session.manage_breakpoint(3, @moondbg.DeleteBreakpoint) |> ignore
    let enabled = session.manage_breakpoint(2, @moondbg.EnableBreakpoint)
    assert_eq(
      enabled.breakpoint.locations[0].source_path,
      Some("/tmp/actual.mbt"),
    )
    assert_eq(enabled.breakpoint.locations[0].line, Some(16))
    guard lldb_session.execution is Some(execution) else {
      fail("stopped execution")
    }
    assert_eq(
      execution.breakpoint_state.outcomes.get(1).map(item => item.dap_id),
      Some(Some(10)),
    )
    assert_eq(
      execution.breakpoint_state.outcomes.get(2).map(item => item.dap_id),
      Some(Some(21)),
    )
    assert_true(execution.breakpoint_state.outcomes.get(3) is None)
    assert_eq(transport.sent_messages().filter_map(sent_command), [
      "initialize", "launch", "configurationDone", "stackTrace", "setBreakpoints",
      "setFunctionBreakpoints", "setFunctionBreakpoints", "setFunctionBreakpoints",
      "setFunctionBreakpoints", "setFunctionBreakpoints",
    ])
    assert_eq(transport.remaining_inputs(), 0)
  })
}

///|
test "replacement parsing rejects malformed records before updating any result" {
  let invalid_bodies : Array[Json] = [
    {},
    { "breakpoints": [] },
    { "breakpoints": [{ "verified": true }, { "verified": true }] },
    { "breakpoints": [{}] },
    { "breakpoints": [{ "verified": "true" }] },
    { "breakpoints": [{ "verified": true, "line": 1.5 }] },
    { "breakpoints": [{ "verified": true, "id": "4" }] },
    { "breakpoints": [{ "verified": true, "source": { "path": 1 } }] },
    { "breakpoints": [{ "verified": true, "column": 0 }] },
    { "breakpoints": [{ "verified": false, "message": 1 }] },
  ]
  for body in invalid_bodies {
    let state = ExecutionBreakpointState::new()
    let breakpoint = LogicalSourceBreakpoint::new(1, "/tmp/main.mbt", 4)
    state.verify(1, Some(4), Some(99))
    try {
      apply_breakpoint_response(
        state,
        [breakpoint],
        test_response(1, 1, "setBreakpoints", body),
      )
      fail("malformed response")
    } catch {
      @moondbg.BreakpointSyncError::BreakpointSyncUncertain(_) => ()
      error => raise error
    }
    assert_eq(state.outcomes.get(1).map(item => item.dap_id), Some(Some(99)))
  }
}

///|
fn management_configured_launch_script(
  command : String,
  id : Int,
) -> Array[@dap_testkit.ScriptedInput] {
  [
    scripted_response(8000, 1, "initialize", {
      "supportsConfigurationDoneRequest": true,
      "supportsFunctionBreakpoints": true,
    }),
    scripted_event(8001, "initialized", {}),
    management_reply(3, command, [management_location(id, 4)]),
    scripted_response(8003, 4, "configurationDone", {}),
    scripted_response(8004, 2, "launch", {}),
    scripted_event(8005, "stopped", { "reason": "breakpoint", "threadId": 1 }),
    scripted_response(
      8006,
      5,
      "stackTrace",
      scripted_stack_body_with_runtime(40, 4),
    ),
  ]
}

///|
async test "empty source and exact removal failures recover without committing deletion" {
  for command in ["setBreakpoints", "setFunctionBreakpoints"] {
    let failures = [
      scripted_response(9000, 6, command, {}),
      scripted_failed_response(9001, 6, command, "adapter rejected replacement"),
      @dap_testkit.ScriptedClosed,
    ]
    for failure in failures {
      @async.with_task_group(async fn(group) {
        let script = management_entry_script()
        script.append([
          management_reply(5, command, [management_location(10, 4)]),
          failure,
          scripted_response(9002, 7, "disconnect", {}),
        ])
        let failed_transport = @dap_testkit.ScriptedTransport::new(script)
        let recovered_transport = @dap_testkit.ScriptedTransport::new(
          management_configured_launch_script(command, 77),
        )
        let mut starts = 0
        let lldb_session = LldbDapSession::start_with_dispatcher_factory(
          group,
          () => {
            let transport = if starts == 0 {
              failed_transport
            } else {
              recovered_transport
            }
            starts += 1
            @dap.DapDispatcher::from_transport(transport.as_transport())
          },
          preparation_timeout_ms=10000,
        )
        let session = @moondbg.DebugSession::new(
          "/tmp/program",
          LldbDapBackend::{ session: lldb_session, },
          debug_context=@moondbg.DebugContext::new("example/main", []),
        )
        defer session.close()
        session.run() |> ignore
        if command == "setBreakpoints" {
          session.add_source_breakpoint("/tmp/main.mbt", 4) |> ignore
        } else {
          session.add_function_breakpoint(
            @moondbg.FunctionBreakpointRequest::current("main"),
          )
          |> ignore
        }
        try {
          session.manage_breakpoint(1, @moondbg.DeleteBreakpoint) |> ignore
          fail("cannot confirm deletion")
        } catch {
          @moondbg.AdapterFailure(message) =>
            assert_true(message.contains("current execution was discarded"))
          error => raise error
        }
        assert_true(session.state() is @moondbg.Ready)
        assert_true(lldb_session.execution is None)
        assert_true(failed_transport.is_closed())
        assert_eq(session.breakpoints().map(item => item.id), [1])
        assert_true(session.breakpoints()[0].enabled)
        session.run() |> ignore
        assert_true(session.state() is @moondbg.Stopped)
        guard lldb_session.execution is Some(execution) else {
          fail("restarted execution")
        }
        assert_eq(
          execution.breakpoint_state.outcomes.get(1).map(item => item.dap_id),
          Some(Some(77)),
        )
      })
    }
  }
}

///|
async test "malformed initial breakpoint response closes the launch and permits replay" {
  @async.with_task_group(async fn(group) {
    let failed_transport = @dap_testkit.ScriptedTransport::new([
      scripted_response(9100, 1, "initialize", {
        "supportsConfigurationDoneRequest": true,
      }),
      scripted_event(9101, "initialized", {}),
      scripted_response(9102, 3, "setBreakpoints", { "breakpoints": [{}] }),
      scripted_response(9103, 4, "disconnect", {}),
    ])
    let recovered_transport = @dap_testkit.ScriptedTransport::new(
      management_configured_launch_script("setBreakpoints", 88),
    )
    let mut starts = 0
    let lldb_session = LldbDapSession::start_with_dispatcher_factory(
      group,
      () => {
        let transport = if starts == 0 {
          failed_transport
        } else {
          recovered_transport
        }
        starts += 1
        @dap.DapDispatcher::from_transport(transport.as_transport())
      },
      preparation_timeout_ms=10000,
    )
    let session = @moondbg.DebugSession::new("/tmp/program", LldbDapBackend::{
      session: lldb_session,
    })
    defer session.close()
    session.add_source_breakpoint("/tmp/main.mbt", 4) |> ignore
    try {
      session.run() |> ignore
      fail("invalid launch breakpoint response")
    } catch {
      @moondbg.AdapterFailure(_) => ()
      error => raise error
    }
    assert_true(session.state() is @moondbg.Ready)
    assert_true(lldb_session.execution is None)
    assert_true(failed_transport.is_closed())
    session.run() |> ignore
    assert_true(session.state() is @moondbg.Stopped)
    assert_eq(session.breakpoints().map(item => item.id), [1])
  })
}

///|
async test "exact rejected enable keeps intent and a disabled target is absent on replay" {
  @async.with_task_group(async fn(group) {
    let first_script = management_entry_script()
    first_script.append([
      management_reply(5, "setFunctionBreakpoints", [
        management_location(20, 15),
      ]),
      management_reply(6, "setFunctionBreakpoints", []),
      management_reply(7, "setFunctionBreakpoints", [
        { "verified": false, "id": 21, "message": "no exact location" },
      ]),
      management_reply(8, "setFunctionBreakpoints", []),
      scripted_response(9500, 9, "disconnect", {}),
    ])
    let first = @dap_testkit.ScriptedTransport::new(first_script)
    let second = @dap_testkit.ScriptedTransport::new(management_entry_script())
    let mut starts = 0
    let lldb_session = LldbDapSession::start_with_dispatcher_factory(
      group,
      () => {
        let transport = if starts == 0 { first } else { second }
        starts += 1
        @dap.DapDispatcher::from_transport(transport.as_transport())
      },
      preparation_timeout_ms=10000,
    )
    let session = @moondbg.DebugSession::new(
      "/tmp/program",
      LldbDapBackend::{ session: lldb_session, },
      debug_context=@moondbg.DebugContext::new("example/main", []),
    )
    defer session.close()
    session.run() |> ignore
    session.add_function_breakpoint(
      @moondbg.FunctionBreakpointRequest::current("main"),
    )
    |> ignore
    session.manage_breakpoint(1, @moondbg.DisableBreakpoint) |> ignore
    let rejected = session.manage_breakpoint(1, @moondbg.EnableBreakpoint)
    assert_true(rejected.breakpoint.enabled)
    assert_true(
      rejected.breakpoint.installation
      is @moondbg.CurrentInstallation(@moondbg.Rejected("no exact location")),
    )
    assert_true(session.state() is @moondbg.Stopped)
    session.manage_breakpoint(1, @moondbg.DisableBreakpoint) |> ignore
    session.run() |> ignore
    assert_eq(session.breakpoints().map(item => item.id), [1])
    assert_false(session.breakpoints()[0].enabled)
    assert_eq(lldb_session.function_breakpoints.length(), 0)
    assert_eq(second.sent_messages().filter_map(sent_command), [
      "initialize", "launch", "configurationDone", "stackTrace",
    ])
    assert_true(first.is_closed())
    assert_eq(first.remaining_inputs(), 0)
    assert_eq(second.remaining_inputs(), 0)
  })
}
