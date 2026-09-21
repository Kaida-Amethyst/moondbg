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
const TERMINAL_OUTPUT_BEGIN : String = ">>>>>>>>> begin terminal output >>>>>>>>>"

///|
const TERMINAL_OUTPUT_END : String = "<<<<<<<<< end terminal output <<<<<<<<<<<"

///|
async fn render_debuggee_outputs(
  output_items : Array[@debugger.DebugOutput],
) -> Unit {
  guard output_items is [_, ..] else { return }
  println(TERMINAL_OUTPUT_BEGIN)
  println("")
  let mut ended_with_newline = true
  for output in output_items {
    @stdio.stdout.write(output.text())
    ended_with_newline = output.text().has_suffix("\n") ||
      output.text().has_suffix("\r")
  }
  if !ended_with_newline {
    println("")
  }
  println("")
  println(TERMINAL_OUTPUT_END)
}

///|
fn render_breakpoint_update(breakpoint : @debugger.BreakpointSnapshot) -> Unit {
  let requested = "\{breakpoint.source_path()}:\{breakpoint.requested_line()}"
  match breakpoint.status() {
    @debugger.Pending =>
      println("Breakpoint \{breakpoint.id()} is still pending at \{requested}")
    @debugger.Verified =>
      match breakpoint.actual_line() {
        Some(actual_line) if actual_line != breakpoint.requested_line() =>
          println(
            "Breakpoint \{breakpoint.id()} moved from \{requested} to \{breakpoint.source_path()}:\{actual_line}",
          )
        _ => println("Breakpoint \{breakpoint.id()} verified at \{requested}")
      }
    @debugger.Rejected(message) =>
      println(
        "Breakpoint \{breakpoint.id()} rejected at \{requested}: \{message}",
      )
  }
}

///|
fn render_function_breakpoint_update(
  breakpoint : @debugger.FunctionBreakpointSnapshot,
) -> Unit {
  match breakpoint.status() {
    @debugger.Pending =>
      println(
        "Breakpoint \{breakpoint.id()} is still pending at function \{breakpoint.display_name()}",
      )
    @debugger.Verified =>
      match breakpoint.location_count() {
        Some(count) if count > 1 =>
          println(
            "Breakpoint \{breakpoint.id()} verified at function \{breakpoint.display_name()} (\{count} locations)",
          )
        _ =>
          println(
            "Breakpoint \{breakpoint.id()} verified at function \{breakpoint.display_name()}",
          )
      }
    @debugger.Rejected(message) =>
      println(
        "Breakpoint \{breakpoint.id()} rejected at function \{breakpoint.display_name()}: \{message}",
      )
  }
}

