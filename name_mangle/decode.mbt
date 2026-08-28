///|
priv struct SymbolCursor {
  bytes : Bytes
  mut offset : Int
}

///|
fn SymbolCursor::new(symbol : StringView) -> SymbolCursor {
  { bytes: @utf8.encode(symbol), offset: 0, }
}

///|
fn SymbolCursor::at(bytes : Bytes, offset : Int) -> SymbolCursor {
  { bytes, offset, }
}

///|
fn SymbolCursor::peek(self : SymbolCursor) -> Byte? {
  self.bytes.get(self.offset)
}

///|
fn SymbolCursor::take(self : SymbolCursor) -> Byte raise NameMangleError {
  guard self.bytes.get(self.offset) is Some(byte) else {
    raise InvalidSymbol("unexpected end of symbol")
  }
  self.offset += 1
  byte
}

///|
fn SymbolCursor::expect(
  self : SymbolCursor,
  expected : Byte,
) -> Unit raise NameMangleError {
  let actual = self.take()
  guard actual == expected else {
    raise InvalidSymbol(
      "expected byte \{expected.to_int()}, found \{actual.to_int()}",
    )
  }
}

///|
fn SymbolCursor::is_at_end(self : SymbolCursor) -> Bool {
  self.offset == self.bytes.length()
}

///|
fn decimal_digit(byte : Byte) -> Int? {
  if byte >= b'0' && byte <= b'9' {
    Some(byte.to_int() - b'0'.to_int())
  } else {
    None
  }
}

///|
fn SymbolCursor::read_decimal(self : SymbolCursor) -> Int raise NameMangleError {
  guard self.peek() is Some(first) && decimal_digit(first) is Some(_) else {
    raise InvalidSymbol("expected a decimal number")
  }
  for value = 0 {
    guard self.peek() is Some(byte) && decimal_digit(byte) is Some(digit) else {
      break value
    }
    guard value <= 100_000_000 else {
      raise InvalidSymbol("decimal number is too large")
    }
    self.offset += 1
    continue value * 10 + digit
  }
}

///|
fn hex_digit(byte : Byte) -> Int? {
  match byte {
    b'0'..=b'9' => Some(byte.to_int() - b'0'.to_int())
    b'a'..=b'f' => Some(byte.to_int() - b'a'.to_int() + 10)
    b'A'..=b'F' => Some(byte.to_int() - b'A'.to_int() + 10)
    _ => None
  }
}

///|
fn decode_identifier_bytes(encoded : Bytes) -> String raise NameMangleError {
  let decoded : Array[Byte] = []
  for offset = 0; offset < encoded.length(); {
    guard encoded.get(offset) is Some(byte) else {
      raise InvalidSymbol("identifier ended unexpectedly")
    }
    if byte != b'_' {
      guard is_ascii_alphanumeric(byte) else {
        raise InvalidSymbol("identifier contains an unescaped byte")
      }
      decoded.push(byte)
      continue offset + 1
    }
    guard encoded.get(offset + 1) is Some(next) else {
      raise InvalidSymbol("identifier ends in an incomplete escape")
    }
    if next == b'_' {
      decoded.push(b'_')
      continue offset + 2
    }
    guard encoded.get(offset + 2) is Some(last) &&
      hex_digit(next) is Some(high) &&
      hex_digit(last) is Some(low) else {
      raise InvalidSymbol("identifier contains an invalid hexadecimal escape")
    }
    decoded.push(((high << 4) | low).to_byte())
    continue offset + 3
  }
  @utf8.decode(Bytes::from_array(decoded)) catch {
    _ => raise InvalidSymbol("identifier escape is not valid UTF-8")
  }
}

///|
fn SymbolCursor::parse_identifier(
  self : SymbolCursor,
) -> String raise NameMangleError {
  let encoded_length = self.read_decimal()
  guard encoded_length > 0 else {
    raise InvalidSymbol("identifier length must be positive")
  }
  let end = self.offset + encoded_length
  guard end <= self.bytes.length() else {
    raise InvalidSymbol("identifier length exceeds the remaining symbol")
  }
  let encoded = self.bytes[self.offset:end].to_owned()
  self.offset = end
  decode_identifier_bytes(encoded)
}

