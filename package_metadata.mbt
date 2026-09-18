///|
priv suberror LaunchFailure {
  LaunchError(String)
} derive(Debug)

///|
priv struct PackageMetadata {
  directory : String
  name : String
  relative_name : String
  supports_native : Bool
  is_main : Bool
  aliases : Array[(String, String)]
}

///|
fn metadata_string(value : Json, key : String) -> String raise LaunchFailure {
  guard value is Object(fields) && fields.get(key) is Some(String(value)) else {
    raise LaunchError("invalid moon package metadata: missing string '\{key}'")
  }
  value
}

///|
fn parse_package_metadata(text : String) -> Array[PackageMetadata] raise {
  let json = @json.parse(text) catch {
    _ => raise LaunchError("invalid moon package metadata: expected JSON")
  }
  guard json is { "packages": Array(packages), .. } else {
    raise LaunchError("invalid moon package metadata: missing packages array")
  }
  let result = []
  for pkg in packages {
    match pkg {
      { "is-third-party": True, .. } => continue
      { "is-third-party": False, .. } => ()
      _ =>
        raise LaunchError(
          "invalid moon package metadata: missing is-third-party flag",
        )
    }
    let root = metadata_string(pkg, "root")
    let relative_name = metadata_string(pkg, "rel")
    let name = if relative_name == "" {
      root
    } else {
      "\{root}/\{relative_name}"
    }
    guard pkg
      is {
        "is-main": is_main,
        "deps": Array(deps),
        "supported-targets": Array(targets),
        ..
      } &&
      is_main is (True | False) else {
      raise LaunchError("invalid moon package metadata for \{name}")
    }
    let aliases = deps.map(dep => {
      (metadata_string(dep, "alias"), metadata_string(dep, "path"))
    })
    result.push({
      directory: metadata_string(pkg, "root-path"),
      name,
      relative_name,
      is_main: is_main is True,
      supports_native: targets.any(target => target is String("Native")),
      aliases,
    })
  }
  result
}

///|
fn build_artifact(text : String) -> String raise {
  let json = @json.parse(text) catch {
    _ =>
      raise LaunchError("invalid moon run --build-only output: expected JSON")
  }
  guard json is { "artifacts_path": [String(path)], .. } && path != "" else {
    raise LaunchError(
      "moon run --build-only did not return exactly one executable",
    )
  }
  path
}
