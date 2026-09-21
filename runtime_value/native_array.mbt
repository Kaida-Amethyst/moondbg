///|
pub(all) suberror NativeValueError {
  InvalidNativeArrayHeaderSize(Int)
  InvalidNativeArrayCapacity(UInt)
  InvalidIndexedCollectionLength(Int)
  InvalidArrayLength(length~ : Int, capacity~ : Int)
  InvalidIndexedPreviewBudget(Int)
  InvalidScalarPayload(expected~ : Int, actual~ : Int)
  InvalidBoolValue(UInt)
  InvalidEnumDescriptorSize(Int)
} derive(Eq, Debug)

///|
pub extend NativeValueError with Eq::{equal, not_equal}

///|
pub extend NativeValueError with @debug.Debug::{to_repr}

///|
pub(all) enum NativeScalarType {
  NativeBool
  NativeInt
  NativeUInt
  NativeInt64
  NativeUInt64
  NativeFloat
  NativeDouble
} derive(Eq, Debug)

///|
pub extend NativeScalarType with Eq::{equal, not_equal}

///|
pub extend NativeScalarType with @debug.Debug::{to_repr}

///|
pub fn NativeScalarType::source_name(self : NativeScalarType) -> String {
  match self {
    NativeBool => "Bool"
    NativeInt => "Int"
    NativeUInt => "UInt"
    NativeInt64 => "Int64"
    NativeUInt64 => "UInt64"
    NativeFloat => "Float"
    NativeDouble => "Double"
  }
}

///|
pub fn NativeScalarType::byte_width(self : NativeScalarType) -> Int {
  match self {
    NativeBool => 1
    NativeInt | NativeUInt | NativeFloat => 4
    NativeInt64 | NativeUInt64 | NativeDouble => 8
  }
}

///|
pub(all) enum NativeArrayElementType {
  NativeArrayScalar(NativeScalarType)
  NativeArrayOpaque(String)
} derive(Eq, Debug)

///|
pub extend NativeArrayElementType with Eq::{equal, not_equal}

///|
pub extend NativeArrayElementType with @debug.Debug::{to_repr}

///|
pub fn NativeArrayElementType::source_name(
  self : NativeArrayElementType,
) -> String {
  match self {
    NativeArrayScalar(scalar) => scalar.source_name()
    NativeArrayOpaque(name) => name
  }
}

///|
pub fn native_scalar_from_debug_type(name : String) -> NativeScalarType? {
  match name {
    "Bool" | "bool" | "_Bool" => Some(NativeBool)
    "Int" | "int" | "int32_t" => Some(NativeInt)
    "UInt" | "unsigned" | "unsigned int" | "uint32_t" => Some(NativeUInt)
    "Int64" | "long" | "long long" | "int64_t" => Some(NativeInt64)
    "UInt64" | "unsigned long" | "unsigned long long" | "uint64_t" =>
      Some(NativeUInt64)
    "Float" | "float" => Some(NativeFloat)
    "Double" | "double" => Some(NativeDouble)
    _ => None
  }
}

///|
fn opaque_source_name(debug_name : String) -> String {
  let mut name = debug_name.trim()
  while name.strip_suffix("*") is Some(without_pointer) {
    name = without_pointer.trim()
  }
  while name.strip_suffix(" &") is Some(without_reference) {
    name = without_reference.trim()
  }
  if native_scalar_from_debug_type(name.to_owned()) is Some(scalar) {
    return scalar.source_name()
  }
  let output = StringBuilder()
  let mut start = 0
  for index, ch in name.iter2() {
    if ch is ('[' | ']' | '(' | ')' | ',') {
      output.write_string(short_type_token(name[start:index]))
      output.write_char(ch)
      if ch == ',' {
        output.write_char(' ')
      }
      start = index + 1
    }
  }
  output.write_string(short_type_token(name[start:]))
  output.to_string()
}

