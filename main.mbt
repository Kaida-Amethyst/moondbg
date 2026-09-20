///|
async fn validate_executable(path : String) -> String {
  guard @fs.exists(path) else { raise ExecutableNotFound(path) }
  guard @fs.kind(path) is Regular else { raise ExecutableNotAFile(path) }
  guard @fs.can_execute(path) else {
    raise @launch.LaunchError("file is not executable: \{path}")
  }
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
  debug_context : @debugger.DebugContext,
) -> Unit {
  let executable = validate_executable(executable)
  @async.with_task_group(async fn(group) {
    let backend = @lldb_dap.LldbDapBackend::start(
      group,
      adapter_command(),
      preparation_timeout_ms=adapter_preparation_timeout_ms(),
    )
    let session = @debugger.DebugSession::new(
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
  // Dispatch before argparse: help/error output from the human CLI must never
  // enter the DAP stdout stream. The existing executable remains the launcher.
  let argv = @env.args()
  if argv.length() > 1 && argv[1] == "--resolve-source" {
    let (result, code) = try {
      guard argv is [_, _, source] else {
        raise @launch.LaunchError(
          "--resolve-source requires one absolute source path",
        )
      }
      (
        @launch.resolve_source(source, output=(_, text) => {
          @stdio.stderr.write(text)
        }),
        0,
      )
    } catch {
      error => {
        let message = match error {
          @launch.LaunchError(message) => message
          _ => @debug.to_string(error)
        }
        let result : Json = { "protocolVersion": 1, "error": message }
        (result, 1)
      }
    }
    @stdio.stdout.write(result.stringify() + "\n") catch {
      _ => ()
    }
    exit_process(code)
    return
  }
  if argv.length() > 1 && argv[1] == "--build-worker" {
    let code = @launch.run_worker(argv[2:].to_owned()) catch {
      error => {
        @stdio.stderr.write(
          "moondbg build worker: \{@debug.to_string(error)}\n",
        ) catch {
          _ => ()
        }
        1
      }
    }
    exit_process(code)
    return
  }
  if argv.length() > 1 && argv[1] == "--dap" {
    guard argv.length() == 2 else {
      @stdio.stderr.write("moondbg --dap accepts no additional arguments.\n") catch {
        _ => ()
      }
      exit_process(2)
      return
    }
    @dap_frontend.serve(@stdio.stdin, @stdio.stdout) catch {
      error => {
        @stdio.stderr.write("moondbg DAP: \{@debug.to_string(error)}\n") catch {
          _ => ()
        }
        exit_process(1)
      }
    }
    return
  }
  try {
    let matches = command().parse()
    let target = target_argument(matches)
    let explicit_context = debug_context_argument(matches)
    let prepared = @launch.prepare_target(target, output=(_, text) => {
      @stdio.stderr.write(text)
    })
    let executable = prepared.executable
    let debug_context = prepared.debug_context
    let debug_context = if matches.values.contains("current-package") {
      explicit_context
    } else {
      debug_context
    }
    run(executable, debug_context)
  } catch {
    error => {
      let message = match error {
        @debugger.AdapterFailure(message) =>
          "debugger adapter failed: \{message}"
        @launch.LaunchError(message) => message
        _ => @debug.to_string(error)
      }
      @stdio.stderr.write("moondbg: \{message}\n") catch {
        _ => ()
      }
      exit_process(1)
    }
  }
}

///|
extern "c" fn exit_process(code : Int) = "exit"