///|
fn parse_exact_decimal_prefix(bytes : Bytes, start : Int, end : Int) -> Int? {
  guard start < end else { return None }
  for offset = start, value = 0; offset < end; {
    guard bytes.get(offset) is Some(byte) && decimal_digit(byte) is Some(digit) else {
      break None
    }
    guard value <= 100_000_000 else { break None }
    continue offset + 1, value * 10 + digit
  } nobreak {
    Some(value)
  }
}

///|
fn parse_package_segments_candidate(
  bytes : Bytes,
  segment_start : Int,
  count : Int,
) -> (String, Int)? {
  guard count >= 0 && count <= 1024 else { return None }
  let candidate = SymbolCursor::at(bytes, segment_start)
  let segments : Array[String] = []
  let valid = try {
    for _ in 0..<count {
      segments.push(candidate.parse_identifier())
    }
    true
  } catch {
    _ => false
  }
  guard valid else { return None }
  guard candidate.peek() is Some(next) && decimal_digit(next) is Some(_) else {
    return None
  }
  Some((segments.join("/"), candidate.offset))
}

///|
fn SymbolCursor::parse_counted_package_segments(
  self : SymbolCursor,
) -> String raise NameMangleError {
  let count_start = self.offset
  for count_end = count_start
      self.bytes.get(count_end) is Some(byte) && decimal_digit(byte) is Some(_)
      count_end = count_end + 1 {
    let prefix_end = count_end + 1
    guard parse_exact_decimal_prefix(self.bytes, count_start, prefix_end)
      is Some(count) else {
      continue
    }
    guard parse_package_segments_candidate(self.bytes, prefix_end, count)
      is Some((package_name, package_end)) else {
      continue
    }
    self.offset = package_end
    return package_name
  }
  raise InvalidSymbol("invalid package segment count or package path")
}

///|
fn SymbolCursor::parse_package(
  self : SymbolCursor,
) -> String raise NameMangleError {
  self.expect(b'P')
  match self.peek() {
    Some(b'B') => {
      self.offset += 1
      "moonbitlang/core/builtin"
    }
    Some(b'C') => {
      self.offset += 1
      let suffix = self.parse_counted_package_segments()
      guard suffix != "" else {
        raise InvalidSymbol("core package suffix must not be empty")
      }
      "moonbitlang/core/\{suffix}"
    }
    Some(_) => self.parse_counted_package_segments()
    None => raise InvalidSymbol("package marker has no payload")
  }
}

///|
fn parse_type_arguments(
  cursor : SymbolCursor,
) -> Array[String] raise NameMangleError {
  cursor.expect(b'G')
  let arguments : Array[String] = []
  while cursor.peek() is Some(byte) && byte != b'E' {
    arguments.push(parse_type_argument(cursor))
  }
  cursor.expect(b'E')
  guard arguments.length() > 0 else {
    raise InvalidSymbol("generic argument list must not be empty")
  }
  arguments
}

///|
fn parse_type_reference(cursor : SymbolCursor) -> String raise NameMangleError {
  cursor.expect(b'R')
  let package_name = cursor.parse_package()
  let mut type_name = cursor.parse_identifier()
  if cursor.peek() is Some(b'L') {
    cursor.offset += 1
    type_name = "\{type_name}.\{cursor.parse_identifier()}"
  }
  let arguments = if cursor.peek() is Some(b'G') {
    parse_type_arguments(cursor)
  } else {
    []
  }
  let qualified = if package_name == "" {
    "@\{type_name}"
  } else {
    "@\{package_name}.\{type_name}"
  }
  if arguments.length() == 0 {
    qualified
  } else {
    "\{qualified}[\{arguments.join(", ")}]"
  }
}

///|
fn parse_function_type(
  cursor : SymbolCursor,
  is_async : Bool,
  is_raw : Bool,
) -> String raise NameMangleError {
  cursor.expect(b'W')
  let parameters : Array[String] = []
  while cursor.peek() is Some(byte) && byte != b'E' {
    parameters.push(parse_type_argument(cursor))
  }
  cursor.expect(b'E')
  let return_type = parse_type_argument(cursor)
  let error_type = if cursor.peek() is Some(b'Q') {
    cursor.offset += 1
    Some(parse_type_argument(cursor))
  } else {
    None
  }
  let prefix = match (is_raw, is_async) {
    (true, true) => "raw async "
    (true, false) => "raw "
    (false, true) => "async "
    (false, false) => ""
  }
  let suffix = match error_type {
    Some(error_type) => "!\{error_type}"
    None => ""
  }
  "\{prefix}(\{parameters.join(", ")}) -> \{return_type}\{suffix}"
}

