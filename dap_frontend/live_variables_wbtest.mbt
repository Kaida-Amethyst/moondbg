///|
async test "scope handles are opaque, reject invalid input and expire across stops" {
  let (session, _) = live_test_session()
  let frames : Array[Json] = [{ "id": 90, "name": "main" }]
  session.inspection.map_frames(frames)
  assert_true(frames is [{ "id": Number(1, ..), .. }])
  let messages = capture_messages(writer => {
    session.on_client(writer, request(10, "scopes", arguments={ "frameId": 1 }))
    session.on_client(
      writer,
      request(11, "scopes", arguments={ "frameId": 90 }),
    )
    session.on_client(
      writer,
      request(12, "variables", arguments={
        "variablesReference": 1,
        "start": -1,
      }),
    )
    session.on_client(
      writer,
      request(13, "variables", arguments={
        "variablesReference": 1,
        "filter": "invalid",
      }),
    )
    session.on_client(
      writer,
      request(14, "continue", arguments={ "threadId": 7 }),
    )
    control_event(session, writer, "stopped")
    session.on_client(
      writer,
      request(15, "variables", arguments={ "variablesReference": 1 }),
    )
    session.on_client(writer, request(16, "scopes", arguments={ "frameId": 1 }))
  })
  assert_true(
    messages[0]
    is {
      "body": { "scopes": [{ "variablesReference": Number(1, ..), .. }], .. },
      ..
    },
  )
  for message in messages {
    if message is { "request_seq": Number(seq, ..), .. } && seq != 10 {
      assert_true(message is { "success": False, .. })
    }
  }
  let frames : Array[Json] = [{ "id": 90 }]
  session.inspection.map_frames(frames)
  assert_true(frames is [{ "id": Number(2, ..), .. }])
}

///|
async test "slow variable reads do not block continue and late results never revive handles" {
  let (session, transport) = live_test_session()
  let reply : @async.Queue[Json] = @async.Queue(kind=Blocking(1))
  defer reply.close()
  let job = VariableJob::{
    seq: 11,
    epoch: 0,
    target: Locals(90),
    start: 0,
    count: 0,
  }
  session.inspection.pending.set(11, job)
  let messages = capture_messages(writer => {
    session.request(
      0,
      "variables",
      { "variablesReference": 100 },
      inspection_reply=Some(reply),
    )
    session.on_client(
      writer,
      request(12, "continue", arguments={ "threadId": 7 }),
    )
    assert_false(session.stopped)
    assert_true(session.inspection.pending.is_empty())
    session.on_adapter(
      writer,
      {
        "type": "response",
        "request_seq": 1,
        "seq": 100,
        "command": "variables",
        "success": true,
        "body": { "variables": [] },
      },
      2,
      {},
    )
    session.complete_inspection(writer, 11, Ok([]))
  })
  assert_eq(transport.sent_messages().length(), 2)
  assert_true(
    messages is [{ "request_seq": Number(11, ..), "success": False, .. }],
  )
  assert_true(
    try {
      reply.get() |> ignore
      false
    } catch {
      _ => true
    },
  )
}

///|
async test "stale stack responses cannot mint frame handles after continue" {
  let (session, _) = live_test_session()
  let messages = capture_messages(writer => {
    session.on_client(
      writer,
      request(10, "stackTrace", arguments={ "threadId": 7 }),
    )
    session.on_client(
      writer,
      request(11, "continue", arguments={ "threadId": 7 }),
    )
    session.on_adapter(
      writer,
      {
        "type": "response",
        "request_seq": 1,
        "seq": 100,
        "command": "stackTrace",
        "success": true,
        "body": { "stackFrames": [{ "id": 90 }] },
      },
      2,
      {},
    )
  })
  assert_true(
    messages is [{ "request_seq": Number(10, ..), "success": False, .. }],
  )
  assert_true(session.inspection.frames.is_empty())
}
