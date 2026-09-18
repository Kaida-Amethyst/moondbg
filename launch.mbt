///|
async fn project_root(directory : String) -> String {
  for directory = directory {
    if @fs.exists("\{directory}/moon.mod") ||
      @fs.exists("\{directory}/moon.mod.json") {
      break directory
    }
    let parent = @fs.realpath("\{directory}/..")
    guard parent != directory else {
      raise LaunchError("no MoonBit project found for \{directory}")
    }
    continue parent
  }
}

///|
async fn run_moon(project : String, arguments : Array[String]) -> String {
  let (status, output) = @process.collect_stdout(
    "moon",
    arguments,
    cwd=project,
    inherit_env=true,
    stderr=@stdio.stderr,
  )
  guard status == 0 else {
    // Build scripts may also write diagnostics to stdout. Preserve them on
    // failure, before returning to the CLI's nonzero exit path.
    @stdio.stderr.write(output)
    raise LaunchError("moon \{arguments[0]} failed (exit status \{status})")
  }
  output.text()
}

///|
async fn select_package(
  packages : Array[PackageMetadata],
  target : String,
  directory : String?,
) -> PackageMetadata {
  let matches = []
  for pkg in packages {
    let matches_target = match directory {
      Some(directory) => @fs.realpath(pkg.directory) == directory
      None => pkg.relative_name == target || pkg.name == target
    }
    if matches_target {
      matches.push(pkg)
    }
  }
  guard matches is [pkg] else {
    raise LaunchError(
      "target '\{target}' does not identify one local MoonBit package",
    )
  }
  guard pkg.supports_native else {
    raise LaunchError(
      "package '\{pkg.name}' does not support the native target",
    )
  }
  guard pkg.is_main else {
    raise LaunchError(
      "package '\{pkg.name}' cannot generate an executable; declare pkgtype(kind: \"executable\") in moon.pkg (or is-main: true in moon.pkg.json)",
    )
  }
  pkg
}

///|
async fn prepare_target(target : String) -> (String, @debugger.DebugContext) {
  let directory = if @fs.exists(target) {
    match @fs.kind(target) {
      Regular =>
        return (validate_executable(target), @debugger.DebugContext::empty())
      Directory => Some(@fs.realpath(target))
      _ =>
        raise LaunchError(
          "target is neither a package directory nor an executable: \{target}",
        )
    }
  } else {
    None
  }
  let project = project_root(
    match directory {
      Some(directory) => directory
      None => @fs.realpath(".")
    },
  )
  // Use one explicit output directory for both commands. This also keeps the
  // debug launch artifacts separate from regular project builds.
  let target_dir = "\{project}/_build/moondbg"
  run_moon(project, [
    "check", "--target", "native", "-g", "--target-dir", target_dir,
  ])
  |> ignore
  let metadata = @fs.read_file("\{target_dir}/native/debug/check/packages.json")
  let pkg = select_package(
    parse_package_metadata(metadata.text()),
    target,
    directory,
  )
  let output = run_moon(project, [
    "run",
    "--build-only",
    "--target",
    "native",
    "-g",
    "--target-dir",
    target_dir,
    @fs.realpath(pkg.directory),
  ])
  let artifact = build_artifact(output)
  // moon run --build-only emits an absolute artifact path.
  let executable = validate_executable(artifact)
  (executable, @debugger.DebugContext::new(pkg.name, pkg.aliases))
}
