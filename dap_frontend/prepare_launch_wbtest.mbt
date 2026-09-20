///|
async test "build preparation rejects ambiguous or unsupported targets before building" {
  let invalid : Array[Json] = [
    {},
    { "package": "/pkg", "program": "/prog" },
    { "package": "relative" },
    { "package": 1 },
    { "package": "/missing-moondbg-package" },
    { "package": "/pkg", "args": [] },
  ]
  for args in invalid {
    let output : Array[String] = []
    assert_true(
      try {
        prepare_launch(args, (_, text) => output.push(text)) |> ignore
        false
      } catch {
        _ => true
      },
    )
    assert_true(output.is_empty())
  }
}

///|
async test "preparation streams output but does not claim initialized before success" {
  let client = ConnectionSession::new()
  let inbox : @async.Queue[LiveInput] = @async.Queue(kind=Blocking(16))
  defer inbox.close()
  let messages = capture_messages(writer => {
    let args = await_preparation(writer, client, 2, {}, inbox, prepare=(
      _,
      output,
    ) => {
      output("stderr", "编译诊断\n")
      { "program": "/built/program" }
    })
    assert_eq(args, Some(Json({ "program": "/built/program" })))
  })
  assert_true(
    messages
    is [
      {
        "event": String("output"),
        "body": {
          "category": String("stderr"),
          "output": String("编译诊断\n"),
          ..
        },
        ..
      },
    ],
  )
}

///|
async test "disconnect and EOF cancel preparation and wait for its cleanup" {
  for eof in [false, true] {
    let client = ConnectionSession::new()
    let inbox : @async.Queue[LiveInput] = @async.Queue(kind=Blocking(16))
    let blocker : @async.Queue[Unit] = @async.Queue(kind=Blocking(1))
    defer inbox.close()
    defer blocker.close()
    let cleanup : Array[String] = []
    let messages = capture_messages(writer => {
      let result = await_preparation(writer, client, 2, {}, inbox, prepare=(
        _,
        output,
      ) => {
        defer cleanup.push("cancelled")
        output("console", "building\n")
        inbox.put(Client(Some(request(3, "threads").stringify())))
        inbox.put(
          Client(
            if eof {
              None
            } else {
              Some(request(4, "disconnect").stringify())
            },
          ),
        )
        blocker.get()
        { "program": "/must-not-run" }
      })
      assert_eq(result, None)
      assert_eq(cleanup, ["cancelled"])
    })
    assert_true(client.closed)
    assert_false(
      messages.any(message => {
        message
        is { "event": String("initialized" | "process" | "stopped"), .. }
      }),
    )
    assert_true(
      messages.any(message => {
        message is { "request_seq": Number(3, ..), "success": False, .. }
      }),
    )
    if !eof {
      assert_true(
        messages.any(message => {
          message is { "command": String("disconnect"), "success": True, .. }
        }),
      )
      assert_true(
        messages.any(message => {
          message is { "command": String("launch"), "success": False, .. }
        }),
      )
    }
  }
}

///|
async test "build failures report diagnostics and failed launch without a live session" {
  let client = ConnectionSession::new()
  let inbox : @async.Queue[LiveInput] = @async.Queue(kind=Blocking(16))
  defer inbox.close()
  let messages = capture_messages(writer => {
    assert_eq(
      await_preparation(writer, client, 2, {}, inbox, prepare=(_, output) => {
        output("stderr", "missing_value\n")
        raise LiveError("build failed")
      }),
      None,
    )
  })
  assert_true(
    messages.any(message => {
      message is { "command": String("launch"), "success": False, .. }
    }),
  )
  assert_true(
    messages.any(message => message is { "event": String("terminated"), .. }),
  )
  assert_false(
    messages.any(message => {
      message is { "event": String("initialized" | "process"), .. }
    }),
  )
}
