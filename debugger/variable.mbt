///|
pub(all) suberror VariableSnapshotError {
  InvalidIndexedCollectionElementType(String)
  InvalidIndexedCollectionLength(Int)
  InvalidIndexedCollectionIndex(index~ : Int, total_length~ : Int)
  UnorderedIndexedCollectionIndex(previous~ : Int, index~ : Int)
  InvalidEnumConstructor(String)
  InvalidEnumPayloadType(position~ : Int, type_name~ : String)
  InvalidEnumPayloadPosition(expected~ : Int, actual~ : Int)
} derive(Eq, Debug)

///|
pub extend VariableSnapshotError with Eq::{equal, not_equal}

///|
pub extend VariableSnapshotError with @debug.Debug::{to_repr}

///|
pub struct VariableStructureSnapshot {
  priv children : Array[VariableSnapshot]
  priv truncated : Bool
} derive(Eq, Debug)

///|
pub extend VariableStructureSnapshot with Eq::{equal, not_equal}

///|
pub extend VariableStructureSnapshot with @debug.Debug::{to_repr}

///|
fn VariableStructureSnapshot::new(
  children : Array[VariableSnapshot],
  truncated : Bool,
) -> VariableStructureSnapshot {
  { children: children.copy(), truncated, }
}

///|
pub fn VariableStructureSnapshot::children(
  self : VariableStructureSnapshot,
) -> ReadOnlyArray[VariableSnapshot] {
  ReadOnlyArray::from_array(self.children)
}

///|
pub fn VariableStructureSnapshot::is_truncated(
  self : VariableStructureSnapshot,
) -> Bool {
  self.truncated
}

///|
pub struct IndexedVariableElement {
  priv index : Int
  priv value : VariableSnapshot?
} derive(Eq, Debug)

///|
pub extend IndexedVariableElement with Eq::{equal, not_equal}

///|
pub extend IndexedVariableElement with @debug.Debug::{to_repr}

///|
pub fn IndexedVariableElement::with_value(
  index : Int,
  value : VariableSnapshot,
) -> IndexedVariableElement {
  { index, value: Some(value), }
}

///|
pub fn IndexedVariableElement::placeholder(
  index : Int,
) -> IndexedVariableElement {
  { index, value: None, }
}

///|
pub fn IndexedVariableElement::index(self : IndexedVariableElement) -> Int {
  self.index
}

///|
pub fn IndexedVariableElement::value(
  self : IndexedVariableElement,
) -> VariableSnapshot? {
  self.value
}

///|
/// The source-level MoonBit collection represented by an indexed preview.
pub(all) enum IndexedCollectionKind {
  FixedArrayCollection
  ArrayCollection
} derive(Eq, Debug)

///|
pub extend IndexedCollectionKind with Eq::{equal, not_equal}

///|
pub extend IndexedCollectionKind with @debug.Debug::{to_repr}

///|
pub fn IndexedCollectionKind::source_name(
  self : IndexedCollectionKind,
) -> String {
  match self {
    FixedArrayCollection => "FixedArray"
    ArrayCollection => "Array"
  }
}

///|
pub struct IndexedCollectionSnapshot {
  priv kind : IndexedCollectionKind
  priv element_type_name : String
  priv total_length : Int
  priv preview_elements : Array[IndexedVariableElement]
} derive(Eq, Debug)

///|
pub extend IndexedCollectionSnapshot with Eq::{equal, not_equal}

///|
pub extend IndexedCollectionSnapshot with @debug.Debug::{to_repr}

///|
pub fn IndexedCollectionSnapshot::new(
  kind : IndexedCollectionKind,
  element_type_name : String,
  total_length : Int,
  preview_elements : Array[IndexedVariableElement],
) -> IndexedCollectionSnapshot raise VariableSnapshotError {
  guard element_type_name.trim() != "" else {
    raise InvalidIndexedCollectionElementType(element_type_name)
  }
  guard total_length >= 0 else {
    raise InvalidIndexedCollectionLength(total_length)
  }
  let mut previous_index : Int? = None
  for element in preview_elements {
    let index = element.index()
    guard index >= 0 && index < total_length else {
      raise InvalidIndexedCollectionIndex(index~, total_length~)
    }
    match previous_index {
      Some(previous) if index <= previous =>
        raise UnorderedIndexedCollectionIndex(previous~, index~)
      _ => previous_index = Some(index)
    }
  }
  {
    kind,
    element_type_name,
    total_length,
    preview_elements: preview_elements.copy(),
  }
}

