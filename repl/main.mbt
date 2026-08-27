///|
priv suberror CliError {
  MissingExecutable
  ExecutableNotFound(String)
  ExecutableNotAFile(String)
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
async fn run_repl(
  editor : @readline.LineEditor,
  history : @readline.History,
  session : @moondbg.DebugSession,
) -> Unit {
  for ;; {
    let input = editor.read_line(prompt="(moondbg) ") catch {
      @readline.Interrupted => {
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
          Run => run_debuggee(session)
          Continue => continue_debuggee(session)
          StepExecution(kind) => step_debuggee(session, kind)
          PrintVariable(name) => inspect_variable(session, name)
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
    #|  run                  r                Run or restart the program
    #|  continue             c                Continue the stopped program
    #|  next                 n                Step over the current source line
    #|  step                 s                Step into a called function
    #|  finish               fin              Step out of the current function
    #|  print <name>         p <name>         Show a simple variable
    #|  list                                  Show the current source location
    #|  help                                  Show this help
    #|  quit                  q, exit          Exit moondbg
  println(help)
}

///|
fn render_operation_not_allowed(
  state : @moondbg.DebugSessionState,
  action : String,
) -> Unit {
  println("Cannot \{action} while the debugger is \{@debug.to_string(state)}.")
}

///|
async fn render_debug_output(session : @moondbg.DebugSession) -> Unit {
  let mut wrote_output = false
  let mut ended_with_newline = true
  for output in session.take_output() {
    @stdio.stdout.write(output.text())
    wrote_output = true
    ended_with_newline = output.text().has_suffix("\n") ||
      output.text().has_suffix("\r")
  }
  if wrote_output && !ended_with_newline {
    println("")
  }
}

///|
async fn render_execution_outcome(outcome : @moondbg.RunOutcome) -> Unit {
  match outcome {
    @moondbg.Stopped(snapshot) => render_stop_snapshot(snapshot)
    @moondbg.Exited(exit_code) => print_exit(exit_code)
  }
}

///|
async fn run_debuggee(session : @moondbg.DebugSession) -> Unit {
  if session.state() is @moondbg.Stopped {
    println("Restarting program.")
  }
  let outcome = session.run() catch {
    @moondbg.OperationNotAllowed(state~, action~) => {
      render_operation_not_allowed(state, action)
      return
    }
    @moondbg.AdapterFailure(message) => {
      render_debug_output(session)
      println("moondbg: debugger adapter failed: \{message}")
      return
    }
    error => raise error
  }
  render_debug_output(session)
  render_breakpoint_updates(session)
  render_execution_outcome(outcome)
}

///|
async fn continue_debuggee(session : @moondbg.DebugSession) -> Unit {
  let outcome = session.continue_execution() catch {
    @moondbg.OperationNotAllowed(state~, action~) => {
      render_operation_not_allowed(state, action)
      return
    }
    @moondbg.AdapterFailure(message) => {
      render_debug_output(session)
      println("moondbg: debugger adapter failed: \{message}")
      return
    }
    error => raise error
  }
  render_debug_output(session)
  render_execution_outcome(outcome)
}

///|
async fn request_step(
  session : @moondbg.DebugSession,
  kind : ReplStepKind,
) -> @moondbg.RunOutcome {
  match kind {
    StepOver => session.next()
    StepInto => session.step()
    StepOut => session.finish()
  }
}

///|
async fn step_debuggee(
  session : @moondbg.DebugSession,
  kind : ReplStepKind,
) -> Unit {
  let outcome = request_step(session, kind) catch {
    @moondbg.OperationNotAllowed(state~, action~) => {
      render_operation_not_allowed(state, action)
      return
    }
    @moondbg.AdapterFailure(message) => {
      render_debug_output(session)
      println("moondbg: debugger adapter failed: \{message}")
      return
    }
    error => raise error
  }
  render_debug_output(session)
  render_execution_outcome(outcome)
}

///|
async fn inspect_variable(
  session : @moondbg.DebugSession,
  name : String,
) -> Unit {
  let result = session.find_variable(name) catch {
    @moondbg.OperationNotAllowed(state~, action~) => {
      render_operation_not_allowed(state, action)
      return
    }
    @moondbg.AdapterFailure(message) => {
      render_debug_output(session)
      println("moondbg: debugger adapter failed: \{message}")
      return
    }
    error => raise error
  }
  render_debug_output(session)
  match result {
    @moondbg.VariableFound(variable) =>
      match variable.type_name() {
        Some(type_name) =>
          println("\{variable.name()}: \{type_name} = \{variable.value()}")
        None => println("\{variable.name()} = \{variable.value()}")
      }
    @moondbg.VariableNotFound(variable_name) =>
      println("Variable '\{variable_name}' was not found in the current frame.")
  }
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
  let lines = @render.render_mbt_lines(source.unwrap(), theme = @render.Theme::gruvbox_dark())
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
    Some(0) => println("Process exited normally (code 0).")
    Some(code) => println("Process exited with code \{code}.")
    None => println("Process exited.")
  }
}

///|
async fn run(executable : String) -> Unit {
  let executable = validate_executable(executable)
  @async.with_task_group(async fn(group) {
    let session = @moondbg.DebugSession::start(
      group,
      adapter_command(),
      executable,
      preparation_timeout_ms=adapter_preparation_timeout_ms(),
    )
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
    @moondbg.AdapterFailure(message) =>
      println("moondbg: debugger adapter failed: \{message}")
    error => println("moondbg: \{@debug.to_string(error)}")
  }
}
