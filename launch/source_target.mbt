///|
async fn check_packages(
  project : String,
  output~ : async (String, String) -> Unit,
  isolated? : Bool = true,
) -> String {
  let target_dir = "\{project}/_build/moondbg"
  run_moon(
    project,
    ["check", "--target", "native", "-g", "--target-dir", target_dir],
    output~,
    isolated~,
  )
  |> ignore
  @fs.read_file("\{target_dir}/native/debug/check/packages.json").text()
}

///|
/// Find the exact compiler-listed production source, never a nearby runnable
/// package. A library, test file or ignored file must not select another main.
async fn source_package(text : String, source : String) -> PackageMetadata {
  let parsed = @json.parse(text)
  let packages = parse_package_metadata(text)
  guard parsed is { "packages": Array(entries), .. } else {
    raise LaunchError("invalid package metadata")
  }
  let matches : Array[PackageMetadata] = []
  for entry in entries {
    guard entry is { "is-third-party": False, "files": Object(files), .. } else {
      continue
    }
    for path, condition in files {
      guard condition
        is { "backend": Array(backends), "optlevel": Array(levels), .. } &&
        backends.contains(Json("Native")) &&
        levels.contains(Json("Debug")) else {
        continue
      }
      guard @fs.exists(path) && @fs.realpath(path) == source else { continue }
      let directory = metadata_string(entry, "root-path")
      for pkg in packages {
        if pkg.directory == directory {
          matches.push(pkg)
        }
      }
    }
  }
  guard matches is [pkg] && pkg.is_main && pkg.supports_native else {
    raise LaunchError(
      "未确定 main 函数位置：当前源码不属于 native 可执行包；不会自动选择其他入口。",
    )
  }
  pkg
}

///|
/// Machine-facing source discovery. Only checks metadata, never builds/runs a
/// target or starts LLDB. The caller owns this CLI process group, including
/// moon and compiler children, so discovery must not create a nested group.
pub async fn resolve_source(
  path : String,
  output~ : async (String, String) -> Unit,
) -> Json {
  guard path.has_prefix("/") &&
    path.has_suffix(".mbt") &&
    @fs.exists(path) &&
    @fs.kind(path) is Regular else {
    raise LaunchError(
      "未确定 main 函数位置：请打开并保存 MoonBit 源码文件。",
    )
  }
  let source = @fs.realpath(path)
  guard source.rev_find("/") is Some(separator) else {
    raise LaunchError("Invalid absolute source path")
  }
  let project = project_root(
    if separator == 0 {
      "/"
    } else {
      source[:separator].to_owned()
    },
  )
  let metadata = check_packages(project, output~, isolated=false)
  let pkg = source_package(metadata, source)
  {
    "protocolVersion": 1,
    "source": source,
    "package": @fs.realpath(pkg.directory),
    "name": pkg.name,
  }
}
