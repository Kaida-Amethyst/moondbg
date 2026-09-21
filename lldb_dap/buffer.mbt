///|
pub suberror BufferInspectionError {
  BufferInspectionError(String)
} derive(Debug)

///|
pub extend BufferInspectionError with @debug.Debug::{to_repr}

///|
priv struct BufferLayout {
  kind : @runtime_value.BufferKind
  pointer : String
  length : Int
}

///|
fn DapVariable::buffer_kind(self : DapVariable) -> @runtime_value.BufferKind? {
  self.type_name.bind(@runtime_value.buffer_kind)
}

///|
// LLDB appends a C string summary to some pointer values. Only the address is
// consumed: summaries can stop at NUL and are never used as buffer content.
fn buffer_pointer(value : String) -> String? {
  let text = value.trim()
  let address = match text.split_once(" ") {
    Some((address, _)) => address.to_owned()
    None => text.to_owned()
  }
  match parse_native_payload_pointer(address) {
    Some(PayloadPointer(pointer)) => Some(pointer)
    _ => None
  }
}

///|
async fn VariableInspector::buffer_layout(
  self : VariableInspector,
  identity : VariableCacheIdentity,
  variable : DapVariable,
) -> BufferLayout {
  guard variable.buffer_kind() is Some(kind) else {
    raise BufferInspectionError("Ranges require String or Bytes")
  }
  guard variable.is_available() && variable.variables_reference > 0 else {
    raise BufferInspectionError(
      "\{kind.type_name()} has no readable debug location",
    )
  }
  let children = self.load_variables(identity, variable.variables_reference)
  guard children.named_child("body") is Some(body) &&
    buffer_pointer(body.value) is Some(pointer) else {
    raise BufferInspectionError("\{kind.type_name()} has no valid body address")
  }
  let header = self.read_buffer_memory(
    pointer,
    @runtime_value.NATIVE_ARRAY_HEADER_OFFSET,
    @runtime_value.NATIVE_ARRAY_HEADER_SIZE,
  )
  let length = @runtime_value.decode_native_array_capacity(header) catch {
    error =>
      raise BufferInspectionError(
        "Invalid buffer header: \{@debug.to_string(error)}",
      )
  }
  self.ensure_variable_identity(identity)
  { kind, pointer, length, }
}

///|
async fn VariableInspector::read_buffer_memory(
  self : VariableInspector,
  pointer : String,
  offset : Int,
  count : Int,
) -> Bytes {
  guard json_bool_field(self.capabilities, "supportsReadMemoryRequest") ==
    Some(true) else {
    raise BufferInspectionError("lldb-dap does not support readMemory")
  }
  // A negative adapter reply means this value cannot be read, not that the
  // transport failed. Errors while awaiting a reply still propagate normally.
  let response = self.request_allow_failure("readMemory", {
    "memoryReference": pointer,
    "offset": offset,
    "count": count,
  })
  let _ = validate_response(response, "readMemory") catch {
    RequestFailed(message~, ..) =>
      raise BufferInspectionError("Memory read failed: \{message}")
    error => raise error
  }
  decode_memory_reply(response.body(), count) catch {
    InvalidIndexedCollectionValue(message) =>
      raise BufferInspectionError("Memory read failed: \{message}")
    error => raise error
  }
}

///|
async fn VariableInspector::buffer_preview(
  self : VariableInspector,
  identity : VariableCacheIdentity,
  layout : BufferLayout,
  range : (Int, Int)?,
  automatic? : Bool = false,
) -> @runtime_value.BufferPreview {
  let (start, end) = range.unwrap_or(
    (0, layout.length.min(layout.kind.page_size())),
  )
  guard start >= 0 && end >= start && end <= layout.length else {
    raise BufferInspectionError(
      "Range [\{start}:\{end}] is outside length \{layout.length} \{layout.kind.unit_name()}",
    )
  }
  guard end - start <= 1024 else {
    raise BufferInspectionError(
      "Read at most 1024 \{layout.kind.unit_name()} per range",
    )
  }
  // Automatic pages carry a surrogate pair together. Explicit ranges remain
  // exact and expose isolated code units as escapes instead of losing data.
  let align = (automatic || range is None) &&
    layout.kind is @runtime_value.StringBuffer &&
    start < end
  let read_start = if align { (start - 1).max(0) } else { start }
  let read_end = if align && end < layout.length { end + 1 } else { end }
  let offset = read_start.to_int64() * layout.kind.width().to_int64()
  guard offset <= 2147483647L else {
    raise BufferInspectionError("Buffer offset exceeds supported memory range")
  }
  let bytes = if start == end {
    b""
  } else {
    self.read_buffer_memory(
      layout.pointer,
      offset.to_int(),
      (read_end - read_start) * layout.kind.width(),
    )
  }
  self.ensure_variable_identity(identity)
  let first = if align &&
    start > 0 &&
    @runtime_value.is_high_surrogate(
      @runtime_value.utf16_unit(bytes, start - read_start - 1),
    ) &&
    @runtime_value.is_low_surrogate(
      @runtime_value.utf16_unit(bytes, start - read_start),
    ) {
    start - 1
  } else {
    start
  }
  let last = if align &&
    end < layout.length &&
    @runtime_value.is_high_surrogate(
      @runtime_value.utf16_unit(bytes, end - read_start - 1),
    ) &&
    @runtime_value.is_low_surrogate(
      @runtime_value.utf16_unit(bytes, end - read_start),
    ) {
    end - 1
  } else {
    end
  }
  let content = bytes[(first - read_start) * layout.kind.width():(
    last - read_start
  ) *
  layout.kind.width()].to_owned()
  @runtime_value.BufferPreview::new(
    layout.kind,
    layout.length,
    first,
    last,
    content,
  )
}

///|
async fn VariableInspector::buffer_snapshot(
  self : VariableInspector,
  identity : VariableCacheIdentity,
  variable : DapVariable,
  name : String,
  range : (Int, Int)?,
) -> @debugger.VariableSnapshot {
  let layout = self.buffer_layout(identity, variable)
  let preview = self.buffer_preview(identity, layout, range)
  @debugger.VariableSnapshot::new(
    name,
    preview.summary(),
    Some(layout.kind.type_name()),
  )
}
