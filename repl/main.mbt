///|
priv suberror CliError {
  MissingExecutable
  ExecutableNotFound(String)
  ExecutableNotAFile(String)
  AdapterStartTimedOut
  BreakpointSourceNotFound(String)
  BreakpointSourceNotAFile(String)
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
async fn resolve_breakpoint_source(path : String) -> String {
  guard @fs.exists(path) else { raise BreakpointSourceNotFound(path) }
  guard @fs.kind(path) is Regular else { raise BreakpointSourceNotAFile(path) }
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
async fn run_repl(
  editor : @readline.LineEditor,
  history : @readline.History,
  session : @moondbg.DebugSession,
) -> Unit {
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
          Help => print_help()
          Break(source, source_line) =>
            add_source_breakpoint(session, source, source_line)
          Run =>
            match session.run() {
              @moondbg.Stopped(snapshot) => {
                render_breakpoint_updates(session)
                render_stop_snapshot(snapshot)
              }
              @moondbg.Exited(exit_code) => {
                render_breakpoint_updates(session)
                print_exit(exit_code)
                return
              }
            }
          List =>
            match session.last_stop_snapshot() {
              Some(snapshot) => render_stop_snapshot(snapshot)
              None => println("No stopped source location is available.")
            }
          Invalid(message) => println("Error: \{message}")
          Unknown => println("Unknown command. Type 'help' for help.")
        }
      }
    }
  }
}

///|
fn print_help() -> Unit {
  let help =
    #|Commands:
    #|  break <file>:<line>  b <file>:<line>  Set a source breakpoint
    #|  run                  r                Run the program once
    #|  list                                  Show the current source location
    #|  help                                  Show this help
    #|  quit                  q, exit          Exit moondbg
  println(help)
}

///|
async fn add_source_breakpoint(
  session : @moondbg.DebugSession,
  source : String,
  line : Int,
) -> Unit {
  try {
    let canonical_source = resolve_breakpoint_source(source)
    let breakpoint = session.add_source_breakpoint(canonical_source, line)
    println("Breakpoint \{breakpoint.id()} pending at \{source}:\{line}")
  } catch {
    BreakpointSourceNotFound(path) =>
      println("Cannot set breakpoint: source file not found: \{path}")
    BreakpointSourceNotAFile(path) =>
      println("Cannot set breakpoint: source path is not a file: \{path}")
    @moondbg.OperationNotAllowed(state~, action~) =>
      println(
        "Cannot set breakpoint: \{action} is not allowed while the debugger is \{@debug.to_string(state)}",
      )
    error => println("Cannot set breakpoint: \{@debug.to_string(error)}")
  }
}

///|
fn render_breakpoint_updates(session : @moondbg.DebugSession) -> Unit {
  for breakpoint in session.source_breakpoints() {
    let requested = "\{breakpoint.source_path()}:\{breakpoint.requested_line()}"
    match breakpoint.status() {
      @moondbg.Pending =>
        println(
          "Breakpoint \{breakpoint.id()} is still pending at \{requested}",
        )
      @moondbg.Verified =>
        match breakpoint.actual_line() {
          Some(actual_line) if actual_line != breakpoint.requested_line() =>
            println(
              "Breakpoint \{breakpoint.id()} moved from \{requested} to \{breakpoint.source_path()}:\{actual_line}",
            )
          _ => println("Breakpoint \{breakpoint.id()} verified at \{requested}")
        }
      @moondbg.Rejected(message) =>
        println(
          "Breakpoint \{breakpoint.id()} rejected at \{requested}: \{message}",
        )
    }
  }
}

///|
fn stop_location(snapshot : @moondbg.StopSnapshot) -> String {
  match (snapshot.source_path(), snapshot.line()) {
    (Some(source_path), Some(line)) => "\{source_path}:\{line}"
    (Some(source_path), None) => source_path
    (None, _) => "an unknown source location"
  }
}

///|
async fn render_source_context(snapshot : @moondbg.StopSnapshot) -> Unit {
  guard (snapshot.source_path(), snapshot.line())
    is (Some(source_path), Some(line)) else {
    println(
      "Source unavailable: lldb-dap did not provide a local source path and line.",
    )
    return
  }
  let source = Some(@fs.read_file(source_path).text()) catch {
    error => {
      println("Source unavailable: \{@debug.to_string(error)}")
      return
    }
  }
  let lines : Array[StringView] = source.unwrap().split("\n").collect()
  guard line > 0 && line <= lines.length() else {
    println(
      "Source unavailable: line \{line} is outside \{source_path} (1..\{lines.length()}).",
    )
    return
  }
  let first_line = if line > 2 { line - 2 } else { 1 }
  let last_line = if line + 2 < lines.length() {
    line + 2
  } else {
    lines.length()
  }
  let width = last_line.to_string().length()
  for source_line in first_line..<=last_line {
    let number = source_line.to_string()
    let padding = " ".repeat(width - number.length())
    let marker = if source_line == line { ">" } else { " " }
    println("\{marker} \{padding}\{number} │ \{lines[source_line - 1]}")
  }
}

///|
async fn render_stop_snapshot(snapshot : @moondbg.StopSnapshot) -> Unit {
  println(
    "Stopped (\{snapshot.reason()}) in \{snapshot.function_name()} at \{stop_location(snapshot)}",
  )
  render_source_context(snapshot)
}

///|
fn print_exit(exit_code : Int?) -> Unit {
  match exit_code {
    Some(code) => println("Process exited (code \{code}).")
    None => println("Process exited.")
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
    run_repl(editor, history, session)
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