///|
pub fn IndexedCollectionSnapshot::kind(
  self : IndexedCollectionSnapshot,
) -> IndexedCollectionKind {
  self.kind
}

///|
pub fn IndexedCollectionSnapshot::element_type_name(
  self : IndexedCollectionSnapshot,
) -> String {
  self.element_type_name
}

///|
pub fn IndexedCollectionSnapshot::total_length(
  self : IndexedCollectionSnapshot,
) -> Int {
  self.total_length
}

///|
pub fn IndexedCollectionSnapshot::preview_elements(
  self : IndexedCollectionSnapshot,
) -> ReadOnlyArray[IndexedVariableElement] {
  ReadOnlyArray::from_array(self.preview_elements)
}

///|
pub fn IndexedCollectionSnapshot::omitted_count(
  self : IndexedCollectionSnapshot,
) -> Int {
  self.total_length - self.preview_elements.length()
}

///|
pub fn IndexedCollectionSnapshot::is_complete(
  self : IndexedCollectionSnapshot,
) -> Bool {
  self.omitted_count() == 0
}

///|
/// One direct payload slot in an active MoonBit enum constructor.
///
/// The position is source-facing; this snapshot is not used to resolve paths.
/// A missing scalar value means the payload is represented by its source type
/// only; it does not mean that adapter children remain available.
pub struct VariableEnumPayload {
  priv position : Int
  priv type_name : String
  priv scalar_value : String?
} derive(Eq, Debug)

///|
pub extend VariableEnumPayload with Eq::{equal, not_equal}

///|
pub extend VariableEnumPayload with @debug.Debug::{to_repr}

///|
pub fn VariableEnumPayload::scalar(
  position : Int,
  type_name : String,
  value : String,
) -> VariableEnumPayload {
  { position, type_name, scalar_value: Some(value), }
}

///|
pub fn VariableEnumPayload::aggregate(
  position : Int,
  type_name : String,
) -> VariableEnumPayload {
  { position, type_name, scalar_value: None, }
}

///|
pub fn VariableEnumPayload::position(self : VariableEnumPayload) -> Int {
  self.position
}

///|
pub fn VariableEnumPayload::type_name(self : VariableEnumPayload) -> String {
  self.type_name
}

///|
pub fn VariableEnumPayload::scalar_value(self : VariableEnumPayload) -> String? {
  self.scalar_value
}

///|
pub struct VariableEnumSnapshot {
  priv constructor_name : String
  priv payload : Array[VariableEnumPayload]
  priv preview : String?
} derive(Eq, Debug)

///|
pub extend VariableEnumSnapshot with Eq::{equal, not_equal}

///|
pub extend VariableEnumSnapshot with @debug.Debug::{to_repr}

///|
pub fn VariableEnumSnapshot::new(
  constructor_name : String,
  payload : Array[VariableEnumPayload],
  preview? : String,
) -> VariableEnumSnapshot raise VariableSnapshotError {
  guard constructor_name.trim() != "" else {
    raise InvalidEnumConstructor(constructor_name)
  }
  for index, element in payload {
    guard element.position() == index else {
      raise InvalidEnumPayloadPosition(
        expected=index,
        actual=element.position(),
      )
    }
    guard element.type_name().trim() != "" else {
      raise InvalidEnumPayloadType(
        position=element.position(),
        type_name=element.type_name(),
      )
    }
  }
  { constructor_name, payload: payload.copy(), preview, }
}

///|
/// Bounded automatic presentation; never used to resolve paths or evaluate conditions.
pub fn VariableEnumSnapshot::preview(self : VariableEnumSnapshot) -> String? {
  self.preview
}

