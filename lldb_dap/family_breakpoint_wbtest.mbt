///|
fn family_reply(seq : Int, result : String) -> @dap_testkit.ScriptedInput {
  scripted_response(10000 + seq, seq, "evaluate", { "result": result })
}

///|
fn family_request_expressions(
  transport : @dap_testkit.ScriptedTransport,
) -> Array[String] {
  transport
  .sent_messages()
  .filter_map(message => {
    match message {
      {
        "command": "evaluate",
        "arguments": { "expression": String(expression), .. },
        ..
      } => Some(expression)
      _ => None
    }
  })
}

///|
async test "duplicate families keep separate handles and do not delete source or exact mappings" {
  @async.with_task_group(async fn(group) {
    let script = management_entry_script()
    script.append([
      management_reply(5, "setBreakpoints", [management_location(10, 4)]),
      management_reply(6, "setFunctionBreakpoints", [management_location(20, 4)]),
      family_reply(7, "Breakpoint 7: 2 locations."),
      family_reply(8, "details unavailable"),
      family_reply(9, "Breakpoint 8: 2 locations."),
      family_reply(10, "details unavailable"),
      family_reply(11, "1 breakpoints disabled."),
      family_reply(
        12, "1 breakpoints deleted; 0 breakpoint locations disabled.",
      ),
      family_reply(
        13, "1 breakpoints deleted; 0 breakpoint locations disabled.",
      ),
    ])
    let transport = @dap_testkit.ScriptedTransport::new(script)
    let backend = LldbDapBackend::{
      session: LldbDapSession::start_with_dispatcher_factory(
        group,
        () => @dap.DapDispatcher::from_transport(transport.as_transport()),
        preparation_timeout_ms=10000,
      ),
    }
    let session = @moondbg.DebugSession::new(
      "/tmp/program",
      backend,
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
      @moondbg.FunctionBreakpointRequest::current("identity"),
    )
    |> ignore
    session.add_function_breakpoint(
      @moondbg.FunctionBreakpointRequest::current("identity"),
    )
    |> ignore
    session.manage_breakpoint(3, @moondbg.DisableBreakpoint) |> ignore
    guard backend.session.execution is Some(execution) else {
      fail("stopped execution")
    }
    assert_true(
      execution.breakpoint_state.families.get(3)
      is Some({ id: LldbBreakpointId(7), enabled: false, }),
    )
    assert_true(
      execution.breakpoint_state.families.get(4)
      is Some({ id: LldbBreakpointId(8), enabled: true, }),
    )
    session.manage_breakpoint(3, @moondbg.DeleteBreakpoint) |> ignore
    assert_true(
      !session.manage_breakpoint(4, @moondbg.EnableBreakpoint).changed,
    )
    session.manage_breakpoint(4, @moondbg.DeleteBreakpoint) |> ignore
    assert_eq(
      execution.breakpoint_state.outcomes.get(1).map(outcome => outcome.dap_id),
      Some(Some(10)),
    )
    assert_eq(
      execution.breakpoint_state.outcomes.get(2).map(outcome => outcome.dap_id),
      Some(Some(20)),
    )
    assert_true(execution.breakpoint_state.families.is_empty())
    assert_eq(session.breakpoints().map(item => item.id), [1, 2])
    assert_eq(
      family_request_expressions(transport).filter(command => {
        command.has_prefix("breakpoint delete")
      }),
      ["breakpoint delete 7", "breakpoint delete 8"],
    )
    assert_eq(transport.remaining_inputs(), 0)
  })
}

///|
test "family parsing rejects unknown creation text and malformed bounded metadata" {
  for
    result in [
      "Breakpoint 7: surprise", "Breakpoint 0: 2 locations.", "Breakpoint 7: -1 locations.",
      "Breakpoint 7: no locations nonsense",
    ] {
    assert_true(LldbCreatedBreakpoint::parse(result) is None)
  }
  for
    result in [
      "8: locations = 2", "7: locations = 2junk", "7: locations = -1", "7: locations = 2147483648",
    ] {
    assert_eq(family_location_count(result, LldbBreakpointId(7)), None)
  }
  assert_eq(
    family_location_count(
      "7: locations = 8, resolved = 8\n",
      LldbBreakpointId(7),
    ),
    Some(8),
  )
  for
    result in [
      "8: locations = 1\n  8.1: address = 0x10", "7: locations = 1\n  8.1: address = 0x10",
      "7: locations = 1\n  7.1: address = 0x1x2", "7: locations = 1\n  7.1: address = 0x",
      "7: locations = 1\n  7.1: address = 0x10\n  7.2: address = 0x20",
    ] {
    assert_eq(family_addresses(result, 1, LldbBreakpointId(7)), None)
  }
}

