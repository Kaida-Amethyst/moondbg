///|
/// Errors produced while constructing or resolving source-visible package
/// names for debugger operations.
pub(all) suberror DebugContextError {
  MissingCurrentPackage
  InvalidCurrentPackage(String)
  InvalidPackageAlias(String)
  DuplicatePackageAlias(String)
  UnknownPackageAlias(String)
} derive(Debug, Eq)

///|
pub extend DebugContextError with @debug.Debug::{to_repr}

///|
pub extend DebugContextError with Eq::{equal, not_equal}

///|
/// Build-system context needed to resolve source package names.
///
/// Alias keys exclude the source-level `@`. Values are canonical package
/// names used by the compiler and native name mangling.
pub struct DebugContext {
  priv current_package : String?
  priv package_aliases : Map[String, String]
}

///|
pub fn DebugContext::empty() -> DebugContext {
  { current_package: None, package_aliases: Map([]), }
}

///|
pub fn DebugContext::new(
  current_package : String,
  package_aliases : Array[(String, String)],
) -> DebugContext raise DebugContextError {
  guard current_package.trim() != "" else {
    raise InvalidCurrentPackage(current_package)
  }
  let resolved_aliases : Map[String, String] = Map([])
  for entry in package_aliases {
    let (alias_name, package_name) = entry
    guard alias_name.trim() == alias_name &&
      alias_name != "" &&
      !alias_name.contains("@") &&
      !alias_name.contains(".") &&
      !alias_name.contains("=") else {
      raise InvalidPackageAlias(alias_name)
    }
    guard package_name.trim() == package_name && package_name != "" else {
      raise InvalidPackageAlias("\{alias_name}=\{package_name}")
    }
    guard resolved_aliases.get(alias_name) is None else {
      raise DuplicatePackageAlias(alias_name)
    }
    resolved_aliases[alias_name] = package_name
  }
  { current_package: Some(current_package), package_aliases: resolved_aliases, }
}

///|
pub fn DebugContext::current_package(
  self : DebugContext,
) -> String raise DebugContextError {
  guard self.current_package is Some(package_name) else {
    raise MissingCurrentPackage
  }
  package_name
}

///|
pub fn DebugContext::package_for_alias(
  self : DebugContext,
  alias_name : StringView,
) -> String raise DebugContextError {
  let alias_name = alias_name.to_owned()
  guard self.package_aliases.get(alias_name) is Some(package_name) else {
    raise UnknownPackageAlias(alias_name)
  }
  package_name
}
