///|
priv suberror CliError {
  MissingTarget
  ExecutableNotFound(String)
  ExecutableNotAFile(String)
  InvalidPackageAliasArgument(String)
  PackageAliasWithoutCurrentPackage
} derive(Debug)

///|
fn command() -> @argparse.Command {
  @argparse.Command(
    "moondbg",
    about="Build and debug a MoonBit native package, or debug an existing executable with lldb-dap. Use moondbg --dap for the VS Code protocol frontend.",
    arg_required_else_help=true,
    positionals=[
      @argparse.PositionArg(
        "target",
        about="MoonBit package directory/name or path to an executable",
        num_args=@argparse.ValueRange::single(),
        allow_hyphen_values=true,
      ),
    ],
    options=[
      @argparse.OptionArg(
        "current-package",
        about="canonical MoonBit package containing the debug target",
      ),
      @argparse.OptionArg(
        "package-alias",
        about="source import alias mapping in ALIAS=PACKAGE form",
        action=Append,
      ),
    ],
  )
}

///|
fn target_argument(matches : @argparse.Matches) -> String raise CliError {
  guard matches.values.get("target") is Some([target]) else {
    raise MissingTarget
  }
  target
}

///|
fn parse_package_alias_argument(
  argument : StringView,
) -> (String, String) raise CliError {
  guard argument.split_once("=") is Some((alias_name, package_name)) &&
    alias_name != "" &&
    package_name != "" else {
    raise InvalidPackageAliasArgument(argument.to_owned())
  }
  (alias_name.to_owned(), package_name.to_owned())
}

///|
fn debug_context_argument(
  matches : @argparse.Matches,
) -> @debugger.DebugContext raise {
  let aliases : Array[(String, String)] = match
    matches.values.get("package-alias") {
    Some(arguments) =>
      arguments.map(argument => parse_package_alias_argument(argument))
    None => []
  }
  match matches.values.get("current-package") {
    Some([current_package]) =>
      @debugger.DebugContext::new(current_package, aliases)
    _ => {
      guard aliases.length() == 0 else {
        raise PackageAliasWithoutCurrentPackage
      }
      @debugger.DebugContext::empty()
    }
  }
}
