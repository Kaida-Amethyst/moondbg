///|
/// Errors produced while encoding or decoding MoonBit v0 native symbols.
pub(all) suberror NameMangleError {
  InvalidPackage(String)
  InvalidIdentifier(String)
  InvalidSymbol(String)
  UnsupportedVersion(String)
} derive(Debug, Eq)

///|
pub extend NameMangleError with @debug.Debug::{to_repr}

///|
pub extend NameMangleError with Eq::{equal, not_equal}
