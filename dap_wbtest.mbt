///|
test "DAP framing counts UTF-8 bytes" {
  assert_eq(frame_message("hi"), "Content-Length: 2\r\n\r\nhi")
  assert_eq(frame_message("月"), "Content-Length: 3\r\n\r\n月")
}

///|
test "Content-Length parsing is case-insensitive" {
  assert_eq(parse_content_length("Content-Length: 42\r\n"), Some(42))
  assert_eq(parse_content_length("content-length: 7"), Some(7))
  assert_eq(parse_content_length("Content-Type: application/json"), None)
  assert_eq(parse_content_length("Content-Length: nope"), None)
}

///|
test "classify DAP events and responses" {
  assert_true(
    classify_message({ "seq": 2, "type": "event", "event": "initialized" })
    is Event("initialized"),
  )
  assert_true(
    classify_message({
      "seq": 3,
      "type": "response",
      "request_seq": 1,
      "success": true,
    })
    is Response(request_seq=1, success=true, message=None),
  )
}
