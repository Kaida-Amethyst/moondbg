///|
priv struct LivePeer {
  process : @process.Process
  reader : @process.ReadFromProcess
  writer : @process.WriteToProcess
  pending : Array[Json]
  transcript : Array[Json]
  mut seq : Int
}

///|
async fn[G] LivePeer::start(
  group : @async.TaskGroup[G],
  extra_env? : Map[String, String] = {},
) -> LivePeer {
  let (_, moondbg) = require_toolchain()
  let (input, writer) = @process.write_to_process()
  errdefer writer.close()
  let (reader, output) = @process.read_from_process()
  errdefer reader.close()
  let process = @process.spawn(
    group,
    moondbg,
    ["--dap"],
    stdin=input,
    stdout=output,
    inherit_env=true,
    extra_env~,
  )
  { process, reader, writer, pending: [], transcript: [], seq: 0, }
}

///|
fn LivePeer::close(self : LivePeer) -> Unit {
  self.reader.close()
  self.writer.close()
  self.process.cancel()
}

///|
async fn LivePeer::send(
  self : LivePeer,
  command : String,
  arguments? : Json = {},
) -> Int {
  self.seq += 1
  self.writer.write(connection_request(self.seq, command, arguments~))
  self.seq
}

///|
async fn LivePeer::expect(self : LivePeer, predicate : (Json) -> Bool) -> Json {
  @async.with_timeout(20000, () => {
    for ;; {
      for index, message in self.pending {
        if predicate(message) {
          self.pending.remove(index) |> ignore
          return message
        }
      }
      guard @dap.read_frame(self.reader) is Some(text) else {
        fail("DAP closed early: \{Json(self.transcript).stringify()}")
      }
      let message = @json.parse(text)
      self.transcript.push(message)
      self.pending.push(message)
    }
  })
}

///|
async fn LivePeer::response(
  self : LivePeer,
  seq : Int,
  success? : Bool = true,
) -> Json {
  let message = self.expect(message => {
    message
    is { "type": String("response"), "request_seq": Number(number, ..), .. } &&
    number == seq.to_double()
  })
  assert_eq(
    message is { "success": True, .. },
    success,
    msg=message.stringify(),
  )
  match message {
    { "body": body, .. } => body
    _ => {}
  }
}

///|
async fn LivePeer::event(self : LivePeer, name : String) -> Json {
  let message = self.expect(message => {
    message is { "event": String(event), .. } && event == name
  })
  match message {
    { "body": body, .. } => body
    _ => {}
  }
}

///|
async fn LivePeer::initialize_launch(
  self : LivePeer,
  program : String,
  cwd : String,
) -> Int {
  let capabilities = self.response(
    self.send("initialize", arguments={
      "adapterID": "moondbg",
      "linesStartAt1": true,
      "columnsStartAt1": true,
      "pathFormat": "path",
    }),
  )
  assert_true(
    capabilities
    is {
      "supportsConfigurationDoneRequest": True,
      "supportsFunctionBreakpoints": False,
      ..
    },
  )
  let launch = self.send("launch", arguments={ "program": program, "cwd": cwd })
  self.event("initialized") |> ignore
  launch
}

///|
async fn LivePeer::disconnect(self : LivePeer) -> Unit {
  self.response(self.send("disconnect")) |> ignore
  assert_eq(@async.with_timeout(10000, () => self.process.wait()), 0)
}

///|
fn dap_thread_id(event : Json) -> Int raise {
  guard event is { "threadId": Number(id, ..), .. } else {
    fail(event.stringify())
  }
  id.to_int()
}

///|
async fn assert_target_gone(pid : Int) -> Unit {
  let (code, _, _) = @process.collect_output(
    "/bin/kill",
    ["-0", pid.to_string()],
    inherit_env=true,
  )
  assert_true(code != 0, msg="debuggee \{pid} was left alive")
}

