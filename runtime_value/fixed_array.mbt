///|
pub(all) suberror NativeValueError {
  InvalidFixedArrayHeaderSize(Int)
  InvalidFixedArrayLength(UInt)
  InvalidFixedArrayPreviewBudget(Int)
  InvalidScalarPayload(expected~ : Int, actual~ : Int)
  InvalidBoolValue(UInt)
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
pub(all) enum FixedArrayElementType {
  FixedArrayScalar(NativeScalarType)
  FixedArrayOpaque(String)
} derive(Eq, Debug)

///|
pub extend FixedArrayElementType with Eq::{equal, not_equal}

///|
pub extend FixedArrayElementType with @debug.Debug::{to_repr}

///|
pub fn FixedArrayElementType::source_name(
  self : FixedArrayElementType,
) -> String {
  match self {
    FixedArrayScalar(scalar) => scalar.source_name()
    FixedArrayOpaque(name) => name
  }
}

///|
fn scalar_type_from_debug_name(name : String) -> NativeScalarType? {
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
  match name {
    "moonbit_string_t" => "String"
    "moonbit_bytes_t" => "Bytes"
    _ =>
      match name.rev_split_once("/") {
        Some((_, short_name)) if short_name != "" => short_name.to_owned()
        _ => name.to_owned()
      }
  }
}

///|
/// Interprets the raw DAP type of a FixedArray `body` field. The final pointer
/// belongs to the array payload; any remaining pointer belongs to the source
/// element representation.
pub fn fixed_array_element_from_pointer_type(
  pointer_type : String,
) -> FixedArrayElementType? {
  guard pointer_type.trim().strip_suffix("*") is Some(element_debug_type) else {
    return None
  }
  let element_debug_type = element_debug_type.trim().to_owned()
  match scalar_type_from_debug_name(element_debug_type) {
    Some(scalar) => Some(FixedArrayScalar(scalar))
    None => {
      let source_name = opaque_source_name(element_debug_type)
      guard source_name != "" else { return None }
      Some(FixedArrayOpaque(source_name))
    }
  }
}

///|
pub const NATIVE_FIXED_ARRAY_HEADER_SIZE : Int = 8

///|
pub const NATIVE_FIXED_ARRAY_HEADER_OFFSET : Int = -8

///|
pub const MAX_FIXED_ARRAY_PREVIEW_ELEMENTS : Int = 16

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
pub fn decode_fixed_array_length(header : Bytes) -> Int raise NativeValueError {
  guard header.length() == NATIVE_FIXED_ARRAY_HEADER_SIZE else {
    raise InvalidFixedArrayHeaderSize(header.length())
  }
  let length = read_uint32_le(header, 4)
  guard length <= 0x7fff_ffff else { raise InvalidFixedArrayLength(length) }
  length.reinterpret_as_int()
}

///|
pub struct FixedArrayPreviewPlan {
  priv total_length : Int
  priv head_count : Int
  priv tail_index : Int?
} derive(Eq, Debug)

///|
pub extend FixedArrayPreviewPlan with Eq::{equal, not_equal}

///|
pub extend FixedArrayPreviewPlan with @debug.Debug::{to_repr}

///|
pub fn FixedArrayPreviewPlan::new(
  total_length : Int,
  max_elements? : Int = MAX_FIXED_ARRAY_PREVIEW_ELEMENTS,
) -> FixedArrayPreviewPlan raise NativeValueError {
  guard total_length >= 0 else {
    raise InvalidFixedArrayLength(total_length.reinterpret_as_uint())
  }
  guard max_elements >= 2 else {
    raise InvalidFixedArrayPreviewBudget(max_elements)
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
pub fn FixedArrayPreviewPlan::total_length(self : FixedArrayPreviewPlan) -> Int {
  self.total_length
}

///|
pub fn FixedArrayPreviewPlan::head_count(self : FixedArrayPreviewPlan) -> Int {
  self.head_count
}

///|
pub fn FixedArrayPreviewPlan::tail_index(self : FixedArrayPreviewPlan) -> Int? {
  self.tail_index
}

///|
pub fn FixedArrayPreviewPlan::selected_count(
  self : FixedArrayPreviewPlan,
) -> Int {
  self.head_count + (if self.tail_index is Some(_) { 1 } else { 0 })
}

///|
pub fn FixedArrayPreviewPlan::tail_byte_offset(
  self : FixedArrayPreviewPlan,
  element_width : Int,
) -> Int? raise NativeValueError {
  guard self.tail_index is Some(index) else { return None }
  guard element_width > 0 && index <= 0x7fff_ffff / element_width else {
    raise InvalidFixedArrayLength(self.total_length.reinterpret_as_uint())
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