///|
pub fn VariableEnumSnapshot::constructor_name(
  self : VariableEnumSnapshot,
) -> String {
  self.constructor_name
}

///|
/// A bounded payload prefix. The preview carries any omission marker; explicit
/// positional lookup re-reads the source value, not this presentation snapshot.
pub fn VariableEnumSnapshot::payload(
  self : VariableEnumSnapshot,
) -> ReadOnlyArray[VariableEnumPayload] {
  ReadOnlyArray::from_array(self.payload)
}

///|
pub enum VariableContent {
  VariableLeaf
  VariableStructure(VariableStructureSnapshot)
  VariableTuple(VariableStructureSnapshot)
  VariableIndexedCollection(IndexedCollectionSnapshot)
  VariableEnum(VariableEnumSnapshot)
} derive(Eq, Debug)

///|
pub extend VariableContent with Eq::{equal, not_equal}

///|
pub extend VariableContent with @debug.Debug::{to_repr}

///|
pub struct VariableSnapshot {
  priv name : String
  priv value : String
  priv type_name : String?
  priv content : VariableContent
} derive(Eq, Debug)

///|
pub extend VariableSnapshot with Eq::{equal, not_equal}

///|
pub extend VariableSnapshot with @debug.Debug::{to_repr}

///|
/// Creates a debugger-domain variable value with no adapter reference.
pub fn VariableSnapshot::new(
  name : String,
  value : String,
  type_name : String?,
) -> VariableSnapshot {
  { name, value, type_name, content: VariableLeaf, }
}

///|
pub fn VariableSnapshot::tuple(
  name : String,
  type_name : String?,
  children : Array[VariableSnapshot],
  truncated~ : Bool,
) -> VariableSnapshot {
  {
    name,
    value: "",
    type_name,
    content: VariableTuple(VariableStructureSnapshot::new(children, truncated)),
  }
}

///|
/// Creates a debugger-domain variable whose structure was fully materialized.
pub fn VariableSnapshot::expanded(
  name : String,
  value : String,
  type_name : String?,
  children : Array[VariableSnapshot],
) -> VariableSnapshot {
  {
    name,
    value,
    type_name,
    content: VariableStructure(VariableStructureSnapshot::new(children, false)),
  }
}

///|
/// Creates a debugger-domain structure whose remaining children were omitted.
pub fn VariableSnapshot::truncated(
  name : String,
  value : String,
  type_name : String?,
  children : Array[VariableSnapshot],
) -> VariableSnapshot {
  {
    name,
    value,
    type_name,
    content: VariableStructure(VariableStructureSnapshot::new(children, true)),
  }
}

///|
/// Creates a debugger-domain indexed collection with an adapter-free preview.
pub fn VariableSnapshot::indexed_collection(
  name : String,
  value : String,
  type_name : String?,
  collection : IndexedCollectionSnapshot,
) -> VariableSnapshot {
  { name, value, type_name, content: VariableIndexedCollection(collection), }
}

///|
/// Creates a debugger-domain enum value without retaining an adapter pointer.
pub fn VariableSnapshot::enum_value(
  name : String,
  type_name : String?,
  enum_value : VariableEnumSnapshot,
) -> VariableSnapshot {
  { name, value: "", type_name, content: VariableEnum(enum_value), }
}

///|
pub fn VariableSnapshot::name(self : VariableSnapshot) -> String {
  self.name
}

///|
pub fn VariableSnapshot::value(self : VariableSnapshot) -> String {
  self.value
}

///|
pub fn VariableSnapshot::type_name(self : VariableSnapshot) -> String? {
  self.type_name
}

///|
pub fn VariableSnapshot::content(self : VariableSnapshot) -> VariableContent {
  self.content
}

///|
pub using @expression {type VariablePath, type VariablePathStep}