///|
async test "family locations use bounded structured disassembly and preserve selected frame" {
  @async.with_task_group(async fn(group) {
    let script = management_entry_script()
    script.append([
      family_reply(5, "Breakpoint 7: 2 locations."),
      family_reply(6, "7: name = identity, locations = 2, resolved = 2"),
      family_reply(
        7, "7: locations = 2\n  7.1: where = app`identity at main.mbt:9, address = 0x10, resolved\n  7.2: where = app`identity at main.mbt:9, address = 0x20, resolved",
      ),
      scripted_response(10008, 8, "disassemble", {
        "instructions": [
          { "location": { "path": "/actual/main.mbt" }, "line": 9, "column": 3 },
        ],
      }),
      scripted_response(10009, 9, "disassemble", {
        "instructions": [
          {
            "location": { "path": "/actual/main.mbt" },
            "line": 10,
            "column": 4,
          },
        ],
      }),
      family_reply(10, "1 breakpoints disabled."),
      family_reply(11, "1 breakpoints enabled."),
      scripted_failed_response(10012, 12, "evaluate", "details unsupported"),
      family_reply(
        13, "1 breakpoints deleted; 0 breakpoint locations disabled.",
      ),
    ])
    let transport = @dap_testkit.ScriptedTransport::new(script)
    let backend = LldbDapBackend::{
      session: LldbDapSession::start_with_dispatcher_factory(
        group,
        () => @dap.DapDispatcher::from_transport(transport.as_transport()),
        preparation_timeout_ms=10000,
      ),
    }
    let session = @moondbg.DebugSession::new(
      "/tmp/program",
      backend,
      debug_context=@moondbg.DebugContext::new("example/main", []),
    )
    defer session.close()
    session.run() |> ignore
    let frame = session.selected_frame()
    let epoch = session.stop_epoch()
    assert_eq(frame.map(item => item.index()), Some(1))
    session.add_function_breakpoint(
      @moondbg.FunctionBreakpointRequest::current("identity"),
    )
    |> ignore
    let item = session.breakpoints()[0]
    assert_eq(item.location_count, Some(2))
    assert_eq(item.locations.map(location => location.source_path), [
      Some("/actual/main.mbt"),
      Some("/actual/main.mbt"),
    ])
    assert_eq(item.locations.map(location => location.instruction_reference), [
      Some("0x10"),
      Some("0x20"),
    ])
    session.manage_breakpoint(1, @moondbg.DisableBreakpoint) |> ignore
    let before = transport.sent_messages().length()
    assert_true(
      !session.manage_breakpoint(1, @moondbg.DisableBreakpoint).changed,
    )
    assert_eq(transport.sent_messages().length(), before)
    session.manage_breakpoint(1, @moondbg.EnableBreakpoint) |> ignore
    assert_true(session.function_breakpoints()[0].status() is @moondbg.Verified)
    assert_eq(session.breakpoints()[0].location_count, None)
    assert_eq(session.breakpoints()[0].locations.length(), 0)
    session.manage_breakpoint(1, @moondbg.DeleteBreakpoint) |> ignore
    assert_eq(session.selected_frame(), frame)
    assert_eq(session.stop_epoch(), epoch)
    assert_eq(
      family_request_expressions(transport)
      .filter(command => command.has_prefix("breakpoint set"))
      .length(),
      1,
    )
    for message in transport.sent_messages() {
      if message is { "command": "disassemble", "arguments": arguments, .. } {
        assert_true(
          arguments is { "instructionCount": 1, "resolveSymbols": false, .. },
        )
      }
    }
    assert_eq(transport.remaining_inputs(), 0)
  })
}

