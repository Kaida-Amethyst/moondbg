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
priv enum ComparisonOperand {
  PathOperand(VariablePath)
  IntegerOperand(String)
  BoolOperand(Bool)
} derive(Eq, Debug)

///|
/// Resolving paths belongs to the debugger. Integer literals acquire the
/// left path's type; runtime values are never implicitly converted.
priv struct ScalarComparison {
  left : VariablePath
  right : ComparisonOperand
  text : String
  comparison : Comparison
} derive(Eq, Debug)

///|
fn ScalarComparison::parse(
  input : StringView,
) -> ScalarComparison raise ConditionError {
  let input = input.trim()
  guard input.length() <= 8192 else {
    raise ConditionError("Condition is too long")
  }
  let split = for index, ch in input.iter2() {
    if ch is ('>' | '<' | '=' | '!') {
      break Some(index)
    }
  } nobreak {
    None
  }
  guard split is Some(index) else {
    raise ConditionError(
      "Expected <variable path> <comparison> <path or literal>; comparisons: > >= < <= == !=",
    )
  }
  guard VariablePath::parse(input[:index].trim()) is Some(left) &&
    left.range() is None else {
    raise ConditionError(
      "Invalid left variable path; use point.x or arr[0], without calls or arithmetic",
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
  let value = value.trim()
  let (right, text) = match value {
    "true" => (BoolOperand(true), "true")
    "false" => (BoolOperand(false), "false")
    ['-' | '0'..='9', ..] => {
      let integer = integer_literal(value)
      (IntegerOperand(integer), integer)
    }
    _ => {
      guard VariablePath::parse(value) is Some(path) && path.range() is None else {
        raise ConditionError(
          "Invalid right operand; use a variable path, decimal integer, true or false",
        )
      }
      (PathOperand(path), path.display_name())
    }
  }
  if right is BoolOperand(_) && !(comparison is (Equal | NotEqual)) {
    raise ConditionError("Bool conditions support only == and !=")
  }
  {
    left,
    right,
    comparison,
    text: "\{left.display_name()} \{operator} \{text}",
  }
}

///|
fn integer_literal(text : StringView) -> String raise ConditionError {
  decimal_digits(text)
  try {
    if text.has_prefix("-") {
      @string.parse_int64(text, base=10).to_string()
    } else {
      @string.parse_uint64(text, base=10).to_string()
    }
  } catch {
    _ =>
      raise ConditionError(
        "Integer literal is outside the supported 64-bit range",
      )
  }
}

///|
fn ScalarComparison::literal_value(
  self : ScalarComparison,
  left : ScalarValue,
) -> ScalarValue? raise ConditionError {
  match self.right {
    PathOperand(_) => None
    BoolOperand(value) => Some(BoolValue(value))
    IntegerOperand(text) => {
      guard !(left is BoolValue(_)) else {
        raise ConditionError("Cannot compare Bool with an integer literal")
      }
      Some(ScalarValue::decode(left.type_name(), text))
    }
  }
}

///|
fn[T : Compare] Comparison::matches(
  self : Comparison,
  left : T,
  right : T,
) -> Bool {
  match self {
    Greater => left > right
    GreaterEqual => left >= right
    Less => left < right
    LessEqual => left <= right
    Equal => left == right
    NotEqual => left != right
  }
}

///|
fn ScalarComparison::evaluate(
  self : ScalarComparison,
  left : ScalarValue,
  right : ScalarValue,
) -> Bool raise ConditionError {
  match (left, right) {
    (IntValue(a), IntValue(b)) => self.comparison.matches(a, b)
    (UIntValue(a), UIntValue(b)) => self.comparison.matches(a, b)
    (Int64Value(a), Int64Value(b)) => self.comparison.matches(a, b)
    (UInt64Value(a), UInt64Value(b)) => self.comparison.matches(a, b)
    (BoolValue(a), BoolValue(b)) =>
      match self.comparison {
        Equal => a == b
        NotEqual => a != b
        _ => raise ConditionError("Bool conditions support only == and !=")
      }
    _ =>
      raise ConditionError(
        "Condition type mismatch: \{left.type_name()} and \{right.type_name()}; implicit conversions are not supported",
      )
  }
}
