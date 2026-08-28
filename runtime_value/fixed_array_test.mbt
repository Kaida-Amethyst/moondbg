///|
test "FixedArray element types follow raw DAP pointer types" {
  assert_eq(
    @runtime_value.fixed_array_element_from_pointer_type("int *"),
    Some(@runtime_value.FixedArrayScalar(@runtime_value.NativeInt)),
  )
  assert_eq(
    @runtime_value.fixed_array_element_from_pointer_type("unsigned long long *"),
    Some(@runtime_value.FixedArrayScalar(@runtime_value.NativeUInt64)),
  )
  assert_eq(
    @runtime_value.fixed_array_element_from_pointer_type(
      "example/geometry/Point **",
    ),
    Some(@runtime_value.FixedArrayOpaque("Point")),
  )
  assert_eq(
    @runtime_value.fixed_array_element_from_pointer_type("not a pointer"),
    None,
  )
}

///|
test "FixedArray header length is decoded before planning its preview" {
  assert_eq(
    @runtime_value.decode_fixed_array_length(
      b"\x00\x00\x00\x00\x64\x00\x00\x00",
    ),
    100,
  )
  let short = @runtime_value.FixedArrayPreviewPlan::new(3)
  assert_eq(short.head_count(), 3)
  assert_eq(short.tail_index(), None)
  assert_eq(short.selected_count(), 3)
  let long = @runtime_value.FixedArrayPreviewPlan::new(100)
  assert_eq(long.head_count(), 15)
  assert_eq(long.tail_index(), Some(99))
  assert_eq(long.selected_count(), 16)
  assert_eq(long.tail_byte_offset(4), Some(396))
}

///|
test "native scalar payload decoder covers supported FixedArray elements" {
  assert_eq(
    @runtime_value.decode_scalar_payload(
      @runtime_value.NativeBool,
      b"\x00\x01",
      2,
    ),
    ["false", "true"],
  )
  assert_eq(
    @runtime_value.decode_scalar_payload(
      @runtime_value.NativeInt,
      b"\xff\xff\xff\xff\x2a\x00\x00\x00",
      2,
    ),
    ["-1", "42"],
  )
  assert_eq(
    @runtime_value.decode_scalar_payload(
      @runtime_value.NativeUInt,
      b"\xff\xff\xff\xff",
      1,
    ),
    ["4294967295"],
  )
  assert_eq(
    @runtime_value.decode_scalar_payload(
      @runtime_value.NativeInt64,
      b"\xff\xff\xff\xff\xff\xff\xff\xff",
      1,
    ),
    ["-1"],
  )
  assert_eq(
    @runtime_value.decode_scalar_payload(
      @runtime_value.NativeUInt64,
      b"\xff\xff\xff\xff\xff\xff\xff\xff",
      1,
    ),
    ["18446744073709551615"],
  )
  assert_eq(
    @runtime_value.decode_scalar_payload(
      @runtime_value.NativeFloat,
      b"\x00\x00\xc0\x3f",
      1,
    ),
    ["1.5"],
  )
  assert_eq(
    @runtime_value.decode_scalar_payload(
      @runtime_value.NativeDouble,
      b"\x00\x00\x00\x00\x00\x00\x02\xc0",
      1,
    ),
    ["-2.25"],
  )
}

///|
test "native FixedArray decoder rejects malformed metadata and payloads" {
  assert_true(
    try {
      @runtime_value.decode_fixed_array_length(b"\x00") |> ignore
      false
    } catch {
      @runtime_value.InvalidFixedArrayHeaderSize(1) => true
      _ => false
    },
  )
  assert_true(
    try {
      @runtime_value.decode_scalar_payload(
        @runtime_value.NativeInt,
        b"\x01\x00",
        1,
      )
      |> ignore
      false
    } catch {
      @runtime_value.InvalidScalarPayload(expected=4, actual=2) => true
      _ => false
    },
  )
  assert_true(
    try {
      @runtime_value.decode_scalar_payload(
        @runtime_value.NativeBool,
        b"\x02",
        1,
      )
      |> ignore
      false
    } catch {
      @runtime_value.InvalidBoolValue(2) => true
      _ => false
    },
  )
}