///|
fn parse_type_argument(cursor : SymbolCursor) -> String raise NameMangleError {
  match cursor.peek() {
    Some(b'i') => {
      cursor.offset += 1
      "Int"
    }
    Some(b'l') => {
      cursor.offset += 1
      "Int64"
    }
    Some(b'h') => {
      cursor.offset += 1
      "Int16"
    }
    Some(b'j') => {
      cursor.offset += 1
      "UInt"
    }
    Some(b'k') => {
      cursor.offset += 1
      "UInt16"
    }
    Some(b'm') => {
      cursor.offset += 1
      "UInt64"
    }
    Some(b'd') => {
      cursor.offset += 1
      "Double"
    }
    Some(b'f') => {
      cursor.offset += 1
      "Float"
    }
    Some(b'b') => {
      cursor.offset += 1
      "Bool"
    }
    Some(b'c') => {
      cursor.offset += 1
      "Char"
    }
    Some(b's') => {
      cursor.offset += 1
      "String"
    }
    Some(b'u') => {
      cursor.offset += 1
      "Unit"
    }
    Some(b'y') => {
      cursor.offset += 1
      "Byte"
    }
    Some(b'z') => {
      cursor.offset += 1
      "Bytes"
    }
    Some(b'v') => {
      cursor.offset += 1
      "V128"
    }
    Some(b'A') => {
      cursor.offset += 1
      "FixedArray[\{parse_type_argument(cursor)}]"
    }
    Some(b'N') => {
      cursor.offset += 1
      "ReadOnlyArray[\{parse_type_argument(cursor)}]"
    }
    Some(b'O') => {
      cursor.offset += 1
      "Option[\{parse_type_argument(cursor)}]"
    }
    Some(b'U') => {
      cursor.offset += 1
      let elements : Array[String] = []
      while cursor.peek() is Some(byte) && byte != b'E' {
        elements.push(parse_type_argument(cursor))
      }
      cursor.expect(b'E')
      "(\{elements.join(", ")})"
    }
    Some(b'V') => {
      cursor.offset += 1
      let is_raw = if cursor.peek() is Some(b'X') {
        cursor.offset += 1
        true
      } else {
        false
      }
      parse_function_type(cursor, true, is_raw)
    }
    Some(b'X') => {
      cursor.offset += 1
      parse_function_type(cursor, false, true)
    }
    Some(b'W') => parse_function_type(cursor, false, false)
    Some(b'R') => parse_type_reference(cursor)
    Some(byte) =>
      raise InvalidSymbol("unknown type argument marker \{byte.to_int()}")
    None => raise InvalidSymbol("missing type argument")
  }
}

///|
/// Demangles one complete MoonBit v0 top-level function physical symbol.
///
/// Symbols for methods, lifted functions, closures and future mangling
/// versions are rejected instead of being partially decoded.
pub fn demangle_top_level_function(
  symbol : StringView,
) -> TopLevelFunctionSymbol raise NameMangleError {
  let cursor = SymbolCursor::new(symbol)
  guard cursor.peek() is Some(b'_') else {
    raise InvalidSymbol("symbol does not start with the MoonBit prefix")
  }
  cursor.expect(b'_')
  cursor.expect(b'M')
  guard cursor.peek() is Some(version) else {
    raise InvalidSymbol("symbol is missing its mangling version")
  }
  guard version == b'0' else {
    raise UnsupportedVersion("_M\{version.to_int().unsafe_to_char()}")
  }
  cursor.offset += 1
  cursor.expect(b'F')
  let package_name = cursor.parse_package()
  let function_name = cursor.parse_identifier()
  let type_arguments = if cursor.peek() is Some(b'G') {
    parse_type_arguments(cursor)
  } else {
    []
  }
  let error_type_argument = if cursor.peek() is Some(b'H') {
    cursor.offset += 1
    Some(parse_type_argument(cursor))
  } else {
    None
  }
  guard cursor.is_at_end() else {
    raise InvalidSymbol("top-level function symbol has an unsupported suffix")
  }
  TopLevelFunctionSymbol::new(
    package_name, function_name, type_arguments, error_type_argument,
  )
}
