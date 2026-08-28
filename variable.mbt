///|
pub(all) suberror VariableSnapshotError {
  InvalidIndexedCollectionElementType(String)
  InvalidIndexedCollectionLength(Int)
  InvalidIndexedCollectionIndex(index~ : Int, total_length~ : Int)
  UnorderedIndexedCollectionIndex(previous~ : Int, index~ : Int)
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
pub struct IndexedCollectionSnapshot {
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
    element_type_name,
    total_length,
    preview_elements: preview_elements.copy(),
  }
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
pub enum VariableContent {
  VariableLeaf
  VariableStructure(VariableStructureSnapshot)
  VariableIndexedCollection(IndexedCollectionSnapshot)
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
/// One backend-independent step in a variable lookup path.
pub enum VariablePathStep {
  Field(String)
} derive(Eq, Debug)

///|
pub extend VariablePathStep with Eq::{equal, not_equal}

///|
pub extend VariablePathStep with @debug.Debug::{to_repr}

///|
/// A parsed variable lookup path owned by debugger core.
///
/// Adapter references and expression-evaluator text intentionally do not
/// appear in this value.
pub struct VariablePath {
  priv root : String
  priv steps : Array[VariablePathStep]
} derive(Eq, Debug)

///|
pub extend VariablePath with Eq::{equal, not_equal}

///|
pub extend VariablePath with @debug.Debug::{to_repr}

///|
pub fn VariablePath::root(root : String) -> VariablePath {
  { root, steps: [], }
}

///|
pub fn VariablePath::with_fields(
  root : String,
  fields : Array[String],
) -> VariablePath {
  { root, steps: fields.map(field => Field(field)), }
}

///|
pub fn VariablePath::root_name(self : VariablePath) -> String {
  self.root
}

///|
pub fn VariablePath::steps(
  self : VariablePath,
) -> ReadOnlyArray[VariablePathStep] {
  ReadOnlyArray::from_array(self.steps)
}

///|
pub fn VariablePath::display_name(self : VariablePath) -> String {
  guard self.steps is [_, ..] else { return self.root }
  let fields = self.steps.map(step => {
    match step {
      Field(field) => field
    }
  })
  "\{self.root}.\{fields.join(".")}"
}

///|
/// A domain-level reason why one variable path could not be inspected.
pub enum VariableLookupFailure {
  VariableRootNotFound(String)
  VariableFieldNotFound(String, String)
  VariableFieldAccessOnNonStruct(String, String, String?)
  VariableUnavailable(String)
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
    VariableUnavailable(path) => path
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
pub fn VariableLookupResult::unavailable(path : String) -> VariableLookupResult {
  VariableLookupFailed(VariableUnavailable(path))
}
