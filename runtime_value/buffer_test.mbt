///|
test "buffer quoting is lossless and terminal safe" {
  assert_eq(
    quote_buffer(
      StringBuffer,
      b"\x60\x4f\x7d\x59\x3d\xd8\x42\xde\x0a\x00\x41\x00\x00\x00\x42\x00",
    ),
    "\"你好🙂\\nA\\u0000B\"",
  )
  assert_eq(
    quote_buffer(StringBuffer, b"\x22\x00\x5c\x00\x09\x00\x0d\x00\x1b\x00"),
    "\"\\\"\\\\\\t\\r\\u001b\"",
  )
  assert_eq(quote_buffer(StringBuffer, b"\x3d\xd8"), "\"\\ud83d\"")
  assert_eq(quote_buffer(StringBuffer, b"\x42\xde"), "\"\\ude42\"")
  assert_eq(quote_buffer(StringBuffer, b""), "\"\"")
  assert_eq(quote_buffer(BytesBuffer, b"\x41\x00\xff"), "b\"\\x41\\x00\\xff\"")
  assert_eq(quote_buffer(BytesBuffer, b""), "b\"\"")
  let failed = try {
    quote_buffer(StringBuffer, b"x") |> ignore
    false
  } catch {
    InvalidScalarPayload(..) => true
    _ => false
  }
  assert_true(failed)
}

///|
test "buffer summaries distinguish empty complete and partial content" {
  assert_eq(
    BufferPreview::new(StringBuffer, 0, 0, 0, b"").summary(),
    "\"\" (length = 0 UTF-16 units)",
  )
  assert_eq(
    BufferPreview::new(BytesBuffer, 1000, 5, 6, b"\xff").summary(),
    "b\"\\xff\" (length = 1000 bytes; showing [5:6], truncated; use [start:end])",
  )
}

///|
test "source type names preserve nested generic constructors" {
  for
    (raw, expected) in [
      (
        "moonbitlang/core/result/Result[example/Point, String] &", "Result[Point, String]",
      ),
      (
        "example/Outer[other/Inner[p/Point], (Int, moonbit_string_t)] *", "Outer[Inner[Point], (Int, String)]",
      ),
      ("moonbit_bytes_t", "Bytes"),
      ("unsigned long", "UInt64"),
      ("example/Pair[unsigned long, unsigned int] &", "Pair[UInt64, UInt]"),
      ("项目/容器[包/点, moonbit_string_t] *", "容器[点, String]"),
    ] {
    assert_eq(source_name_from_debug_type(raw), Some(expected))
  }
}
