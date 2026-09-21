///|
pub(all) suberror ConditionError {
  ConditionError(String)
} derive(Debug)

///|
pub extend ConditionError with @debug.Debug::{to_repr}

///|
priv enum Comparison {
  Greater
  GreaterEqual
  Less
  LessEqual
  Equal
  NotEqual
} derive(Eq, Debug)

///|
/// Round one: one local Int compared to one decimal Int literal. Parsing
/// never executes code, resolves a variable, or delegates syntax to LLDB.
pub struct IntCondition {
  variable : String
  text : String
  priv comparison : Comparison
  priv literal : Int
} derive(Eq, Debug)

///|
pub extend IntCondition with Eq::{equal, not_equal}

///|
pub extend IntCondition with @debug.Debug::{to_repr}

///|
pub fn IntCondition::parse(
  input : StringView,
) -> IntCondition raise ConditionError {
  let input = input.trim()
  let split = for index, ch in input.iter2() {
    if ch is ('>' | '<' | '=' | '!') {
      break Some(index)
    }
  } nobreak {
    None
  }
  guard split is Some(index) else {
    raise ConditionError(
      "Expected <Int variable> <comparison> <decimal integer>; comparisons: > >= < <= == !=",
    )
  }
  let variable = input[:index].trim()
  guard variable is [first, .. rest] &&
    (first.is_ascii_alphabetic() || first == '_') &&
    rest.all(ch => ch.is_ascii_alphabetic() || ch.is_ascii_digit() || ch == '_') else {
    raise ConditionError(
      "Condition requires a simple local variable name (ASCII letters, digits and underscore)",
    )
  }
  let (comparison, operator, value) = match input[index:] {
    ['>', '=', .. value] => (GreaterEqual, ">=", value)
    ['<', '=', .. value] => (LessEqual, "<=", value)
    ['=', '=', .. value] => (Equal, "==", value)
    ['!', '=', .. value] => (NotEqual, "!=", value)
    ['>', .. value] => (Greater, ">", value)
    ['<', .. value] => (Less, "<", value)
    _ =>
      raise ConditionError(
        "Use == for equality; supported comparisons: > >= < <= == !=",
      )
  }
  let literal = decimal_int(value.trim())
  {
    variable: variable.to_owned(),
    text: "\{variable} \{operator} \{literal}",
    comparison,
    literal,
  }
}

///|
/// Strict decoding of DAP's raw scalar text, after the caller checks its type.
/// This never parses a REPL rendering or coerces a floating-point value to Int.
pub fn decimal_int(text : StringView) -> Int raise ConditionError {
  let digits = match text {
    ['-', .. rest] => rest
    _ => text
  }
  guard !digits.is_empty() && digits.all(ch => ch is ('0'..='9')) else {
    raise ConditionError("Expected a signed 32-bit decimal integer")
  }
  @string.parse_int(text, base=10) catch {
    _ => raise ConditionError("Integer is outside the MoonBit Int range")
  }
}

///|
pub fn IntCondition::evaluate(self : IntCondition, value : Int) -> Bool {
  match self.comparison {
    Greater => value > self.literal
    GreaterEqual => value >= self.literal
    Less => value < self.literal
    LessEqual => value <= self.literal
    Equal => value == self.literal
    NotEqual => value != self.literal
  }
}

///|
test "integer comparison grammar and boundaries" {
  for
    (text, value, expected) in [
      ("i > 5", 7, true),
      ("i>5", 5, false),
      ("i>=5", 5, true),
      ("i<5", 4, true),
      ("i<=5", 5, true),
      ("i == -7", -7, true),
      ("i!=5", 5, false),
      ("i == -2147483648", -2147483648, true),
      ("i == 2147483647", 2147483647, true),
    ] {
    assert_eq(IntCondition::parse(text).evaluate(value), expected)
  }
  for
    text in [
      "i = 1", "i > 1.0", "i > 2147483648", "i > -2147483649", "i > 1 && j < 2",
      "point.x > 1", "arr[0] > 1", "i > other", "i > 0x10", "i > 1; quit", "i >",
      "i() > 1",
    ] {
    assert_true(
      try {
        IntCondition::parse(text) |> ignore
        false
      } catch {
        _ => true
      },
      msg=text,
    )
  }
  assert_eq(IntCondition::parse("  i  >=  -1  ").text, "i >= -1")
}