///|
fn stop_location(snapshot : @debugger.StopSnapshot) -> String {
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
fn render_stop_header(snapshot : @debugger.StopSnapshot) -> Unit {
  println(
    "Stopped (\{snapshot.reason()}) in \{snapshot.function_name()} at \{stop_location(snapshot)}",
  )
  if snapshot.notice() is Some(notice) {
    println(notice)
  }
}

///|
fn stack_frame_location(frame : @debugger.StackFrameSnapshot) -> String {
  match (frame.source_path(), frame.line()) {
    (Some(source_path), Some(line)) => "\{source_path}:\{line}"
    (Some(source_path), None) => source_path
    (None, _) => "source unavailable"
  }
}

///|
fn stack_frame_kind_label(kind : @debugger.FrameKind) -> String {
  match kind {
    @debugger.MoonBitUserFrame => "moonbit"
    @debugger.MoonBitRuntimeFrame => "runtime"
    @debugger.NativeFrame => "native"
    @debugger.UnknownFrame => "unknown"
  }
}

///|
fn backtrace_lines(view : BacktraceView) -> Array[String] {
  guard view.frames is [_, ..] else {
    return ["No stack frames are available."]
  }
  let lines = view.frames.map(frame => {
    let marker = if view.selected_frame == Some(frame.physical_index()) {
      "*"
    } else {
      " "
    }
    "\{marker} #\{frame.physical_index()} [\{stack_frame_kind_label(frame.kind())}] \{frame.display_name()} at \{stack_frame_location(frame)}"
  })
  if view.selected_frame is Some(selected) &&
    !view.frames.any(frame => frame.physical_index() == selected) {
    lines.push(
      "  Current frame #\{selected} is hidden; use 'bt --all' to show it.",
    )
  }
  lines
}

///|
fn render_backtrace(view : BacktraceView) -> Unit {
  for line in backtrace_lines(view) {
    println(line)
  }
}

///|
fn frame_selected_line(frame : @debugger.StackFrameSnapshot) -> String {
  "Selected frame #\{frame.physical_index()}: \{frame.display_name()} at \{stack_frame_location(frame)}"
}

///|
fn render_frame_selection_failure(failure : FrameSelectionFailure) -> Unit {
  match failure {
    FrameUnavailable(index) => println("Frame #\{index} is not available.")
    CurrentFrameUnavailable => println("No current frame is selected.")
    CallerBoundary(index) =>
      println("Frame #\{index} has no visible MoonBit caller.")
    CalleeBoundary(index) =>
      println("Frame #\{index} has no visible MoonBit callee.")
  }
}

///|
fn moonbit_variable_type_name(type_name : StringView) -> String {
  match type_name {
    "bool" => "Bool"
    "float" => "Float"
    "double" => "Double"
    "int32_t" => "Int"
    "uint32_t" => "UInt"
    "int64_t" => "Int64"
    "uint64_t" => "UInt64"
    _ => {
      let base : StringView = match type_name.strip_suffix(" &") {
        Some(base) => base
        None =>
          match type_name.strip_suffix(" *") {
            Some(base) => base
            None => type_name
          }
      }
      match base.rev_split_once("/") {
        Some((package_name, source_name)) if package_name != "" &&
          source_name != "" => source_name.to_owned()
        _ => base.to_owned()
      }
    }
  }
}

///|
fn variable_label(variable : @debugger.VariableSnapshot) -> String {
  match variable.type_name() {
    Some(type_name) =>
      "\{variable.name()}: \{moonbit_variable_type_name(type_name)}"
    None => variable.name()
  }
}

///|
const INDEXED_COLLECTION_CONTENT_WIDTH : Int = 100

///|
fn indexed_element_text(
  element : @debugger.IndexedVariableElement,
  element_type_name : String,
) -> String {
  match element.value() {
    Some(value) => value.value()
    None => element_type_name
  }
}

///|
fn indexed_content_text(
  collection : @debugger.IndexedCollectionSnapshot,
  selected : Array[@debugger.IndexedVariableElement],
) -> String {
  let parts : Array[String] = []
  let mut next_index = 0
  for element in selected {
    if element.index() > next_index {
      parts.push("...")
    }
    parts.push(indexed_element_text(element, collection.element_type_name()))
    next_index = element.index() + 1
  }
  if next_index < collection.total_length() {
    parts.push("...")
  }
  "[\{parts.join(", ")}]"
}

///|
fn bounded_indexed_content_text(
  collection : @debugger.IndexedCollectionSnapshot,
) -> String {
  let selected : Array[@debugger.IndexedVariableElement] = []
  selected.push_iter(collection.preview_elements().iter())
  let mut content = indexed_content_text(collection, selected)
  while content.length() > INDEXED_COLLECTION_CONTENT_WIDTH &&
        selected.length() > 2 {
    selected.remove(selected.length() - 2) |> ignore
    content = indexed_content_text(collection, selected)
  }
  content
}

///|
fn append_indexed_collection_lines(
  lines : Array[String],
  variable : @debugger.VariableSnapshot,
  collection : @debugger.IndexedCollectionSnapshot,
  indentation : Int,
) -> Unit {
  let prefix = " ".repeat(indentation)
  lines.push(
    "\{prefix}\{variable.name()}: \{collection.kind().source_name()}[\{collection.element_type_name()}] with length = \{collection.total_length()}",
  )
  lines.push("")
  lines.push("\{prefix}  \{bounded_indexed_content_text(collection)}")
}

///|
fn enum_payload_text(payload : @debugger.VariableEnumPayload) -> String {
  payload.scalar_value().unwrap_or(payload.type_name())
}

///|
fn append_enum_lines(
  lines : Array[String],
  variable : @debugger.VariableSnapshot,
  enum_value : @debugger.VariableEnumSnapshot,
  indentation : Int,
) -> Unit {
  let prefix = " ".repeat(indentation)
  let payload = enum_value.payload().map(enum_payload_text)
  let rendered = if payload is [] {
    enum_value.constructor_name()
  } else {
    "\{enum_value.constructor_name()}(\{payload.join(", ")})"
  }
  lines.push("\{prefix}\{variable_label(variable)}")
  lines.push("")
  lines.push("\{prefix}  \{rendered}")
}

///|
fn append_variable_lines(
  lines : Array[String],
  variable : @debugger.VariableSnapshot,
  indentation : Int,
) -> Unit {
  let prefix = " ".repeat(indentation)
  let label = variable_label(variable)
  match variable.content() {
    @debugger.VariableLeaf =>
      lines.push("\{prefix}\{label} = \{variable.value()}")
    @debugger.VariableStructure(structure) => {
      let children = structure.children()
      if children is [] && !structure.is_truncated() {
        lines.push("\{prefix}\{label} = {}")
      } else {
        lines.push("\{prefix}\{label} = {")
        for child in children {
          append_variable_lines(lines, child, indentation + 2)
        }
        if structure.is_truncated() {
          lines.push("\{prefix}  …")
        }
        lines.push("\{prefix}}")
      }
    }
    @debugger.VariableIndexedCollection(collection) =>
      append_indexed_collection_lines(lines, variable, collection, indentation)
    @debugger.VariableEnum(enum_value) =>
      append_enum_lines(lines, variable, enum_value, indentation)
  }
}

///|
fn variable_lines(variable : @debugger.VariableSnapshot) -> Array[String] {
  let lines : Array[String] = []
  append_variable_lines(lines, variable, 0)
  lines
}

///|
fn render_variable(variable : @debugger.VariableSnapshot) -> Unit {
  for line in variable_lines(variable) {
    println(line)
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
    BreakpointCurrentFrameMissing =>
      println(
        "Cannot set breakpoint by line: no stopped frame is selected. Use b <file>:<line>.",
      )
    BreakpointCurrentFrameSourceMissing =>
      println(
        "Cannot set breakpoint by line: the selected frame has no source file. Use b <file>:<line>.",
      )
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
        "Cannot set function breakpoint: package context is missing; launch moondbg with a package directory or provide --current-package.",
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
fn variable_lookup_failure_message(
  failure : @debugger.VariableLookupFailure,
) -> String {
  failure.message()
}

///|
fn local_type_suffix(type_name : String?) -> String {
  match type_name {
    Some(name) if name != "" => ": \{name}"
    _ => ""
  }
}

///|
fn local_summary_line(variable : @debugger.LocalVariableSnapshot) -> String {
  let prefix = "  \{variable.name()}\{local_type_suffix(variable.type_name())}"
  match variable.availability() {
    @debugger.LocalVariableUnavailable => "\{prefix} = <unavailable>"
    @debugger.LocalVariableAmbiguous => "\{prefix} = <ambiguous binding>"
    @debugger.LocalVariableAvailable(value) =>
      match value {
        @debugger.LocalScalar(scalar) => "\{prefix} = \{scalar}"
        @debugger.LocalCollection(_, length) =>
          "\{prefix} with length = \{length}"
        @debugger.LocalEnumConstructor(name) => "\{prefix} = \{name}"
        @debugger.LocalStructure | @debugger.LocalOpaque => prefix
      }
  }
}

///|
fn local_snapshot_lines(
  snapshot : @debugger.LocalVariablesSnapshot,
) -> Array[String] {
  guard snapshot.scope_availability() is @debugger.LocalScopeAvailable else {
    return ["Local variables are unavailable in the selected frame."]
  }
  let variables = snapshot.variables()
  guard variables.length() > 0 else {
    return ["No local variables in the selected frame."]
  }
  let lines = ["Locals:"]
  for variable in variables {
    lines.push(local_summary_line(variable))
  }
  lines
}

///|
fn render_locals(snapshot : @debugger.LocalVariablesSnapshot) -> Unit {
  for line in local_snapshot_lines(snapshot) {
    println(line)
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
    BreakpointsPresentation(entries) =>
      for line in breakpoint_list_lines(entries) {
        println(line)
      }
    BreakpointManagedPresentation(result) =>
      println(breakpoint_managed_line(result))
    BreakpointManagementFailurePresentation(failure) =>
      println(breakpoint_management_failure_line(failure))
    StopPresentation(snapshot) => render_stop_header(snapshot)
    BacktracePresentation(view) => render_backtrace(view)
    FrameSelectedPresentation(frame) => println(frame_selected_line(frame))
    FrameSelectionFailurePresentation(failure) =>
      render_frame_selection_failure(failure)
    SourceViewPresentation(view) => render_source_view(view)
    VariablePresentation(variable) => render_variable(variable)
    VariableLookupFailurePresentation(failure) =>
      println(variable_lookup_failure_message(failure))
    LocalsPresentation(snapshot) => render_locals(snapshot)
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
