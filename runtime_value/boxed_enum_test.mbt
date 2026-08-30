///|
test "boxed enum tag is the descriptor's low eight bits" {
  assert_eq(@runtime_value.decode_boxed_enum_tag(b"\x00\x00\x00\x40"), 0)
  assert_eq(@runtime_value.decode_boxed_enum_tag(b"\x01\x00\x00\x40"), 1)
  assert_eq(@runtime_value.decode_boxed_enum_tag(b"\xff\xab\xcd\xef"), 255)
}

///|
test "boxed enum descriptor requires exactly four bytes" {
  assert_true(
    try {
      @runtime_value.decode_boxed_enum_tag(b"\x01\x00\x00") |> ignore
      false
    } catch {
      @runtime_value.InvalidEnumDescriptorSize(3) => true
      _ => false
    },
  )
}
