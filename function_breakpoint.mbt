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
/// A stable application-level function breakpoint after package and native
/// symbol resolution. Adapter-specific breakpoint identifiers are not stored.
pub struct FunctionBreakpoint {
  priv id : Int
  priv display_name : String
  priv physical_name : String
}

///|
fn FunctionBreakpoint::new(
  id : Int,
  display_name : String,
  physical_name : String,
) -> FunctionBreakpoint {
  { id, display_name, physical_name, }
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
pub fn FunctionBreakpoint::physical_name(self : FunctionBreakpoint) -> String {
  self.physical_name
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
  priv status : BreakpointStatus
}

///|
pub fn FunctionBreakpointSnapshot::pending(
  id : Int,
  display_name : String,
) -> FunctionBreakpointSnapshot {
  { id, display_name, status: Pending, }
}

///|
pub fn FunctionBreakpointSnapshot::verified(
  id : Int,
  display_name : String,
) -> FunctionBreakpointSnapshot {
  { id, display_name, status: Verified, }
}

///|
pub fn FunctionBreakpointSnapshot::rejected(
  id : Int,
  display_name : String,
  message : String,
) -> FunctionBreakpointSnapshot {
  { id, display_name, status: Rejected(message), }
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
