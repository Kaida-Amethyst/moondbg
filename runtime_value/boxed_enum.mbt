///|
pub const NATIVE_ENUM_DESCRIPTOR_OFFSET : Int = -4

///|
pub const NATIVE_ENUM_DESCRIPTOR_SIZE : Int = 4

///|
/// Extracts the active constructor tag from the low eight bits of MoonBit's
/// boxed-enum descriptor. Higher descriptor bits belong to runtime metadata.
pub fn decode_boxed_enum_tag(descriptor : Bytes) -> Int raise NativeValueError {
  guard descriptor.length() == NATIVE_ENUM_DESCRIPTOR_SIZE else {
    raise InvalidEnumDescriptorSize(descriptor.length())
  }
  descriptor[0].to_int()
}
