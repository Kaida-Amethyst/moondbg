///|
async fn find_adapter() -> String {
  if @env.get_env_var("MOONDBG_LLDB_DAP") is Some(path) && path != "" {
    return path
  }
  let discovered = Some(
    @process.collect_stdout("xcrun", ["--find", "lldb-dap"], inherit_env=true),
  ) catch {
    _ => None
  }
  if discovered is Some((0, output)) {
    let path = output.text().trim().to_owned()
    if path != "" {
      return path
    }
  }
  "lldb-dap"
}

///|
async fn launch_arguments(arguments : Json) -> Json {
  validate_launch_options(arguments)
  guard arguments is { "program": String(program), .. } &&
    program.has_prefix("/") else {
    raise LiveError(
      "launch.program must be an absolute path to a precompiled executable.",
    )
  }
  guard @fs.exists(program) &&
    @fs.kind(program) is Regular &&
    @fs.can_execute(program) else {
    raise LiveError(
      "Program is missing or not executable: \{program}. Build it with -g -O0 first.",
    )
  }
  let default_cwd = match program.rev_find("/") {
    Some(index) if index > 0 => program[:index].to_owned()
    _ => "/"
  }
  let cwd = validate_launch_cwd(arguments, default_cwd)
  {
    "program": program,
    "cwd": cwd,
    "stopOnEntry": false,
    "preRunCommands": ["!settings set target.input-path /dev/null"],
  }
}

///|
async fn validate_launch_cwd(arguments : Json, default_cwd : String) -> String {
  let cwd = match arguments {
    { "cwd": String(cwd), .. } => cwd
    { "cwd": _, .. } =>
      raise LiveError("launch.cwd must be an absolute directory path.")
    _ => default_cwd
  }
  guard cwd.has_prefix("/") && @fs.exists(cwd) && @fs.kind(cwd) is Directory else {
    raise LiveError("Working directory does not exist: \{cwd}")
  }
  cwd
}

///|
fn validate_launch_options(arguments : Json) -> Unit raise {
  // Do not forward arbitrary LLDB commands, terminal settings, args or attach
  // settings from launch.json. This milestone owns one no-argument launch.
  for
    key in [
      "args", "env", "initCommands", "preRunCommands", "runInTerminal", "stopOnEntry",
    ] {
    if arguments is Object(fields) && fields.contains(key) {
      raise LiveError("launch.\{key} is not supported in this milestone.")
    }
  }
  if arguments is { "noDebug": True, .. } {
    raise LiveError("Running without debugging is not supported.")
  }
}