///|
fn short_type_token(token : StringView) -> String {
  let token = token.trim()
  match token {
    "moonbit_string_t" => "String"
    "moonbit_bytes_t" => "Bytes"
    _ =>
      match token.rev_split_once("/") {
        Some((_, name)) => name.to_owned()
        None =>
          match native_scalar_from_debug_type(token.to_owned()) {
            Some(scalar) => scalar.source_name()
            None => token.to_owned()
          }
      }
  }
}

///|
/// Reduces a raw debugger type to a source-facing MoonBit name without
/// retaining module paths, pointers, or references.
pub fn source_name_from_debug_type(debug_name : String) -> String? {
  let trimmed = debug_name.trim().to_owned()
  guard trimmed != "" else { return None }
  match trimmed {
    "moonbit.array_i32" | "$moonbit.array_i32" => return Some("FixedArray[Int]")
    "moonbit.array_u32" | "$moonbit.array_u32" =>
      return Some("FixedArray[UInt]")
    "moonbit.array_i64" | "$moonbit.array_i64" =>
      return Some("FixedArray[Int64]")
    "moonbit.array_u64" | "$moonbit.array_u64" =>
      return Some("FixedArray[UInt64]")
    "moonbit.array_f32" | "$moonbit.array_f32" =>
      return Some("FixedArray[Float]")
    "moonbit.array_f64" | "$moonbit.array_f64" =>
      return Some("FixedArray[Double]")
    _ if trimmed.has_prefix("moonbit.array_") ||
      trimmed.has_prefix("$moonbit.array_") => return Some("FixedArray")
    _ => ()
  }
  match native_scalar_from_debug_type(trimmed) {
    Some(scalar) => Some(scalar.source_name())
    None => {
      let source_name = opaque_source_name(trimmed)
      if source_name == "" {
        None
      } else {
        Some(source_name)
      }
    }
  }
}

///|
/// Interprets the raw DAP type of a native array-storage `body` field. The
/// final pointer belongs to the contiguous payload; any remaining pointer
/// belongs to the source element representation.
pub fn native_array_element_from_pointer_type(
  pointer_type : String,
) -> NativeArrayElementType? {
  guard pointer_type.trim().strip_suffix("*") is Some(element_debug_type) else {
    return None
  }
  let element_debug_type = element_debug_type.trim().to_owned()
  match native_scalar_from_debug_type(element_debug_type) {
    Some(scalar) => Some(NativeArrayScalar(scalar))
    None => {
      let source_name = opaque_source_name(element_debug_type)
      guard source_name != "" else { return None }
      Some(NativeArrayOpaque(source_name))
    }
  }
}

///|
pub const NATIVE_ARRAY_HEADER_SIZE : Int = 8

///|
pub const NATIVE_ARRAY_HEADER_OFFSET : Int = -8

///|
pub const MAX_INDEXED_PREVIEW_ELEMENTS : Int = 16

///|
fn read_uint32_le(bytes : Bytes, offset : Int) -> UInt {
  bytes[offset].to_uint() |
  (bytes[offset + 1].to_uint() << 8) |
  (bytes[offset + 2].to_uint() << 16) |
  (bytes[offset + 3].to_uint() << 24)
}

///|
fn read_uint64_le(bytes : Bytes, offset : Int) -> UInt64 {
  bytes[offset].to_uint64() |
  (bytes[offset + 1].to_uint64() << 8) |
  (bytes[offset + 2].to_uint64() << 16) |
  (bytes[offset + 3].to_uint64() << 24) |
  (bytes[offset + 4].to_uint64() << 32) |
  (bytes[offset + 5].to_uint64() << 40) |
  (bytes[offset + 6].to_uint64() << 48) |
  (bytes[offset + 7].to_uint64() << 56)
}

///|
/// Decodes the storage capacity kept immediately before a native array
/// payload. FixedArray uses this value as its source-level length; Array keeps
/// its logical length in a separate field.
pub fn decode_native_array_capacity(
  header : Bytes,
) -> Int raise NativeValueError {
  guard header.length() == NATIVE_ARRAY_HEADER_SIZE else {
    raise InvalidNativeArrayHeaderSize(header.length())
  }
  let capacity = read_uint32_le(header, 4)
  guard capacity <= 0x7fff_ffff else {
    raise InvalidNativeArrayCapacity(capacity)
  }
  capacity.reinterpret_as_int()
}

