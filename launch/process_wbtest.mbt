///|
async test "build output preserves split UTF-8 characters and streams without newlines" {
  let bytes = @utf8.encode("编译🙂done")
  let reader = @io.MemoryReader(writer => {
    for byte in bytes {
      writer.write(Bytes::from_array([byte]))
    }
  })
  defer reader.close()
  let chunks : Array[String] = []
  let capture = @buffer.Buffer()
  stream_build_output(
    reader,
    "stderr",
    (category, text) => {
      assert_eq(category, "stderr")
      chunks.push(text)
    },
    capture~,
  )
  assert_eq(chunks.join(""), "编译🙂done")
  assert_eq(capture.to_bytes(), bytes)
  assert_eq(utf8_complete_prefix(b"abc\xe7"), 3)
  assert_eq(utf8_complete_prefix(b"abc\xe7\xbc"), 3)
  assert_eq(utf8_complete_prefix(b"abc\xe7\xbc\x96"), 6)
}
