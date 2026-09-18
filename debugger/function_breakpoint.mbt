///|
/// A source-level request for one top-level MoonBit function.
///
/// Package aliases stay unresolved until DebugSession applies the build-system
/// DebugContext. Physical native symbols are intentionally absent here.
pub enum FunctionBreakpointRequest {
  CurrentPackageFunction(String)
  ImportedPackageFunction(String, String)
} derive(Debug, Eq)

///|
pub extend FunctionBreakpointRequest with @debug.Debug::{to_repr}

///|
pub extend FunctionBreakpointRequest with Eq::{equal, not_equal}

///|
pub fn FunctionBreakpointRequest::current(
  function_name : String,
) -> FunctionBreakpointRequest {
  CurrentPackageFunction(function_name)
}

///|
pub fn FunctionBreakpointRequest::imported(
  package_alias : String,
  function_name : String,
) -> FunctionBreakpointRequest {
  ImportedPackageFunction(package_alias, function_name)
}

///|
pub fn FunctionBreakpointRequest::display_name(
  self : FunctionBreakpointRequest,
) -> String {
  match self {
    CurrentPackageFunction(function_name) => function_name
    ImportedPackageFunction(package_alias, function_name) =>
      "@\{package_alias}.\{function_name}"
  }
}

///|
/// Backend-independent physical matching strategy for a function breakpoint.
pub enum FunctionBreakpointSelector {
  ExactPhysicalFunction(String)
  MoonBitFunctionFamily(String)
} derive(Debug, Eq)

///|
pub extend FunctionBreakpointSelector with @debug.Debug::{to_repr}

///|
pub extend FunctionBreakpointSelector with Eq::{equal, not_equal}

///|
pub fn FunctionBreakpointSelector::exact_physical(
  physical_name : String,
) -> FunctionBreakpointSelector {
  ExactPhysicalFunction(physical_name)
}

///|
pub fn FunctionBreakpointSelector::family(
  mangled_base : String,
) -> FunctionBreakpointSelector {
  MoonBitFunctionFamily(mangled_base)
}

///|
/// A stable application-level function breakpoint after package and native
/// symbol resolution. Adapter-specific breakpoint identifiers are not stored.
pub struct FunctionBreakpoint {
  priv id : Int
  priv display_name : String
  priv selector : FunctionBreakpointSelector
  priv enabled : Bool
}

///|
fn FunctionBreakpoint::new(
  id : Int,
  display_name : String,
  selector : FunctionBreakpointSelector,
) -> FunctionBreakpoint {
  { id, display_name, selector, enabled: true, }
}

///|
pub fn FunctionBreakpoint::enabled(self : FunctionBreakpoint) -> Bool {
  self.enabled
}

///|
fn FunctionBreakpoint::with_enabled(
  self : FunctionBreakpoint,
  enabled : Bool,
) -> FunctionBreakpoint {
  { ..self, enabled, }
}

///|
pub fn FunctionBreakpoint::id(self : FunctionBreakpoint) -> Int {
  self.id
}

///|
pub fn FunctionBreakpoint::display_name(self : FunctionBreakpoint) -> String {
  self.display_name
}

///|
pub fn FunctionBreakpoint::selector(
  self : FunctionBreakpoint,
) -> FunctionBreakpointSelector {
  self.selector
}

///|
fn FunctionBreakpoint::pending_snapshot(
  self : FunctionBreakpoint,
) -> FunctionBreakpointSnapshot {
  FunctionBreakpointSnapshot::pending(self.id, self.display_name)
}

///|
pub struct FunctionBreakpointSnapshot {
  priv id : Int
  priv display_name : String
  priv location_count : Int?
  priv status : BreakpointStatus
  priv locations : Array[BreakpointLocation]
}

///|
pub fn FunctionBreakpointSnapshot::pending(
  id : Int,
  display_name : String,
) -> FunctionBreakpointSnapshot {
  { id, display_name, location_count: None, status: Pending, locations: [], }
}

///|
pub fn FunctionBreakpointSnapshot::verified(
  id : Int,
  display_name : String,
  location_count? : Int? = None,
) -> FunctionBreakpointSnapshot {
  { id, display_name, location_count, status: Verified, locations: [], }
}

///|
pub fn FunctionBreakpointSnapshot::rejected(
  id : Int,
  display_name : String,
  message : String,
  location_count? : Int? = None,
) -> FunctionBreakpointSnapshot {
  {
    id,
    display_name,
    location_count,
    status: Rejected(message),
    locations: [],
  }
}

///|
pub fn FunctionBreakpointSnapshot::with_locations(
  self : FunctionBreakpointSnapshot,
  locations : Array[BreakpointLocation],
) -> FunctionBreakpointSnapshot {
  { ..self, locations: locations.copy(), }
}

///|
pub fn FunctionBreakpointSnapshot::locations(
  self : FunctionBreakpointSnapshot,
) -> Array[BreakpointLocation] {
  self.locations.copy()
}

///|
pub fn FunctionBreakpointSnapshot::id(self : FunctionBreakpointSnapshot) -> Int {
  self.id
}

///|
pub fn FunctionBreakpointSnapshot::display_name(
  self : FunctionBreakpointSnapshot,
) -> String {
  self.display_name
}

///|
pub fn FunctionBreakpointSnapshot::status(
  self : FunctionBreakpointSnapshot,
) -> BreakpointStatus {
  self.status
}

///|
pub fn FunctionBreakpointSnapshot::location_count(
  self : FunctionBreakpointSnapshot,
) -> Int? {
  self.location_count
}
