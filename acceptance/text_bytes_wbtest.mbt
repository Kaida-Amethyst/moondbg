///|
async test "REPL reads text bytes and exact ranges without executing user code" {
  guard toolchain_acceptance_enabled() else { return }
  toolchain_acceptance_mutex.acquire()
  defer toolchain_acceptance_mutex.release()
  let (_, moondbg) = require_toolchain()
  let fixture = "\{@fs.realpath(".")}/testdata/dwarf_probe"
  let process = @pty_testkit.PtyProcess::spawn_debug(
    moondbg,
    fixture,
    package_name="text_bytes",
  )
  defer process.close()
  breakpoint_expect(process, "(moondbg) ", "startup")
  breakpoint_command(process, "b inspect_values", ["Breakpoint 1 pending"])
  breakpoint_command(process, "run", ["Stopped (breakpoint)"])
  for
    (command, expected) in [
      ("p values.text", "\"你好🙂\\nA\\u0000B\" (length = 8 UTF-16 units)"),
      ("p values.bytes", "b\"\\x41\\x00\\xff\" (length = 3 bytes)"),
      ("p values.empty_text", "\"\" (length = 0 UTF-16 units)"),
      ("p values.empty_bytes", "b\"\" (length = 0 bytes)"),
      (
        "p values.long_text", "length = 280 UTF-16 units; showing [0:127], truncated",
      ),
      ("p values.long_bytes", "length = 150 bytes; showing [0:32], truncated"),
      ("p values.text[2:4]", "\"🙂\" (length = 8 UTF-16 units; showing [2:4]"),
      ("p values.text[2:3]", "\"\\ud83d\""),
      ("p values.text[8:8]", "\"\" (length = 8 UTF-16 units; showing [8:8]"),
      ("p values.bytes[1:3]", "b\"\\x00\\xff\""),
      ("p values.long_text[279:280]", "\"尾\""),
      ("p values.long_bytes[148:150]", "b\"\\xff\\xff\""),
      ("p values.text[0:9]", "outside length 8"),
      ("p values[0:1]", "Ranges require String or Bytes"),
      ("p values.result", "Result[Point, String]"),
    ] {
    breakpoint_command(process, command, [expected])
  }
  breakpoint_command(process, "p values", ["Values", "你好🙂\\nA\\u0000B"])
  breakpoint_command(process, "next", ["Stopped (step over)"])
  breakpoint_command(process, "locals", ["marker", "你好🙂\\nA\\u0000B"])
  breakpoint_command(process, "p marker", [
    "\"你好🙂\\nA\\u0000B\" (length = 8 UTF-16 units)",
  ])
  breakpoint_quit(process)
}

///|
async test "DAP shares text summaries range evaluation paging and stale reference checks" {
  guard toolchain_acceptance_enabled() else { return }
  toolchain_acceptance_mutex.acquire()
  defer toolchain_acceptance_mutex.release()
  let (fixture, program, source) = build_dap_control_fixture("text_bytes")
  let first = unique_source_line(source, "let marker = values.text")
  let second = unique_source_line(source, "println(marker)")
  @async.with_task_group(group => {
    let peer = LivePeer::start(group)
    defer peer.close()
    let launch = peer.initialize_launch(program, fixture)
    peer.response(
      peer.send("setBreakpoints", arguments={
        "source": { "path": source },
        "breakpoints": [{ "line": first }, { "line": second }],
      }),
    )
    |> ignore
    peer.response(peer.send("configurationDone")) |> ignore
    peer.response(launch) |> ignore
    let thread = dap_thread_id(peer.event("stopped"))
    let frame = peer.top_frame(thread)
    guard frame is { "id": id, .. } else { fail(frame.stringify()) }
    let values = named_variable(peer.frame_locals(id), "values")
    let fields = peer.children_of(values)
    assert_true(
      named_variable(fields, "text")
      is {
        "type": String("String"),
        "value": String("\"你好🙂\\nA\\u0000B\" (length = 8 UTF-16 units)"),
        ..
      },
      msg=fields.stringify(),
    )
    assert_true(
      named_variable(fields, "empty_text")
      is {
        "variablesReference": Number(0, ..),
        "value": String("\"\" (length = 0 UTF-16 units)"),
        ..
      },
    )
    assert_true(
      named_variable(fields, "empty_bytes")
      is {
        "variablesReference": Number(0, ..),
        "value": String("b\"\" (length = 0 bytes)"),
        ..
      },
    )
    let long_text = named_variable(fields, "long_text")
    assert_true(long_text is { "indexedVariables": Number(3, ..), .. })
    let chunks = peer.children_of(long_text)
    let first_chunk = named_variable(chunks, "[0:127]")
    assert_true(
      first_chunk
      is {
        "evaluateName": String("values.long_text[0:127]"),
        "value": String(value),
        ..
      } &&
      !value.contains("\\ud83d"),
      msg=first_chunk.stringify(),
    )
    assert_true(
      named_variable(chunks, "[127:256]") is { "value": String(value), .. } &&
      value.has_prefix("\"🙂"),
    )
    let last = named_variable(chunks, "[256:280]")
    assert_true(last is { "value": String(value), .. } && value.contains("尾"))
    let bytes = named_variable(fields, "long_bytes")
    let page = peer.response(
      peer.send("variables", arguments={
        "variablesReference": variable_reference(bytes),
        "filter": "indexed",
        "start": 4,
        "count": 1,
      }),
    )
    named_variable(page, "[128:150]") |> ignore
    for context in ["watch", "hover", "repl"] {
      let result = peer.evaluate_path(id, "values.text[2:4]", context~)
      assert_true(
        result
        is { "result": String(value), "variablesReference": Number(0, ..), .. } &&
        value.has_prefix("\"🙂\""),
        msg=result.stringify(),
      )
    }
    let result = named_variable(fields, "result")
    assert_true(
      result
      is { "type": String("Result[Point, String]"), "value": String("Err"), .. },
      msg=result.stringify(),
    )
    assert_true(
      named_variable(peer.children_of(result), ".0")
      is { "type": String("String"), "value": String(value), .. } &&
      value.contains("错误\\nmessage"),
    )
    for
      invalid in [
        "values.text[0:9]", "values.bytes[0:4]", "values[0:1]", "values.text[-1:2]",
      ] {
      peer.evaluate_path(id, invalid, success=false) |> ignore
    }
    peer.response(peer.send("continue", arguments={ "threadId": thread }))
    |> ignore
    peer.event("stopped") |> ignore
    peer.response(
      peer.send("variables", arguments={
        "variablesReference": variable_reference(long_text),
      }),
      success=false,
    )
    |> ignore
    peer.disconnect()
  })
}
