///|
priv suberror CliError {
  MissingExecutable
  ExecutableNotFound(String)
  ExecutableNotAFile(String)
  InvalidPackageAliasArgument(String)
  PackageAliasWithoutCurrentPackage
} derive(Debug)

///|
fn command() -> @argparse.Command {
  @argparse.Command(
    "moondbg",
    about="Debug a native executable with lldb-dap.",
    arg_required_else_help=true,
    positionals=[
      @argparse.PositionArg(
        "executable",
        about="path to the executable to debug",
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
fn executable_argument(matches : @argparse.Matches) -> String raise CliError {
  guard matches.values.get("executable") is Some([executable]) else {
    raise MissingExecutable
  }
  executable
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
) -> @moondbg.DebugContext raise {
  let aliases : Array[(String, String)] = match
    matches.values.get("package-alias") {
    Some(arguments) =>
      arguments.map(argument => parse_package_alias_argument(argument))
    None => []
  }
  match matches.values.get("current-package") {
    Some([current_package]) =>
      @moondbg.DebugContext::new(current_package, aliases)
    _ => {
      guard aliases.length() == 0 else {
        raise PackageAliasWithoutCurrentPackage
      }
      @moondbg.DebugContext::empty()
    }
  }
}

///|
async fn validate_executable(path : String) -> String {
  guard @fs.exists(path) else { raise ExecutableNotFound(path) }
  guard @fs.kind(path) is Regular else { raise ExecutableNotAFile(path) }
  @fs.realpath(path)
}

///|
async fn adapter_command() -> String {
  match @env.get_env_var("MOONDBG_LLDB_DAP") {
    Some(command) if command != "" => return command
    _ => ()
  }
  let discovered = Some(
    @process.collect_stdout("xcrun", ["--find", "lldb-dap"], inherit_env=true),
  ) catch {
    _ => None
  }
  match discovered {
    Some((0, output)) => {
      let path = output.text().trim().to_owned() catch { _ => "" }
      if path == "" {
        "lldb-dap"
      } else {
        path
      }
    }
    _ => "lldb-dap"
  }
}

///|
fn adapter_preparation_timeout_ms() -> Int {
  let default_timeout_ms = 10000
  guard @env.get_env_var("MOONDBG_ADAPTER_TIMEOUT_MS") is Some(value) else {
    return default_timeout_ms
  }
  let parsed = Some(@string.parse_int(value, base=10)) catch { _ => None }
  guard parsed is Some(timeout_ms) && timeout_ms > 0 else {
    return default_timeout_ms
  }
  timeout_ms
}

///|
async fn run(
  executable : String,
  debug_context : @moondbg.DebugContext,
) -> Unit {
  let executable = validate_executable(executable)
  @async.with_task_group(async fn(group) {
    let backend = @lldb_dap.LldbDapBackend::start(
      group,
      adapter_command(),
      preparation_timeout_ms=adapter_preparation_timeout_ms(),
    )
    let session = @moondbg.DebugSession::new(
      executable,
      backend.as_debug_backend(),
      debug_context~,
    )
    defer session.close()
    let history = @readline.History::new()
    let editor = @readline.LineEditor::open(history~)
    let registry = default_command_registry()
    let renderer = HumanRenderer::new()
    let context = ReplContext::new(session, registry, renderer)
    run_repl(editor, history, context)
    session.disconnect()
    println("Debugger exited.")
  })
}

///|
async fn main {
  try {
    let matches = command().parse()
    let executable = executable_argument(matches)
    let debug_context = debug_context_argument(matches)
    run(executable, debug_context)
  } catch {
    @moondbg.AdapterFailure(message) =>
      println("moondbg: debugger adapter failed: \{message}")
    error => println("moondbg: \{@debug.to_string(error)}")
  }
}