///|
/// A domain-level reason why one variable path could not be inspected.
pub enum VariableLookupFailure {
  VariableRootNotFound(String)
  VariableFieldNotFound(String, String)
  VariableFieldAccessOnNonStruct(String, String, String?)
  VariableIndexAccessOnNonCollection(String, Int, String?)
  VariableIndexOutOfBounds(String, Int, Int)
  VariableUnavailable(String)
  VariableReportedUnavailable(String, String)
  VariableMemoryReadFailed(String, String)
  VariableInspectionFailed(String, String)
} derive(Eq, Debug)

///|
pub extend VariableLookupFailure with Eq::{equal, not_equal}

///|
pub extend VariableLookupFailure with @debug.Debug::{to_repr}

///|
pub fn VariableLookupFailure::requested_path(
  self : VariableLookupFailure,
) -> String {
  match self {
    VariableRootNotFound(root) => root
    VariableFieldNotFound(owner, field) => "\{owner}.\{field}"
    VariableFieldAccessOnNonStruct(owner, field, _) => "\{owner}.\{field}"
    VariableIndexAccessOnNonCollection(owner, index, _) => "\{owner}[\{index}]"
    VariableIndexOutOfBounds(owner, index, _) => "\{owner}[\{index}]"
    VariableUnavailable(path) => path
    VariableReportedUnavailable(path, _) | VariableMemoryReadFailed(path, _) =>
      path
    VariableInspectionFailed(path, _) => path
  }
}

///|
pub enum VariableLookupResult {
  VariableFound(VariableSnapshot)
  VariableLookupFailed(VariableLookupFailure)
} derive(Eq, Debug)

///|
pub extend VariableLookupResult with Eq::{equal, not_equal}

///|
pub extend VariableLookupResult with @debug.Debug::{to_repr}

///|
pub fn VariableLookupResult::found(
  variable : VariableSnapshot,
) -> VariableLookupResult {
  VariableFound(variable)
}

///|
pub fn VariableLookupResult::not_found(name : String) -> VariableLookupResult {
  VariableLookupFailed(VariableRootNotFound(name))
}

///|
pub fn VariableLookupResult::field_not_found(
  owner : String,
  field : String,
) -> VariableLookupResult {
  VariableLookupFailed(VariableFieldNotFound(owner, field))
}

///|
pub fn VariableLookupResult::field_access_on_non_struct(
  owner : String,
  field : String,
  type_name : String?,
) -> VariableLookupResult {
  VariableLookupFailed(VariableFieldAccessOnNonStruct(owner, field, type_name))
}

///|
pub fn VariableLookupResult::index_access_on_non_collection(
  owner : String,
  index : Int,
  type_name : String?,
) -> VariableLookupResult {
  VariableLookupFailed(
    VariableIndexAccessOnNonCollection(owner, index, type_name),
  )
}

///|
pub fn VariableLookupResult::index_out_of_bounds(
  owner : String,
  index : Int,
  total_length : Int,
) -> VariableLookupResult {
  VariableLookupFailed(VariableIndexOutOfBounds(owner, index, total_length))
}

///|
pub fn VariableLookupResult::unavailable(path : String) -> VariableLookupResult {
  VariableLookupFailed(VariableUnavailable(path))
}

///|
pub fn VariableLookupResult::failed(
  failure : VariableLookupFailure,
) -> VariableLookupResult {
  VariableLookupFailed(failure)
}

///|
pub fn VariableLookupFailure::reported_unavailable(
  path : String,
  reason : String,
) -> VariableLookupFailure {
  VariableReportedUnavailable(path, reason)
}

///|
pub fn VariableLookupFailure::memory_read_failed(
  path : String,
  reason : String,
) -> VariableLookupFailure {
  VariableMemoryReadFailed(path, reason)
}

///|
pub fn VariableLookupFailure::inspection_failed(
  path : String,
  reason : String,
) -> VariableLookupFailure {
  VariableInspectionFailed(path, reason)
}

///|
/// A failed read is not a failed debugger session.
pub fn VariableLookupResult::inspection_failed(
  path : String,
  message : String,
) -> VariableLookupResult {
  VariableLookupFailed(VariableInspectionFailed(path, message))
}
