///|
priv suberror CliError {
  MissingExecutable
  ExecutableNotFound(String)
  ExecutableNotAFile(String)
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
async fn run(executable : String) -> Unit {
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
    let executable = executable_argument(command().parse())
    run(executable)
  } catch {
    @moondbg.AdapterFailure(message) =>
      println("moondbg: debugger adapter failed: \{message}")
    error => println("moondbg: \{@debug.to_string(error)}")
  }
}
