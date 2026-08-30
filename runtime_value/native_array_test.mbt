///|
test "native array element types follow raw DAP pointer types" {
  assert_eq(
    @runtime_value.native_array_element_from_pointer_type("int *"),
    Some(@runtime_value.NativeArrayScalar(@runtime_value.NativeInt)),
  )
  assert_eq(
    @runtime_value.native_array_element_from_pointer_type(
      "unsigned long long *",
    ),
    Some(@runtime_value.NativeArrayScalar(@runtime_value.NativeUInt64)),
  )
  assert_eq(
    @runtime_value.native_array_element_from_pointer_type(
      "example/geometry/Point **",
    ),
    Some(@runtime_value.NativeArrayOpaque("Point")),
  )
  assert_eq(
    @runtime_value.native_array_element_from_pointer_type("not a pointer"),
    None,
  )
}

///|
test "debug payload types reduce to scalar or short source names" {
  assert_eq(
    @runtime_value.native_scalar_from_debug_type("int"),
    Some(@runtime_value.NativeInt),
  )
  assert_eq(
    @runtime_value.native_scalar_from_debug_type("Kaida-Amethyst/example/List"),
    None,
  )
  assert_eq(
    @runtime_value.source_name_from_debug_type("double"),
    Some("Double"),
  )
  assert_eq(
    @runtime_value.source_name_from_debug_type("Kaida-Amethyst/example/List"),
    Some("List"),
  )
  assert_eq(
    @runtime_value.source_name_from_debug_type("moonbit_string_t"),
    Some("String"),
  )
  assert_eq(
    @runtime_value.source_name_from_debug_type("moonbit.array_i32"),
    Some("FixedArray[Int]"),
  )
}

///|
test "native storage capacity is decoded before planning a bounded preview" {
  assert_eq(
    @runtime_value.decode_native_array_capacity(
      b"\x00\x00\x00\x00\x64\x00\x00\x00",
    ),
    100,
  )
  let short = @runtime_value.IndexedPreviewPlan::new(3)
  assert_eq(short.head_count(), 3)
  assert_eq(short.tail_index(), None)
  assert_eq(short.selected_count(), 3)
  let long = @runtime_value.IndexedPreviewPlan::new(100)
  assert_eq(long.head_count(), 15)
  assert_eq(long.tail_index(), Some(99))
  assert_eq(long.selected_count(), 16)
  assert_eq(long.tail_byte_offset(4), Some(396))
}

///|
test "Array logical length must stay within initialized native capacity" {
  @runtime_value.validate_array_length(10, 10)
  @runtime_value.validate_array_length(100, 128)
  @runtime_value.validate_array_length(0, 0)
  assert_true(
    try {
      @runtime_value.validate_array_length(11, 10)
      false
    } catch {
      @runtime_value.InvalidArrayLength(length=11, capacity=10) => true
      _ => false
    },
  )
  assert_true(
    try {
      @runtime_value.validate_array_length(-1, 10)
      false
    } catch {
      @runtime_value.InvalidArrayLength(length=-1, capacity=10) => true
      _ => false
    },
  )
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
test "native array decoder rejects malformed metadata and payloads" {
  assert_true(
    try {
      @runtime_value.decode_native_array_capacity(b"\x00") |> ignore
      false
    } catch {
      @runtime_value.InvalidNativeArrayHeaderSize(1) => true
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
