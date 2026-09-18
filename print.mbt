///|
priv struct CommandPrint {
  path : @debugger.VariablePath
}

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
fn VariablePathCursor::take_index(self : VariablePathCursor) -> Int? {
  guard self.peek() == Some(b'[') else { return None }
  self.offset += 1
  let start = self.offset
  while self.peek() is Some(byte) && byte >= b'0' && byte <= b'9' {
    self.offset += 1
  }
  guard start < self.offset && self.peek() == Some(b']') else { return None }
  let digits = @utf8.decode(self.bytes[start:self.offset].to_owned()) catch {
    _ => return None
  }
  self.offset += 1
  let parsed = Some(@string.parse_int(digits, base=10)) catch { _ => None }
  guard parsed is Some(index) && index >= 0 else { return None }
  Some(index)
}

///|
fn parse_variable_path(arguments : StringView) -> @debugger.VariablePath? {
  let cursor = VariablePathCursor::new(arguments)
  guard cursor.take_identifier() is Some(root) else { return None }
  let steps : Array[@debugger.VariablePathStep] = []
  while !cursor.is_at_end() {
    match cursor.peek() {
      Some(b'.') => {
        cursor.offset += 1
        guard cursor.take_identifier() is Some(field) else { return None }
        steps.push(@debugger.Field(field))
      }
      Some(b'[') => {
        guard cursor.take_index() is Some(index) else { return None }
        steps.push(@debugger.Index(index))
      }
      _ => return None
    }
  }
  Some(@debugger.VariablePath::new(root, steps))
}

///|
fn parse_print_command(
  _invoked_name : StringView,
  arguments : StringView,
) -> CommandParseResult {
  guard arguments != "" else {
    return invalid_command("print requires a variable path")
  }
  guard parse_variable_path(arguments) is Some(path) else {
    return invalid_command(
      "print only accepts variable paths with fields and non-negative indices",
    )
  }
  parsed_command(CommandPrint::{ path, })
}

///|
fn print_command_spec() -> CommandSpec {
  CommandSpec::new(
    "print",
    ["p"],
    "print <path>",
    "Show a variable, field, or indexed element path",
    parse_print_command,
  )
}

///|
impl ReplCommand for CommandPrint with fn execute(self, context) {
  let events : Array[PresentationEvent] = []
  let result = context.session.find_variable(self.path) catch {
    @debugger.OperationNotAllowed(state~, action~) => {
      events.push(OperationNotAllowedPresentation(state, action))
      return CommandResult::continuing(events~)
    }
    @debugger.AdapterFailure(message) => {
      append_debuggee_output(events, context.session)
      events.push(AdapterFailurePresentation(message))
      return CommandResult::continuing(events~)
    }
    error => raise error
  }
  append_debuggee_output(events, context.session)
  match result {
    @debugger.VariableFound(variable) =>
      events.push(VariablePresentation(variable))
    @debugger.VariableLookupFailed(failure) =>
      events.push(VariableLookupFailurePresentation(failure))
  }
  CommandResult::continuing(events~)
}