///|
async test "live DAP configures source breakpoints displays a stack and continues to exit" {
  guard toolchain_acceptance_enabled() else { return }
  toolchain_acceptance_mutex.acquire()
  defer toolchain_acceptance_mutex.release()
  let (moon, _) = require_toolchain()
  let fixture = "\{@fs.realpath(".")}/testdata/dwarf_probe"
  let (code, _, stderr) = @process.collect_output(
    moon,
    ["run", "main", "--build-only", "--target", "native", "-g"],
    cwd=fixture,
    inherit_env=true,
  )
  assert_eq(code, 0, msg=stderr.text())
  let source = "\{fixture}/main/main.mbt"
  let line = unique_source_line(source, "let len = p.length()")
  let method_line = unique_source_line(
    source, "(self.x * self.x + self.y * self.y).sqrt()",
  )
  @async.with_task_group(group => {
    let peer = LivePeer::start(group)
    defer peer.close()
    let launch = peer.initialize_launch(
      "\{fixture}/_build/native/debug/build/main/main.exe",
      fixture,
    )
    let points = peer.response(
      peer.send("setBreakpoints", arguments={
        "source": { "path": source },
        "breakpoints": [{ "line": line }, { "line": method_line }],
      }),
    )
    assert_true(
      points
      is {
        "breakpoints": [{ "verified": True, .. }, { "verified": True, .. }],
        ..
      },
    )
    peer.response(peer.send("configurationDone")) |> ignore
    peer.response(launch) |> ignore
    let process = peer.event("process")
    guard process is { "systemProcessId": Number(pid, ..), .. } else {
      fail(process.stringify())
    }
    let stop = peer.event("stopped")
    assert_true(stop is { "reason": String("breakpoint"), .. })
    let thread = dap_thread_id(stop)
    let threads = peer.response(peer.send("threads"))
    assert_true(threads is { "threads": Array([_, ..]), .. })
    let stack = peer.response(
      peer.send("stackTrace", arguments={
        "threadId": thread,
        "startFrame": 0,
        "levels": 20,
      }),
    )
    guard stack
      is {
        "stackFrames": Array(
          [
            {
              "id": frame,
              "line": Number(actual_line, ..),
              "source": { "path": String(path), .. },
              ..
            },
            ..,
          ]
        ),
        ..
      } else {
      fail(stack.stringify())
    }
    assert_eq(actual_line.to_int(), line)
    assert_eq(@fs.realpath(path), @fs.realpath(source))
    assert_true(
      peer.response(peer.send("scopes", arguments={ "frameId": frame }))
      is { "scopes": [], .. },
    )
    peer.response(
      peer.send("evaluate", arguments={ "expression": "p" }),
      success=false,
    )
    |> ignore
    peer.response(peer.send("continue", arguments={ "threadId": thread }))
    |> ignore
    let stop = peer.event("stopped")
    let thread = dap_thread_id(stop)
    let stack = peer.response(
      peer.send("stackTrace", arguments={ "threadId": thread, "levels": 20 }),
    )
    assert_true(stack is { "stackFrames": Array([_, _, ..]), .. })
    let cleared = peer.response(
      peer.send("setBreakpoints", arguments={
        "source": { "path": source },
        "breakpoints": [],
      }),
    )
    assert_true(cleared is { "breakpoints": [], .. })
    peer.response(peer.send("continue", arguments={ "threadId": thread }))
    |> ignore
    assert_true(peer.event("exited") is { "exitCode": Number(0, ..), .. })
    peer.event("terminated") |> ignore
    let output = peer.transcript.fold(init="", (text, message) => {
      match message {
        {
          "event": String("output"),
          "body": { "output": String(output), .. },
          ..
        } => text + output
        _ => text
      }
    })
    assert_true(output.contains("Length of point: 5"), msg=output)
    assert_true(output.contains("Length of point q: 10"), msg=output)
    peer.disconnect()
    assert_target_gone(pid.to_int())
  })
}

