///|
test "buffer address parsing ignores summaries but rejects null and malformed pointers" {
  assert_eq(buffer_pointer("0x1234 u\"hello\""), Some("0x1234"))
  assert_eq(buffer_pointer("0x1234"), Some("0x1234"))
  for value in ["0x0", "nullptr", "\"hello\"", "0x123z", "<unavailable>"] {
    assert_eq(buffer_pointer(value), None)
  }
}

///|
async test "automatic UTF16 pages partition a final surrogate pair without an empty page" {
  let content = Bytes::makei(258, index => {
    match index {
      254 => 0x3d
      255 => 0xd8
      256 => 0x42
      257 => 0xde
      _ => 0
    }
  })
  let inspector = VariableInspector::new(
    (command, args) => {
      let offset = json_int_field(args, "offset").unwrap()
      let count = json_int_field(args, "count").unwrap()
      tree_reply(command, {
        "data": @base64.encode(content[offset:offset + count].to_owned()),
      })
    },
    () => Some(1),
    { "supportsReadMemoryRequest": true },
  )
  let identity = inspector.tree_identity(10)
  let layout : BufferLayout = {
    kind: @runtime_value.StringBuffer,
    pointer: "0x1000",
    length: 129,
  }
  let first = inspector.buffer_preview(identity, layout, None)
  let last = inspector.buffer_preview(
    identity,
    layout,
    Some((128, 129)),
    automatic=true,
  )
  assert_eq((first.start, first.end), (0, 127))
  assert_eq((last.start, last.end, last.quoted), (127, 129, "\"🙂\""))
  let exact = inspector.buffer_preview(identity, layout, Some((128, 129)))
  assert_eq(exact.quoted, "\"\\ude42\"")
}

///|
async test "buffer previews stay bounded and reject invalid ranges before payload reads" {
  let reads = []
  let inspector = VariableInspector::new(
    (command, args) => {
      assert_eq(command, "readMemory")
      let count = json_int_field(args, "count").unwrap()
      let offset = json_int_field(args, "offset").unwrap()
      reads.push((offset, count))
      assert_true(count <= 260)
      tree_reply(command, {
        "data": @base64.encode(Bytes::make(count, b'\x00')),
      })
    },
    () => Some(1),
    { "supportsReadMemoryRequest": true },
  )
  let identity = inspector.tree_identity(10)
  let layout : BufferLayout = {
    kind: @runtime_value.StringBuffer,
    pointer: "0x1000",
    length: 1000000,
  }
  let preview = inspector.buffer_preview(identity, layout, None)
  assert_eq((preview.start, preview.end, preview.length), (0, 128, 1000000))
  assert_eq(reads, [(0, 258)])
  for range in [(-1, 1), (2, 1), (0, 1000001), (0, 1025)] {
    let rejected = try {
      inspector.buffer_preview(identity, layout, Some(range)) |> ignore
      false
    } catch {
      BufferInspectionError(_) => true
      error => raise error
    }
    assert_true(rejected)
  }
  assert_eq(reads.length(), 1)
  let empty = inspector.buffer_preview(identity, layout, Some((5, 5)))
  assert_eq(empty.quoted, "\"\"")
  assert_eq(reads.length(), 1)
}

///|
async test "buffer read failures and resumed epochs never become empty content" {
  for
    mode in [
      "partial", "short", "invalid-base64", "stale", "unsupported", "rejected",
    ] {
    let epoch : Ref[Int?] = { val: Some(1), }
    let inspector = VariableInspector::new(
      (command, _) => {
        if mode == "rejected" {
          guard @dap.classify_message({
              "type": "response",
              "seq": 1,
              "request_seq": 1,
              "command": command,
              "success": false,
              "message": "unmapped address",
            })
            is @dap.Response(response) else {
            fail("response")
          }
          return response
        }
        if mode == "stale" {
          epoch.val = None
        }
        let body : Json = match mode {
          "partial" => { "data": "AAA=", "unreadableBytes": 1 }
          "short" => { "data": "" }
          "invalid-base64" => { "data": "!" }
          _ => { "data": "AAA=" }
        }
        tree_reply(command, body)
      },
      () => epoch.val,
      { "supportsReadMemoryRequest": mode != "unsupported" },
    )
    let identity = inspector.tree_identity(10)
    let failed = try {
      inspector.buffer_preview(
        identity,
        { kind: @runtime_value.StringBuffer, pointer: "0x1000", length: 1, },
        None,
      )
      |> ignore
      false
    } catch {
      StaleVariableResult(..) => mode == "stale"
      MemoryReadError(_) => mode != "stale" && mode != "unsupported"
      InvalidIndexedCollectionValue(_) => mode == "unsupported"
      error => raise error
    }
    assert_true(failed, msg=mode)
  }
}