///|
async test "disabled never installed family creates on enable and zero location handle remains manageable" {
  @async.with_task_group(async fn(group) {
    let script = management_entry_script()
    script.append([
      family_reply(5, "Breakpoint 8: no locations (pending)."),
      family_reply(6, "8: locations = 0, resolved = 0"),
      family_reply(7, "1 breakpoints disabled."),
      family_reply(8, "1 breakpoints enabled."),
      family_reply(9, "error: details unavailable"),
      family_reply(
        10, "1 breakpoints deleted; 0 breakpoint locations disabled.",
      ),
    ])
    let transport = @dap_testkit.ScriptedTransport::new(script)
    let backend = LldbDapBackend::{
      session: LldbDapSession::start_with_dispatcher_factory(
        group,
        () => @dap.DapDispatcher::from_transport(transport.as_transport()),
        preparation_timeout_ms=10000,
      ),
    }
    let session = @moondbg.DebugSession::new(
      "/tmp/program",
      backend,
      debug_context=@moondbg.DebugContext::new("example/main", []),
    )
    defer session.close()
    session.add_function_breakpoint(
      @moondbg.FunctionBreakpointRequest::current("missing"),
    )
    |> ignore
    session.manage_breakpoint(1, @moondbg.DisableBreakpoint) |> ignore
    session.run() |> ignore
    assert_eq(family_request_expressions(transport).length(), 0)
    session.manage_breakpoint(1, @moondbg.EnableBreakpoint) |> ignore
    assert_eq(session.breakpoints()[0].location_count, Some(0))
    assert_true(
      session.function_breakpoints()[0].status() is @moondbg.Rejected(_),
    )
    session.manage_breakpoint(1, @moondbg.DisableBreakpoint) |> ignore
    session.manage_breakpoint(1, @moondbg.EnableBreakpoint) |> ignore
    assert_true(session.breakpoints()[0].enabled)
    assert_true(
      session.function_breakpoints()[0].status() is @moondbg.Rejected(_),
    )
    assert_eq(session.breakpoints()[0].location_count, None)
    session.manage_breakpoint(1, @moondbg.DeleteBreakpoint) |> ignore
    assert_eq(family_request_expressions(transport), [
      "breakpoint set --func-regex '^_M0FP27example4main7missing($|G|H)'", "breakpoint list --brief 8",
      "breakpoint disable 8", "breakpoint enable 8", "breakpoint list --brief 8",
      "breakpoint delete 8",
    ])
    assert_true(
      backend.session.execution
      is Some({ breakpoint_state: { families, .. }, .. }) &&
      families.is_empty(),
    )
    assert_eq(transport.remaining_inputs(), 0)
  })
}

///|
async test "family management unconfirmed replies recover execution without committing destructive intent" {
  for
    operation in [
      @moondbg.DeleteBreakpoint,
      @moondbg.DisableBreakpoint,
      @moondbg.EnableBreakpoint,
    ] {
    let seq = if operation is @moondbg.EnableBreakpoint { 8 } else { 7 }
    for
      failure in [
        family_reply(seq, "error: invalid breakpoint id"),
        family_reply(seq, "unknown success text"),
        scripted_failed_response(11000, seq, "evaluate", "failed"),
        @dap_testkit.ScriptedClosed,
      ] {
      @async.with_task_group(async fn(group) {
        let script = function_family_script()
        if operation is @moondbg.EnableBreakpoint {
          script.push(family_reply(7, "1 breakpoints disabled."))
        }
        script.append([
          failure,
          scripted_response(11001, seq + 1, "disconnect", {}),
        ])
        let transport = @dap_testkit.ScriptedTransport::new(script)
        let backend = LldbDapBackend::{
          session: LldbDapSession::start_with_dispatcher_factory(
            group,
            () => @dap.DapDispatcher::from_transport(transport.as_transport()),
            preparation_timeout_ms=10000,
          ),
        }
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
        if operation is @moondbg.EnableBreakpoint {
          session.manage_breakpoint(1, @moondbg.DisableBreakpoint) |> ignore
        }
        try {
          session.manage_breakpoint(1, operation) |> ignore
          fail("unconfirmed family operation")
        } catch {
          @moondbg.AdapterFailure(_) => ()
          error => raise error
        }
        assert_true(session.state() is @moondbg.Ready)
        assert_true(session.breakpoints()[0].enabled)
        assert_true(backend.session.execution is None)
        assert_true(transport.is_closed())
      })
    }
  }
}