///|
async test "live DAP streams output and handles disconnect or EOF while the target runs" {
  guard toolchain_acceptance_enabled() else { return }
  toolchain_acceptance_mutex.acquire()
  defer toolchain_acceptance_mutex.release()
  let repository = @fs.realpath(".")
  let temporary = @fs.tmpdir(prefix="moondbg-dap-running-")
  defer @fs.rmdir(temporary, recursive=true)
  let program = "\{temporary}/running.exe"
  let (code, _, stderr) = @process.collect_output(
    "cc",
    ["-g", "-O0", "\{repository}/testdata/dap_running/main.c", "-o", program],
    inherit_env=true,
  )
  assert_eq(code, 0, msg=stderr.text())
  for eof in [false, true] {
    @async.with_task_group(group => {
      let peer = LivePeer::start(group)
      defer peer.close()
      let launch = peer.initialize_launch(program, temporary)
      peer.response(peer.send("configurationDone")) |> ignore
      peer.response(launch) |> ignore
      let process = peer.event("process")
      guard process is { "systemProcessId": Number(pid, ..), .. } else {
        fail(process.stringify())
      }
      peer.expect(message => {
        message
        is {
          "event": String("output"),
          "body": { "output": String(text), .. },
          ..
        } &&
        text.contains("dap-running-ready")
      })
      |> ignore
      assert_false(
        peer.transcript.any(message => {
          message is { "event": String("stopped"), .. }
        }),
      )
      if eof {
        peer.writer.close()
        assert_eq(@async.with_timeout(10000, () => peer.process.wait()), 0)
      } else {
        peer.disconnect()
      }
      assert_target_gone(pid.to_int())
    })
  }
}

///|
async test "live DAP reports an invalid program without claiming a launch" {
  guard toolchain_acceptance_enabled() else { return }
  toolchain_acceptance_mutex.acquire()
  defer toolchain_acceptance_mutex.release()
  @async.with_task_group(group => {
    let peer = LivePeer::start(group)
    defer peer.close()
    peer.response(peer.send("initialize")) |> ignore
    peer.response(
      peer.send("launch", arguments={
        "program": "/not-a-real-moondbg-test.exe",
      }),
      success=false,
    )
    |> ignore
    peer.event("terminated") |> ignore
    assert_eq(@async.with_timeout(10000, () => peer.process.wait()), 0)
    assert_false(
      peer.transcript.any(message => {
        message is { "event": String("process"), .. }
      }),
    )
  })
}

///|
async test "live DAP reports a missing adapter and a rejected executable as failed launches" {
  guard toolchain_acceptance_enabled() else { return }
  toolchain_acceptance_mutex.acquire()
  defer toolchain_acceptance_mutex.release()
  let temporary = @fs.tmpdir(prefix="moondbg-dap-invalid-")
  defer @fs.rmdir(temporary, recursive=true)
  let invalid = "\{temporary}/not-an-object.exe"
  @fs.write_file(invalid, "not an executable object file\n")
  @fs.chmod(invalid, 0o700)
  for missing_adapter in [true, false] {
    @async.with_task_group(group => {
      let peer = LivePeer::start(
        group,
        extra_env=if missing_adapter {
          { "MOONDBG_LLDB_DAP": "/missing-moondbg-test-adapter" }
        } else {
          {}
        },
      )
      defer peer.close()
      peer.response(peer.send("initialize")) |> ignore
      peer.response(
        peer.send("launch", arguments={ "program": invalid }),
        success=false,
      )
      |> ignore
      peer.event("terminated") |> ignore
      // Invalid local settings may exit immediately; LLDB launch rejection
      // leaves a bounded window for the normal disconnect exchange.
      if !missing_adapter {
        peer.disconnect()
      } else {
        assert_eq(@async.with_timeout(10000, () => peer.process.wait()), 0)
      }
      assert_false(
        peer.transcript.any(message => {
          message is { "event": String("process"), .. }
        }),
      )
    })
  }
}
