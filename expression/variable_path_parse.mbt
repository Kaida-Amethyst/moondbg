///|
fn is_variable_name_char(character : Char, first~ : Bool) -> Bool {
  if character.is_ascii() {
    character.is_ascii_alphabetic() ||
    character == '_' ||
    (!first && character.is_ascii_digit())
  } else {
    character.is_printable() &&
    !character.is_whitespace() &&
    !character.is_control()
  }
}

///|
fn is_variable_path_segment(segment : StringView) -> Bool {
  guard segment is [first, .. rest] && is_variable_name_char(first, first=true) else {
    return false
  }
  rest.all(character => is_variable_name_char(character, first=false))
}

///|
priv struct VariablePathCursor {
  bytes : Bytes
  mut offset : Int
}

///|
fn VariablePathCursor::new(input : StringView) -> VariablePathCursor {
  { bytes: @utf8.encode(input), offset: 0, }
}

///|
fn VariablePathCursor::peek(self : VariablePathCursor) -> Byte? {
  self.bytes.get(self.offset)
}

///|
fn VariablePathCursor::is_at_end(self : VariablePathCursor) -> Bool {
  self.offset == self.bytes.length()
}

///|
fn VariablePathCursor::take_identifier(self : VariablePathCursor) -> String? {
  let start = self.offset
  while self.peek() is Some(byte) &&
        byte != b'.' &&
        byte != b'[' &&
        byte != b']' {
    self.offset += 1
  }
  guard start < self.offset else { return None }
  let segment = @utf8.decode(self.bytes[start:self.offset].to_owned()) catch {
    _ => return None
  }
  guard is_variable_path_segment(segment) else { return None }
  Some(segment)
}

///|
fn VariablePathCursor::take_number(self : VariablePathCursor) -> Int? {
  let start = self.offset
  while self.peek() is Some(byte) && byte >= b'0' && byte <= b'9' {
    self.offset += 1
  }
  guard start < self.offset else { return None }
  let digits = @utf8.decode(self.bytes[start:self.offset].to_owned()) catch {
    _ => return None
  }
  let parsed = Some(@string.parse_int(digits, base=10)) catch { _ => None }
  guard parsed is Some(index) && index >= 0 else { return None }
  Some(index)
}

///|
pub fn VariablePath::parse(arguments : StringView) -> VariablePath? {
  guard arguments.length() <= 4096 else { return None }
  let cursor = VariablePathCursor::new(arguments)
  guard cursor.take_identifier() is Some(root) else { return None }
  let steps : Array[VariablePathStep] = []
  while !cursor.is_at_end() {
    guard steps.length() < 64 else { return None }
    match cursor.peek() {
      Some(b'.') => {
        cursor.offset += 1
        guard cursor.take_identifier() is Some(field) else { return None }
        steps.push(Field(field))
      }
      Some(b'[') => {
        cursor.offset += 1
        guard cursor.take_number() is Some(index) else { return None }
        if cursor.peek() == Some(b':') {
          cursor.offset += 1
          guard cursor.take_number() is Some(end) &&
            end >= index &&
            cursor.peek() == Some(b']') else {
            return None
          }
          cursor.offset += 1
          guard cursor.is_at_end() else { return None }
          return Some(VariablePath::new(root, steps).with_range(index, end))
        }
        guard cursor.peek() == Some(b']') else { return None }
        cursor.offset += 1
        steps.push(Index(index))
      }
      _ => return None
    }
  }
  Some(VariablePath::new(root, steps))
}
