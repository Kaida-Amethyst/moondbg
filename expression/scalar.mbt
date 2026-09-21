///|
/// Exact supported values, never frontend-rendered text or a common Double
/// representation. Float/Double and non-scalars are deliberately unsupported.
pub(all) enum ScalarValue {
  BoolValue(Bool)
  IntValue(Int)
  UIntValue(UInt)
  Int64Value(Int64)
  UInt64Value(UInt64)
} derive(Eq, Debug)

///|
pub extend ScalarValue with Eq::{equal, not_equal}

///|
pub extend ScalarValue with @debug.Debug::{to_repr}

///|
pub fn ScalarValue::type_name(self : ScalarValue) -> String {
  match self {
    BoolValue(_) => "Bool"
    IntValue(_) => "Int"
    UIntValue(_) => "UInt"
    Int64Value(_) => "Int64"
    UInt64Value(_) => "UInt64"
  }
}

///|
fn decimal_digits(text : StringView) -> Unit raise ConditionError {
  let digits = match text {
    ['-', .. rest] => rest
    _ => text
  }
  guard !digits.is_empty() && digits.all(ch => ch is ('0'..='9')) else {
    raise ConditionError("Expected a decimal integer")
  }
}

///|
/// Decode raw DAP text after the backend establishes the source type.
/// Numeric Bool encodings are accepted only for typed debugger values, never
/// for condition literals. No address, summary or approximate numeric parsing.
pub fn ScalarValue::decode(
  type_name : String,
  text : StringView,
) -> ScalarValue raise ConditionError {
  let text = text.trim()
  if type_name == "Bool" {
    return match text {
      "true" | "1" => BoolValue(true)
      "false" | "0" => BoolValue(false)
      _ => raise ConditionError("Invalid or unavailable Bool value: \{text}")
    }
  }
  guard type_name is ("Int" | "UInt" | "Int64" | "UInt64") else {
    raise ConditionError(
      "Unsupported condition scalar type: \{type_name}; supported: Bool, Int, UInt, Int64, UInt64",
    )
  }
  decimal_digits(text)
  if type_name is ("UInt" | "UInt64") && text.has_prefix("-") {
    raise ConditionError("Negative value cannot be represented as \{type_name}")
  }
  try {
    match type_name {
      "Int" => IntValue(@string.parse_int(text, base=10))
      "UInt" => UIntValue(@string.parse_uint(text, base=10))
      "Int64" => Int64Value(@string.parse_int64(text, base=10))
      _ => UInt64Value(@string.parse_uint64(text, base=10))
    }
  } catch {
    _ =>
      raise ConditionError("Value '\{text}' is outside the \{type_name} range")
  }
}
