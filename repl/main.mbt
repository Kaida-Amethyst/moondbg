///|
priv suberror CliError {
  MissingExecutable
  ExecutableNotFound(String)
  ExecutableNotAFile(String)
  AdapterStartTimedOut
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
fn run_repl(
  editor : @readline.LineEditor,
  history : @readline.History,
) -> Unit raise {
  for ;; {
    let input = editor.read_line(prompt="(moondbg) ") catch {
      Interrupted => {
        println("")
        continue
      }
      error => raise error
    }
    match input {
      None => break
      Some(line) => {
        if line != "" {
          history.add(line)
        }
        match parse_repl_command(line) {
          Quit => return
          Unknown => println("Commands are not implemented yet.")
        }
      }
    }
  }
}

///|
async fn run(executable : String) -> Unit {
  let executable = validate_executable(executable)
  @async.with_task_group(async fn(group) {
    guard @async.with_timeout_opt(10000, () => {
        @moondbg.DebugSession::start(group, adapter_command(), executable)
      })
      is Some(session) else {
      raise AdapterStartTimedOut
    }
    defer session.close()
    let history = @readline.History::new()
    let editor = @readline.LineEditor::open(history~)
    run_repl(editor, history)
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
    error => println("moondbg: \{@debug.to_string(error)}")
  }
}
