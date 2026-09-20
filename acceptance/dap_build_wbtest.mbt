///|
async fn LivePeer::initialize_package(
  self : LivePeer,
  directory : String,
) -> Int {
  self.response(self.send("initialize", arguments={ "adapterID": "moondbg" }))
  |> ignore
  self.send("launch", arguments={ "package": directory })
}

///|
async test "DAP package launches rebuild edited code and never run stale artifacts on failure" {
  guard toolchain_acceptance_enabled() else { return }
  toolchain_acceptance_mutex.acquire()
  defer toolchain_acceptance_mutex.release()
  let directory = create_launch_project()
  defer @fs.rmdir(directory, recursive=true)
  let source = "\{directory}/src/app/main.mbt"
  for argument in [41, 99] {
    @fs.write_file(
      source,
      "fn main {\n  let result = @util.increment(\{argument})\n  println(result)\n}\n",
    )
    @async.with_task_group(group => {
      let peer = LivePeer::start(group)
      defer peer.close()
      let launch = peer.initialize_package("\{directory}/src/app")
      peer.event("initialized") |> ignore
      peer.response(
        peer.send("setBreakpoints", arguments={
          "source": { "path": source },
          "breakpoints": [{ "line": 3 }],
        }),
      )
      |> ignore
      peer.response(peer.send("configurationDone")) |> ignore
      peer.response(launch) |> ignore
      let thread = dap_thread_id(peer.event("stopped"))
      let frame = peer.top_frame(thread)
      assert_frame_location(frame, source, 3)
      guard frame is { "id": id, .. } else { fail(frame.stringify()) }
      let value = peer.evaluate_path(id, "result")
      assert_true(
        value is { "result": String(actual), .. } &&
        actual == (argument + 1).to_string(),
        msg=value.stringify(),
      )
      assert_true(
        peer.transcript.any(message => {
          message
          is {
            "event": String("output"),
            "body": { "output": String(text), .. },
            ..
          } &&
          text.contains("Build succeeded")
        }),
      )
      peer.response(peer.send("continue", arguments={ "threadId": thread }))
      |> ignore
      peer.event("exited") |> ignore
      peer.disconnect()
    })
  }
  @fs.write_file(source, "fn main { println(missing_build_value) }")
  @async.with_task_group(group => {
    let peer = LivePeer::start(group, extra_env={
      "MOONDBG_LLDB_DAP": "/must-not-start-on-build-failure",
    })
    defer peer.close()
    let launch = peer.initialize_package("\{directory}/src/app")
    peer.response(launch, success=false) |> ignore
    peer.event("terminated") |> ignore
    assert_eq(@async.with_timeout(10000, () => peer.process.wait()), 0)
    assert_false(
      peer.transcript.any(message => {
        message
        is { "event": String("initialized" | "process" | "stopped"), .. }
      }),
    )
    let output = peer.transcript.fold(init="", (acc, message) => {
      match message {
        {
          "event": String("output"),
          "body": { "output": String(text), .. },
          ..
        } => acc + text
        _ => acc
      }
    })
    assert_true(output.contains("missing_build_value"), msg=output)
    assert_false(output.contains("must-not-start-on-build-failure"), msg=output)
  })
}

///|
async test "DAP stop or EOF during build kills the worker moon and its child before returning" {
  guard toolchain_acceptance_enabled() else { return }
  toolchain_acceptance_mutex.acquire()
  defer toolchain_acceptance_mutex.release()
  let (_, _) = require_toolchain()
  let directory = create_launch_project()
  defer @fs.rmdir(directory, recursive=true)
  let toolchain = "\{directory}/toolchain"
  @fs.mkdir("\{toolchain}/bin", recursive=true)
  let (status, _, error) = @process.collect_output(
    "cc",
    ["testdata/build_cancel/main.c", "-o", "\{toolchain}/bin/moon"],
    inherit_env=true,
  )
  assert_eq(status, 0, msg=error.text())
  guard @env.get_env_var("MOON_HOME") is Some(home) else { fail("MOON_HOME") }
  @fs.symlink(target="\{home}/bin/moonc", "\{toolchain}/bin/moonc")
  for eof in [false, true] {
    @async.with_task_group(group => {
      let peer = LivePeer::start(group, extra_env={
        "MOON_HOME": toolchain,
        "MOONDBG_LLDB_DAP": "/must-not-start-during-build",
      })
      defer peer.close()
      let launch = peer.initialize_package("\{directory}/src/app")
      let ready = peer.expect(message => {
        message
        is {
          "event": String("output"),
          "body": { "output": String(text), .. },
          ..
        } &&
        text.contains("build-cancel-ready")
      })
      guard ready is { "body": { "output": String(text), .. }, .. } else {
        fail("output")
      }
      let parts = text.trim().split(" ").to_array()
      guard parts is ["build-cancel-ready", worker, moon, child, pgid] else {
        fail(text)
      }
      assert_eq(worker, pgid)
      if eof {
        peer.writer.close()
      } else {
        let disconnect = peer.send("disconnect")
        peer.response(launch, success=false) |> ignore
        peer.response(disconnect) |> ignore
        peer.event("terminated") |> ignore
      }
      assert_eq(@async.with_timeout(10000, () => peer.process.wait()), 0)
      for pid in [worker, moon, child] {
        // Orphaned descendants may need a short interval for OS reaping.
        @async.with_timeout(3000, () => {
          for ;; {
            let (code, _, _) = @process.collect_output(
              "/bin/kill",
              ["-0", pid.to_owned()],
              inherit_env=true,
            )
            if code != 0 {
              break
            }
            @async.sleep(20)
          }
        })
      }
      assert_false(
        peer.transcript.any(message => {
          message is { "event": String("initialized" | "process"), .. }
        }),
      )
    })
  }
}
