///|
test "toolchain home defaults only when MOON_HOME is absent" {
  assert_eq(
    resolve_moon_home(None, Some("/Users/example")),
    "/Users/example/.moon",
  )
  assert_eq(
    resolve_moon_home(Some("/custom/moon"), Some("/Users/example")),
    "/custom/moon",
  )
  assert_eq(resolve_moon_home(Some("/custom/moon"), None), "/custom/moon")
  for home in ["", "relative", "~/.moon"] {
    let rejected = try {
      resolve_moon_home(Some(home), Some("/Users/example")) |> ignore
      false
    } catch {
      LaunchError(_) => true
    }
    assert_true(rejected)
  }
  for home in [None, Some(""), Some("relative")] {
    let rejected = try {
      resolve_moon_home(None, home) |> ignore
      false
    } catch {
      LaunchError(_) => true
    }
    assert_true(rejected)
  }
}

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
