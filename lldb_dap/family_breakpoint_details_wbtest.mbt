///|
async test "family detail queries are capped and unsupported or incorrect details stay unknown" {
  for scenario in 0..<7 {
    @async.with_task_group(async fn(group) {
      let script = management_entry_script()
      script.push(family_reply(5, "Breakpoint 7: 2 locations."))
      let count = match scenario {
        0 => 8
        1 => 9
        2 => 2
        _ => 1
      }
      script.push(
        family_reply(
          6,
          if scenario == 2 {
            "unrecognized summary"
          } else {
            "7: locations = \{count}, resolved = \{count}"
          },
        ),
      )
      if scenario != 1 && scenario != 2 {
        let full = StringBuilder()
        full.write_string("7: locations = \{count}\n")
        for index in 1..<=count {
          full.write_string("  7.\{index}: address = 0x\{index}0, resolved\n")
        }
        script.push(
          family_reply(
            7,
            if scenario == 3 {
              "error: unavailable"
            } else {
              full.to_string()
            },
          ),
        )
        if scenario != 3 {
          for index in 1..<=count {
            script.push(
              if scenario == 4 {
                scripted_failed_response(
                  12000,
                  7 + index,
                  "disassemble",
                  "unsupported",
                )
              } else {
                scripted_response(12000 + index, 7 + index, "disassemble", {
                  "instructions": [
                    {
                      "address": if scenario == 5 {
                        "0x999"
                      } else {
                        "0x000\{index}0"
                      },
                      "location": { "path": "/actual/main.mbt" },
                      "line": 9,
                    },
                  ],
                })
              },
            )
          }
        }
      }
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
      session.add_function_breakpoint(
        @moondbg.FunctionBreakpointRequest::current("identity"),
      )
      |> ignore
      assert_true(session.state() is @moondbg.Stopped)
      let item = session.breakpoints()[0]
      assert_eq(item.location_count, Some(count))
      assert_eq(
        item.locations.length(),
        if scenario == 0 {
          8
        } else if scenario == 6 {
          1
        } else {
          0
        },
      )
      assert_eq(
        family_request_expressions(transport)
        .filter(command => command.has_prefix("breakpoint list --full"))
        .length(),
        if scenario == 1 || scenario == 2 {
          0
        } else {
          1
        },
      )
      assert_eq(transport.remaining_inputs(), 0)
    })
  }
}

///|
async test "family restart discards disabled old handles and creates a fresh handle on enable" {
  @async.with_task_group(async fn(group) {
    let first_script = function_family_script()
    first_script.append([
      family_reply(7, "1 breakpoints disabled."),
      scripted_response(13000, 8, "disconnect", {}),
    ])
    let second_script = management_entry_script()
    second_script.append([
      family_reply(5, "Breakpoint 27: 2 locations."),
      family_reply(6, "27: locations = 9"),
      family_reply(7, "1 breakpoints deleted; 0 breakpoint locations disabled."),
    ])
    let first = @dap_testkit.ScriptedTransport::new(first_script)
    let second = @dap_testkit.ScriptedTransport::new(second_script)
    let mut starts = 0
    let backend = LldbDapBackend::{
      session: LldbDapSession::start_with_dispatcher_factory(
        group,
        () => {
          let transport = if starts == 0 { first } else { second }
          starts += 1
          @dap.DapDispatcher::from_transport(transport.as_transport())
        },
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
    session.manage_breakpoint(1, @moondbg.DisableBreakpoint) |> ignore
    session.run() |> ignore
    assert_eq(family_request_expressions(second).length(), 0)
    session.manage_breakpoint(1, @moondbg.EnableBreakpoint) |> ignore
    assert_true(
      backend.session.execution
      is Some({ breakpoint_state: { families, .. }, .. }) &&
      families.get(1) is Some({ id: LldbBreakpointId(27), enabled: true, }),
    )
    session.manage_breakpoint(1, @moondbg.DeleteBreakpoint) |> ignore
    assert_true(
      family_request_expressions(second) is [_, _, "breakpoint delete 27"],
    )
    assert_true(first.is_closed())
    assert_eq(first.remaining_inputs(), 0)
    assert_eq(second.remaining_inputs(), 0)
  })
}

///|
async test "family creation or detail transport failure recovers after a source replacement" {
  for scenario in 0..<3 {
    @async.with_task_group(async fn(group) {
      let script = [
        scripted_response(14000, 1, "initialize", {
          "supportsConfigurationDoneRequest": true,
          "supportsFunctionBreakpoints": true,
        }),
        scripted_event(14001, "initialized", {}),
        management_reply(3, "setBreakpoints", [management_location(10, 4)]),
      ]
      match scenario {
        0 => script.push(family_reply(4, "Breakpoint 7: unknown detail"))
        1 =>
          script.append([
            family_reply(4, "Breakpoint 7: 2 locations."),
            @dap_testkit.ScriptedClosed,
          ])
        _ =>
          script.append([
            family_reply(4, "Breakpoint 7: 2 locations."),
            family_reply(5, "7: locations = 1"),
            family_reply(6, "7: locations = 1\n  7.1: address = 0x10"),
            @dap_testkit.ScriptedClosed,
          ])
      }
      let seq = match scenario {
        0 => 5
        1 => 6
        _ => 8
      }
      script.push(scripted_response(14002, seq, "disconnect", {}))
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
      session.add_source_breakpoint("/tmp/main.mbt", 4) |> ignore
      session.add_function_breakpoint(
        @moondbg.FunctionBreakpointRequest::current("identity"),
      )
      |> ignore
      try {
        session.run() |> ignore
        fail("family failure should recover")
      } catch {
        @moondbg.AdapterFailure(_) => ()
        error => raise error
      }
      assert_true(session.state() is @moondbg.Ready)
      assert_true(backend.session.execution is None)
      assert_true(transport.is_closed())
      assert_eq(session.breakpoints().map(item => item.id), [1, 2])
      assert_true(session.breakpoints().iter().all(item => item.enabled))
    })
  }
}