///|
/// Validates the logical length of a resizable Array against the initialized
/// native storage range. Callers must never read elements between length and
/// capacity.
pub fn validate_array_length(
  length : Int,
  capacity : Int,
) -> Unit raise NativeValueError {
  guard length >= 0 && capacity >= 0 && length <= capacity else {
    raise InvalidArrayLength(length~, capacity~)
  }
}

///|
pub struct IndexedPreviewPlan {
  priv total_length : Int
  priv head_count : Int
  priv tail_index : Int?
} derive(Eq, Debug)

///|
pub extend IndexedPreviewPlan with Eq::{equal, not_equal}

///|
pub extend IndexedPreviewPlan with @debug.Debug::{to_repr}

///|
pub fn IndexedPreviewPlan::new(
  total_length : Int,
  max_elements? : Int = MAX_INDEXED_PREVIEW_ELEMENTS,
) -> IndexedPreviewPlan raise NativeValueError {
  guard total_length >= 0 else {
    raise InvalidIndexedCollectionLength(total_length)
  }
  guard max_elements >= 2 else {
    raise InvalidIndexedPreviewBudget(max_elements)
  }
  if total_length <= max_elements {
    { total_length, head_count: total_length, tail_index: None, }
  } else {
    {
      total_length,
      head_count: max_elements - 1,
      tail_index: Some(total_length - 1),
    }
  }
}

///|
pub fn IndexedPreviewPlan::total_length(self : IndexedPreviewPlan) -> Int {
  self.total_length
}

///|
pub fn IndexedPreviewPlan::head_count(self : IndexedPreviewPlan) -> Int {
  self.head_count
}

///|
pub fn IndexedPreviewPlan::tail_index(self : IndexedPreviewPlan) -> Int? {
  self.tail_index
}

///|
pub fn IndexedPreviewPlan::selected_count(self : IndexedPreviewPlan) -> Int {
  self.head_count + (if self.tail_index is Some(_) { 1 } else { 0 })
}

///|
pub fn IndexedPreviewPlan::tail_byte_offset(
  self : IndexedPreviewPlan,
  element_width : Int,
) -> Int? raise NativeValueError {
  guard self.tail_index is Some(index) else { return None }
  guard element_width > 0 && index <= 0x7fff_ffff / element_width else {
    raise InvalidIndexedCollectionLength(self.total_length)
  }
  Some(index * element_width)
}

///|
fn decode_scalar_at(
  scalar : NativeScalarType,
  payload : Bytes,
  offset : Int,
) -> String raise NativeValueError {
  match scalar {
    NativeBool => {
      let value = payload[offset].to_uint()
      match value {
        0 => "false"
        1 => "true"
        _ => raise InvalidBoolValue(value)
      }
    }
    NativeInt =>
      read_uint32_le(payload, offset).reinterpret_as_int().to_string()
    NativeUInt => read_uint32_le(payload, offset).to_string()
    NativeInt64 =>
      read_uint64_le(payload, offset).reinterpret_as_int64().to_string()
    NativeUInt64 => read_uint64_le(payload, offset).to_string()
    NativeFloat =>
      Float::reinterpret_from_uint(read_uint32_le(payload, offset)).to_string()
    NativeDouble =>
      read_uint64_le(payload, offset).reinterpret_as_double().to_string()
  }
}

///|
pub fn decode_scalar_payload(
  scalar : NativeScalarType,
  payload : Bytes,
  element_count : Int,
) -> Array[String] raise NativeValueError {
  let width = scalar.byte_width()
  guard element_count >= 0 && element_count <= 0x7fff_ffff / width else {
    raise InvalidScalarPayload(expected=0, actual=payload.length())
  }
  let expected = element_count * width
  guard payload.length() == expected else {
    raise InvalidScalarPayload(expected~, actual=payload.length())
  }
  Array::makei(element_count, index => {
    decode_scalar_at(scalar, payload, index * width)
  })
}
