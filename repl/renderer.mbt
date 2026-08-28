///|
priv struct HumanRenderer {}

///|
fn HumanRenderer::new() -> HumanRenderer {
  HumanRenderer::{ }
}

///|
fn help_padding(width : Int, content_length : Int) -> String {
  let padding = width - content_length
  " ".repeat(if padding > 1 { padding } else { 2 })
}

///|
fn format_help_entry(entry : CommandHelpEntry) -> String {
  let alias_usage = entry.alias_usage()
  guard alias_usage != "" else {
    let padding = help_padding(38, entry.usage.length())
    return "  \{entry.usage}\{padding}\{entry.summary}"
  }
  let multiple_aliases = entry.aliases.length() > 1
  let usage_width = if multiple_aliases { 22 } else { 21 }
  let usage_padding = help_padding(usage_width, entry.usage.length())
  let alias_padding = help_padding(17, alias_usage.length())
  "  \{entry.usage}\{usage_padding}\{alias_usage}\{alias_padding}\{entry.summary}"
}

///|
fn render_help(entries : Array[CommandHelpEntry]) -> Unit {
  println("Commands:")
  for entry in entries {
    println(format_help_entry(entry))
  }
}

///|
async fn render_debuggee_outputs(
  output_items : Array[@moondbg.DebugOutput],
) -> Unit {
  let mut wrote_output = false
  let mut ended_with_newline = true
  for output in output_items {
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
fn render_breakpoint_update(breakpoint : @moondbg.BreakpointSnapshot) -> Unit {
  let requested = "\{breakpoint.source_path()}:\{breakpoint.requested_line()}"
  match breakpoint.status() {
    @moondbg.Pending =>
      println("Breakpoint \{breakpoint.id()} is still pending at \{requested}")
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

///|
fn render_function_breakpoint_update(
  breakpoint : @moondbg.FunctionBreakpointSnapshot,
) -> Unit {
  match breakpoint.status() {
    @moondbg.Pending =>
      println(
        "Breakpoint \{breakpoint.id()} is still pending at function \{breakpoint.display_name()}",
      )
    @moondbg.Verified =>
      println(
        "Breakpoint \{breakpoint.id()} verified at function \{breakpoint.display_name()}",
      )
    @moondbg.Rejected(message) =>
      println(
        "Breakpoint \{breakpoint.id()} rejected at function \{breakpoint.display_name()}: \{message}",
      )
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
fn source_window(
  current_line : Int,
  total_lines : Int,
  line_count~ : Int,
) -> (Int, Int) {
  let visible_count = if line_count < total_lines {
    line_count
  } else {
    total_lines
  }
  let centered_first = if current_line > visible_count / 2 {
    current_line - visible_count / 2
  } else {
    1
  }
  let maximum_first = total_lines - visible_count + 1
  let first_line = if centered_first < maximum_first {
    centered_first
  } else {
    maximum_first
  }
  (first_line, first_line + visible_count - 1)
}

///|
async fn render_source_view(view : SourceView) -> Unit {
  guard (view.source_path, view.line) is (Some(source_path), Some(line)) else {
    println(
      "Source unavailable: lldb-dap did not provide a local source path and line.",
    )
    return
  }
  let source = @fs.read_file(source_path).text() catch {
    error => {
      println("Source unavailable: \{@debug.to_string(error)}")
      return
    }
  }
  let lines = @render.render_mbt_lines(
    source,
    theme=@render.Theme::gruvbox_dark(),
  )
  guard line > 0 && line <= lines.length() else {
    println(
      "Source unavailable: line \{line} is outside \{source_path} (1..\{lines.length()}).",
    )
    return
  }
  let (first_line, last_line) = source_window(
    line,
    lines.length(),
    line_count=view.line_count,
  )
  let width = last_line.to_string().length()
  for source_line in first_line..<=last_line {
    let number = source_line.to_string()
    let padding = " ".repeat(width - number.length())
    let marker = if source_line == line { ">" } else { " " }
    println("\{marker} \{padding}\{number} │ \{lines[source_line - 1]}")
  }
}

///|
fn render_stop_header(snapshot : @moondbg.StopSnapshot) -> Unit {
  println(
    "Stopped (\{snapshot.reason()}) in \{snapshot.function_name()} at \{stop_location(snapshot)}",
  )
}

///|
fn render_variable(variable : @moondbg.VariableSnapshot) -> Unit {
  match variable.type_name() {
    Some(type_name) =>
      println("\{variable.name()}: \{type_name} = \{variable.value()}")
    None => println("\{variable.name()} = \{variable.value()}")
  }
}

///|
fn render_process_exit(exit_code : Int?) -> Unit {
  match exit_code {
    Some(0) => println("Process exited normally (code 0).")
    Some(code) => println("Process exited with code \{code}.")
    None => println("Process exited.")
  }
}

///|
fn render_breakpoint_error(error : BreakpointCommandError) -> Unit {
  match error {
    BreakpointSourceNotFound(path) =>
      println("Cannot set breakpoint: source file not found: \{path}")
    BreakpointSourceNotAFile(path) =>
      println("Cannot set breakpoint: source path is not a file: \{path}")
    BreakpointOperationNotAllowed(state, action) =>
      println(
        "Cannot set breakpoint: \{action} is not allowed while the debugger is \{@debug.to_string(state)}",
      )
    BreakpointFunctionContextMissing =>
      println(
        "Cannot set function breakpoint: package context is missing; launch moondbg through moon debug.",
      )
    BreakpointUnknownPackageAlias(package_alias) =>
      println(
        "Cannot set function breakpoint: unknown package alias '@\{package_alias}'.",
      )
    BreakpointUnexpectedFailure(message) =>
      println("Cannot set breakpoint: \{message}")
  }
}

///|
async fn render_presentation_event(event : PresentationEvent) -> Unit {
  match event {
    HelpPresentation(entries) => render_help(entries)
    UserErrorPresentation(message) => println(message)
    DebuggeeOutputPresentation(output) => render_debuggee_outputs(output)
    ProgramRestartingPresentation => println("Restarting program.")
    BreakpointPendingPresentation(id, source, line) =>
      println("Breakpoint \{id} pending at \{source}:\{line}")
    BreakpointUpdatePresentation(breakpoint) =>
      render_breakpoint_update(breakpoint)
    FunctionBreakpointPendingPresentation(id, display_name) =>
      println("Breakpoint \{id} pending at function \{display_name}")
    FunctionBreakpointUpdatePresentation(breakpoint) =>
      render_function_breakpoint_update(breakpoint)
    BreakpointErrorPresentation(error) => render_breakpoint_error(error)
    StopPresentation(snapshot) => render_stop_header(snapshot)
    SourceViewPresentation(view) => render_source_view(view)
    VariablePresentation(variable) => render_variable(variable)
    VariableNotFoundPresentation(name) =>
      println("Variable '\{name}' was not found in the current frame.")
    NoStoppedSourcePresentation =>
      println("No stopped source location is available.")
    ProcessExitPresentation(exit_code) => render_process_exit(exit_code)
    OperationNotAllowedPresentation(state, action) =>
      println(
        "Cannot \{action} while the debugger is \{@debug.to_string(state)}.",
      )
    AdapterFailurePresentation(message) =>
      println("moondbg: debugger adapter failed: \{message}")
  }
}

///|
impl PresentationRenderer for HumanRenderer with fn render(_self, events) {
  for event in events {
    render_presentation_event(event)
  }
}
