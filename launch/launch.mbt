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
pub struct PreparedTarget {
  executable : String
  debug_context : @debugger.DebugContext
  working_directory : String
  project_sources : Array[String]
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
pub async fn prepare_target(
  target : String,
  output~ : async (String, String) -> Unit,
) -> PreparedTarget {
  let directory = if @fs.exists(target) {
    match @fs.kind(target) {
      Regular => {
        let executable = validate_executable(target)
        return {
          executable,
          debug_context: @debugger.DebugContext::empty(),
          working_directory: @fs.realpath("."),
          project_sources: [],
        }
      }
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
  let metadata = check_packages(project, output~)
  let pkg = select_package(parse_package_metadata(metadata), target, directory)
  let output = run_moon(
    project,
    [
      "run",
      "--build-only",
      "--target",
      "native",
      "-g",
      "--target-dir",
      target_dir,
      @fs.realpath(pkg.directory),
    ],
    output~,
  )
  let artifact = build_artifact(output)
  // moon run --build-only emits an absolute artifact path.
  let executable = validate_executable(artifact)
  {
    executable,
    debug_context: @debugger.DebugContext::new(pkg.name, pkg.aliases),
    working_directory: project,
    project_sources: local_debug_sources(metadata),
  }
}

///|
async fn validate_executable(path : String) -> String {
  guard @fs.exists(path) && @fs.kind(path) is Regular && @fs.can_execute(path) else {
    raise LaunchError("file is missing or not executable: \{path}")
  }
  @fs.realpath(path)
}
