///|
fn connection_request(
  seq : Int,
  command : String,
  arguments? : Json = {},
) -> String {
  let message : Json = {
    "seq": seq,
    "type": "request",
    "command": command,
    "arguments": arguments,
  }
  @dap.frame_message(message.stringify())
}

///|
async fn connection_transcript(
  executable : String,
  input : String,
  close_input? : Bool = true,
) -> (Int, String, String) {
  @async.with_timeout(8000, () => {
    @async.with_task_group(group => {
      let (child_stdin, writer) = @process.write_to_process()
      defer writer.close()
      let writing = group.spawn(() => {
        defer (if close_input { writer.close() })
        writer.write(input)
      })
      let (code, stdout, stderr) = @process.collect_output(
        executable,
        ["--dap"],
        stdin=child_stdin,
        inherit_env=true,
        extra_env={ "MOONDBG_LLDB_DAP": "/must-not-launch-lldb-in-this-test" },
      )
      writing.wait()
      (code, stdout.text(), stderr.text())
    })
  })
}

///|
async test "DAP adapter exits after termination even if the client never disconnects" {
  guard toolchain_acceptance_enabled() else { return }
  let (_, moon_home) = require_development_toolchain()
  let transcript = connection_request(1, "initialize") +
    connection_request(2, "launch", arguments={ "connectionTest": true }) +
    connection_request(3, "configurationDone")
  let (code, stdout, stderr) = connection_transcript(
    "\{moon_home}/bin/moondbg",
    transcript,
    close_input=false,
  )
  assert_eq(code, 0)
  assert_eq(stderr, "")
  assert_true(
    connection_messages(stdout)
    is [_, _, _, _, _, { "event": String("terminated"), .. }],
  )
}

///|
async fn connection_messages(text : String) -> Array[Json] {
  let reader = @io.MemoryReader(writer => writer.write(text))
  defer reader.close()
  let messages = []
  while @dap.read_frame(reader) is Some(body) {
    messages.push(@json.parse(body))
  }
  messages
}

///|
async test "real moondbg DAP handshake uses protocol-only stdout and exits cleanly" {
  guard toolchain_acceptance_enabled() else { return }
  let (_, moon_home) = require_development_toolchain()
  let transcript = connection_request(1, "initialize") +
    connection_request(2, "launch", arguments={ "connectionTest": true }) +
    connection_request(3, "setExceptionBreakpoints", arguments={ "filters": [] }) +
    connection_request(4, "configurationDone") +
    connection_request(5, "disconnect")
  let (code, stdout, stderr) = connection_transcript(
    "\{moon_home}/bin/moondbg",
    transcript,
  )
  assert_eq(code, 0)
  assert_eq(stderr, "")
  let messages = connection_messages(stdout)
  assert_eq(messages.length(), 8)
  assert_true(
    messages[0] is { "command": String("initialize"), "success": True, .. },
  )
  assert_true(messages[1] is { "event": String("initialized"), .. })
  assert_true(
    messages[4]
    is {
      "command": String("launch"),
      "request_seq": Number(2, ..),
      "success": True,
      ..
    },
  )
  assert_true(messages[5] is { "event": String("output"), .. })
  assert_true(messages[5].stringify().contains("DAP 连接验证成功"))
  assert_true(messages[6] is { "event": String("terminated"), .. })
  assert_true(
    messages[7] is { "command": String("disconnect"), "success": True, .. },
  )
  assert_false(stdout.contains("(moondbg)"))
  assert_false(stdout.contains("\"event\":\"exited\""))
}

///|
async test "real DAP frontend handles cancellation EOF and malformed input without a REPL" {
  guard toolchain_acceptance_enabled() else { return }
  let (_, moon_home) = require_development_toolchain()
  let executable = "\{moon_home}/bin/moondbg"
  let (code, stdout, stderr) = @process.collect_output(
    executable,
    ["--dap", "unexpected.exe"],
    inherit_env=true,
  )
  assert_eq(code, 2)
  assert_eq(stdout.text(), "")
  assert_true(
    stderr.text().contains("moondbg --dap accepts no additional arguments"),
  )
  let (code, stdout, stderr) = connection_transcript(executable, "")
  assert_eq(code, 0)
  assert_eq(stdout, "")
  assert_eq(stderr, "")
  let (code, stdout, stderr) = connection_transcript(
    executable,
    connection_request(1, "initialize") +
    connection_request(2, "launch", arguments={ "connectionTest": true }) +
    connection_request(3, "disconnect"),
  )
  assert_eq(code, 0)
  assert_eq(stderr, "")
  let messages = connection_messages(stdout)
  assert_true(
    messages
    is [
      _,
      _,
      { "command": String("launch"), "success": False, .. },
      { "command": String("disconnect"), "success": True, .. },
    ],
  )
  assert_false(stdout.contains("DAP 连接验证成功"))
  for
    input in [
      @dap.frame_message("not json"),
      "Content-Length: -1\r\n\r\n",
      "Content-Length: 100\r\n\r\n{}",
    ] {
    let (code, stdout, stderr) = connection_transcript(executable, input)
    assert_eq(code, 1)
    assert_eq(stdout, "")
    assert_true(stderr.contains("moondbg DAP:"))
  }
}
