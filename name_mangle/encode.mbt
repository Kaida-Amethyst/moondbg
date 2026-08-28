///|
let lower_hex_digits : FixedArray[Char] = [
  '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'a', 'b', 'c', 'd', 'e', 'f',
]

///|
fn is_ascii_alphanumeric(byte : Byte) -> Bool {
  (byte >= b'A' && byte <= b'Z') ||
  (byte >= b'a' && byte <= b'z') ||
  (byte >= b'0' && byte <= b'9')
}

///|
fn escaped_identifier(identifier : StringView) -> String {
  let output = StringBuilder(size_hint=identifier.length())
  for byte in @utf8.encode(identifier) {
    match byte {
      b'_' => output.write_string("__")
      b'-' => output.write_string("_2d")
      byte if is_ascii_alphanumeric(byte) =>
        output.write_char(byte.to_int().unsafe_to_char())
      byte => {
        let value = byte.to_int()
        output.write_char('_')
        output.write_char(lower_hex_digits[value >> 4])
        output.write_char(lower_hex_digits[value & 0x0f])
      }
    }
  }
  output.to_string()
}

///|
fn encode_identifier(identifier : StringView) -> String raise NameMangleError {
  guard identifier != "" else {
    raise InvalidIdentifier("identifier must not be empty")
  }
  let escaped = escaped_identifier(identifier)
  "\{escaped.length()}\{escaped}"
}

///|
fn package_segments(
  package_name : StringView,
) -> Array[String] raise NameMangleError {
  let segments = package_name
    .split("/")
    .map(segment => segment.to_owned())
    .to_array()
  for segment in segments {
    guard segment != "" else {
      raise InvalidPackage("package path contains an empty segment")
    }
  }
  segments
}

///|
fn encode_package(package_name : StringView) -> String raise NameMangleError {
  if package_name == "" {
    return "P0"
  }
  if package_name == "moonbitlang/core/builtin" {
    return "PB"
  }
  let core_prefix = "moonbitlang/core/"
  let (marker, segments) = if package_name.has_prefix(core_prefix) {
    ("PC", package_segments(package_name[core_prefix.length():]))
  } else {
    ("P", package_segments(package_name))
  }
  let output = StringBuilder(size_hint=package_name.length() + 8)
  output.write_string(marker)
  output.write_string(segments.length().to_string())
  for segment in segments {
    output.write_string(encode_identifier(segment))
  }
  output.to_string()
}

///|
/// Mangles the common physical-name base of a MoonBit v0 top-level function.
///
/// A monomorphic function uses this string as its complete physical name.
/// Generic and error-polymorphic instantiations append `G...E` and/or `H...`.
pub fn mangle_top_level_function_base(
  package_name : StringView,
  function_name : StringView,
) -> String raise NameMangleError {
  "_M0F\{encode_package(package_name)}\{encode_identifier(function_name)}"
}
