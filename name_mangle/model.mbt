///|
/// A decoded MoonBit v0 top-level function symbol.
///
/// Generic arguments use MoonBit source-like names. They are intentionally
/// independent from LLDB and DAP representations.
pub struct TopLevelFunctionSymbol {
  priv package_name : String
  priv function_name : String
  priv type_arguments : Array[String]
  priv error_type_argument : String?
} derive(Debug, Eq)

///|
pub extend TopLevelFunctionSymbol with @debug.Debug::{to_repr}

///|
pub extend TopLevelFunctionSymbol with Eq::{equal, not_equal}

///|
fn TopLevelFunctionSymbol::new(
  package_name : String,
  function_name : String,
  type_arguments : Array[String],
  error_type_argument : String?,
) -> TopLevelFunctionSymbol {
  { package_name, function_name, type_arguments, error_type_argument, }
}

///|
pub fn TopLevelFunctionSymbol::package_name(
  self : TopLevelFunctionSymbol,
) -> String {
  self.package_name
}

///|
pub fn TopLevelFunctionSymbol::function_name(
  self : TopLevelFunctionSymbol,
) -> String {
  self.function_name
}

///|
pub fn TopLevelFunctionSymbol::type_arguments(
  self : TopLevelFunctionSymbol,
) -> Array[String] {
  self.type_arguments.copy()
}

///|
pub fn TopLevelFunctionSymbol::error_type_argument(
  self : TopLevelFunctionSymbol,
) -> String? {
  self.error_type_argument
}

///|
pub fn TopLevelFunctionSymbol::is_specialized(
  self : TopLevelFunctionSymbol,
) -> Bool {
  self.type_arguments.length() > 0 || self.error_type_argument is Some(_)
}
