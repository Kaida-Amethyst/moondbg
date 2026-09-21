///|
test "condition grammar reuses paths and preserves exact integer literals" {
  for
    (text, canonical) in [
      ("point.x>5", "point.x > 5"),
      ("arr[00] == fixed[1]", "arr[0] == fixed[1]"),
      ("line.start.x < limit", "line.start.x < limit"),
      ("points[0].x >= -07", "points[0].x >= -7"),
      ("ready == true", "ready == true"),
      ("ready != other.flag", "ready != other.flag"),
      ("wide == 18446744073709551615", "wide == 18446744073709551615"),
      ("signed == -9223372036854775808", "signed == -9223372036854775808"),
      ("线段.起点.x < 上限", "线段.起点.x < 上限"),
    ] {
    assert_eq(Condition::parse(text).text, canonical)
  }
  for
    text in [
      "i = 1", "i > 1.0", "i > 1 && j < 2", "i > 0x10", "i > 1; quit", "i >", "i() > 1",
      "arr[i] == 0", "a.0 == 1", "a + 1 == 2", "ready > true", "x == 18446744073709551616",
      "x == -9223372036854775809",
    ] {
    assert_true(
      try {
        Condition::parse(text) |> ignore
        false
      } catch {
        _ => true
      },
      msg=text,
    )
  }
}

///|
test "scalar comparisons keep integer width signedness and Bool semantics" {
  for
    (text, left, right, expected) in [
      ("i > j", IntValue(7), IntValue(5), true),
      ("i >= j", UIntValue(4294967295U), UIntValue(4294967295U), true),
      ("i < j", Int64Value(-9223372036854775808L), Int64Value(0L), true),
      ("i <= j", UInt64Value(18446744073709551615UL), UInt64Value(0UL), false),
      (
        "i == j",
        UInt64Value(9007199254740992UL),
        UInt64Value(9007199254740993UL),
        false,
      ),
      (
        "i != j",
        Int64Value(-9007199254740992L),
        Int64Value(-9007199254740993L),
        true,
      ),
      ("i == j", BoolValue(true), BoolValue(false), false),
      ("i != j", BoolValue(true), BoolValue(false), true),
    ] {
    assert_eq(Condition::parse(text).evaluate(left, right), expected)
  }
  for
    (text, left, right) in [
      ("i == j", IntValue(1), UIntValue(1U)),
      ("i == j", Int64Value(1L), UInt64Value(1UL)),
      ("i == j", IntValue(1), Int64Value(1L)),
      ("i == j", BoolValue(true), IntValue(1)),
      ("i < j", BoolValue(false), BoolValue(true)),
    ] {
    assert_true(
      try {
        Condition::parse(text).evaluate(left, right) |> ignore
        false
      } catch {
        _ => true
      },
    )
  }
}

///|
test "literal typing checks representability without converting runtime operands" {
  assert_eq(
    Condition::parse("i == 9007199254740993").literal_value(UInt64Value(0UL)),
    Some(UInt64Value(9007199254740993UL)),
  )
  assert_eq(
    Condition::parse("i == -9223372036854775808").literal_value(Int64Value(0L)),
    Some(Int64Value(-9223372036854775808L)),
  )
  for
    (text, left) in [
      ("i == 2147483648", IntValue(0)),
      ("i == -2147483649", IntValue(0)),
      ("i == 4294967296", UIntValue(0U)),
      ("i == -1", UIntValue(0U)),
      ("i == 9223372036854775808", Int64Value(0L)),
      ("i == -1", UInt64Value(0UL)),
      ("i == 1", BoolValue(true)),
    ] {
    assert_true(
      try {
        Condition::parse(text).literal_value(left) |> ignore
        false
      } catch {
        _ => true
      },
      msg=text,
    )
  }
}

///|
test "raw scalar decoding is strict and rejects unsupported or unavailable values" {
  for
    (name, text, expected) in [
      ("Bool", "true", BoolValue(true)),
      ("Bool", "0", BoolValue(false)),
      ("Int", "-2147483648", IntValue(-2147483648)),
      ("UInt", "4294967295", UIntValue(4294967295U)),
      ("Int64", "9223372036854775807", Int64Value(9223372036854775807L)),
      ("UInt64", "18446744073709551615", UInt64Value(18446744073709551615UL)),
    ] {
    assert_eq(ScalarValue::decode(name, text), expected)
  }
  for
    (name, text) in [
      ("Bool", "2"),
      ("UInt64", "-1"),
      ("Int", "<unavailable>"),
      ("Int", "0x10"),
      ("Int64", "1.0"),
      ("Double", "1"),
      ("Float", "1"),
      ("Point", "0x123"),
      ("Char", "1"),
      ("Int", "2147483648"),
    ] {
    assert_true(
      try {
        ScalarValue::decode(name, text) |> ignore
        false
      } catch {
        _ => true
      },
      msg="\{name}:\{text}",
    )
  }
}
