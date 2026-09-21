///|
pub(all) enum BufferKind {
  StringBuffer
  BytesBuffer
} derive(Eq, Debug)

///|
pub extend BufferKind with Eq::{equal, not_equal}

///|
pub extend BufferKind with @debug.Debug::{to_repr}

///|
pub fn BufferKind::type_name(self : BufferKind) -> String {
  match self {
    StringBuffer => "String"
    BytesBuffer => "Bytes"
  }
}

///|
pub fn BufferKind::unit_name(self : BufferKind) -> String {
  match self {
    StringBuffer => "UTF-16 units"
    BytesBuffer => "bytes"
  }
}

///|
pub fn BufferKind::width(self : BufferKind) -> Int {
  match self {
    StringBuffer => 2
    BytesBuffer => 1
  }
}

///|
pub fn BufferKind::page_size(self : BufferKind) -> Int {
  match self {
    StringBuffer => 128
    BytesBuffer => 32
  }
}

///|
pub fn buffer_kind(debug_type : String) -> BufferKind? {
  match debug_type.trim() {
    "moonbit_string_t" | "String" => Some(StringBuffer)
    "moonbit_bytes_t" | "Bytes" => Some(BytesBuffer)
    _ => None
  }
}

///|
pub fn utf16_unit(bytes : Bytes, index : Int) -> Int {
  bytes[index * 2].to_int() | (bytes[index * 2 + 1].to_int() << 8)
}

///|
pub fn is_high_surrogate(unit : Int) -> Bool {
  unit >= 0xD800 && unit <= 0xDBFF
}

///|
pub fn is_low_surrogate(unit : Int) -> Bool {
  unit >= 0xDC00 && unit <= 0xDFFF
}

///|
fn hex_digits(value : Int, width : Int) -> String {
  let alphabet = "0123456789abcdef"
  let output = StringBuilder()
  for i = width - 1; i >= 0; i = i - 1 {
    output.write_char(
      alphabet[(value >> (i * 4)) & 15].to_int().unsafe_to_char(),
    )
  }
  output.to_string()
}

///|
/// Lossless quoted content. No terminal control characters are emitted.
/// Isolated UTF-16 surrogates (including explicit slice boundaries) are escaped.
pub fn quote_buffer(
  kind : BufferKind,
  bytes : Bytes,
) -> String raise NativeValueError {
  guard bytes.length() % kind.width() == 0 else {
    raise InvalidScalarPayload(
      expected=bytes.length() + 1,
      actual=bytes.length(),
    )
  }
  let output = StringBuilder()
  if kind is BytesBuffer {
    output.write_string("b\"")
    for byte in bytes {
      output.write_string("\\x\{hex_digits(byte.to_int(), 2)}")
    }
  } else {
    output.write_char('"')
    let count = bytes.length() / 2
    for index = 0; index < count; {
      let unit = utf16_unit(bytes, index)
      if is_high_surrogate(unit) &&
        index + 1 < count &&
        is_low_surrogate(utf16_unit(bytes, index + 1)) {
        let codepoint = 0x10000 +
          ((unit - 0xD800) << 10) +
          utf16_unit(bytes, index + 1) -
          0xDC00
        output.write_char(codepoint.unsafe_to_char())
        continue index + 2
      }
      match unit {
        0x22 => output.write_string("\\\"")
        0x5C => output.write_string("\\\\")
        0x0A => output.write_string("\\n")
        0x0D => output.write_string("\\r")
        0x09 => output.write_string("\\t")
        _ if is_high_surrogate(unit) ||
          is_low_surrogate(unit) ||
          !unit.unsafe_to_char().is_printable() ||
          unit == 0x2028 ||
          unit == 0x2029 => output.write_string("\\u\{hex_digits(unit, 4)}")
        _ => output.write_char(unit.unsafe_to_char())
      }
      continue index + 1
    }
  }
  output.write_char('"')
  output.to_string()
}

///|
/// Bounded, adapter-free content plus the range within the original buffer.
pub struct BufferPreview {
  kind : BufferKind
  length : Int
  start : Int
  end : Int
  quoted : String
} derive(Eq, Debug)

///|
pub extend BufferPreview with Eq::{equal, not_equal}

///|
pub extend BufferPreview with @debug.Debug::{to_repr}

///|
pub fn BufferPreview::new(
  kind : BufferKind,
  length : Int,
  start : Int,
  end : Int,
  bytes : Bytes,
) -> BufferPreview raise NativeValueError {
  { kind, length, start, end, quoted: quote_buffer(kind, bytes), }
}

///|
pub fn BufferPreview::summary(self : BufferPreview) -> String {
  let suffix = if self.start == 0 && self.end == self.length {
    ""
  } else {
    "; showing [\{self.start}:\{self.end}], truncated; use [start:end]"
  }
  "\{self.quoted} (length = \{self.length} \{self.kind.unit_name()}\{suffix})"
}
