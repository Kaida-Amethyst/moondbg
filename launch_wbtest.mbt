///|
fn launch_test_metadata() -> Array[PackageMetadata] raise {
  parse_package_metadata(
    (
      #|{"packages":[
      #| {"is-third-party":false,"is-main":true,"root":"example/app","rel":"main","root-path":"/project/src/main","supported-targets":["Native"],"deps":[{"alias":"util","path":"example/lib/tools"}]},
      #| {"is-third-party":false,"is-main":false,"root":"example/app","rel":"lib","root-path":"/project/src/lib","supported-targets":["Native"],"deps":[]},
      #| {"is-third-party":false,"is-main":true,"root":"example/app","rel":"web","root-path":"/project/src/web","supported-targets":["Js"],"deps":[]},
      #| {"is-third-party":true}
      #|]}
    ),
  )
}

///|
async test "package names resolve from metadata and preserve import aliases" {
  let packages = launch_test_metadata()
  assert_eq(packages.length(), 3)
  for selector in ["main", "example/app/main"] {
    let pkg = select_package(packages, selector, None)
    assert_eq(pkg.directory, "/project/src/main")
    let context = @debugger.DebugContext::new(pkg.name, pkg.aliases)
    assert_eq(context.current_package(), "example/app/main")
    assert_eq(context.package_for_alias("util"), "example/lib/tools")
  }
}

///|
async test "package selection rejects libraries unsupported targets and unknown names" {
  let packages = launch_test_metadata()
  for
    (selector, diagnostic) in [
      ("lib", "cannot generate an executable"),
      ("web", "does not support the native target"),
      ("missing", "does not identify one local MoonBit package"),
    ] {
    assert_true(
      try {
        select_package(packages, selector, None) |> ignore
        false
      } catch {
        LaunchError(message) => message.contains(diagnostic)
        _ => false
      },
    )
  }
}

///|
test "build output requires exactly one nonempty executable artifact" {
  assert_eq(
    build_artifact("{\"artifacts_path\":[\"/tmp/path with spaces/main.exe\"]}"),
    "/tmp/path with spaces/main.exe",
  )
  for
    output in [
      "{}", "{\"artifacts_path\":[]}", "{\"artifacts_path\":[\"a\",\"b\"]}", "{\"artifacts_path\":[\"\"]}",
      "invalid json",
    ] {
    assert_true(
      try {
        build_artifact(output) |> ignore
        false
      } catch {
        _ => true
      },
    )
  }
}

///|
test "metadata root package names omit the trailing separator" {
  let packages = parse_package_metadata(
    (
      #|{"packages":[{"is-third-party":false,"is-main":true,"root":"example/app","rel":"","root-path":"/project","supported-targets":["Native"],"deps":[]}]}
    ),
  )
  assert_eq(packages[0].name, "example/app")
}

///|
test "metadata schema errors are rejected" {
  for
    text in [
      "{}",
      (
        #|{"packages":[{"is-third-party":false}]}
      ),
      (
        #|{"packages":[{"is-third-party":false,"is-main":true,"root":"example/app","rel":"main","root-path":"/project","supported-targets":["Native"],"deps":[{"path":"example/lib"}]}]}
      ),
    ] {
    assert_true(
      try {
        parse_package_metadata(text) |> ignore
        false
      } catch {
        _ => true
      },
    )
  }
}

///|
async test "directory selection canonicalizes symlinks" {
  let directory = @fs.tmpdir(prefix="moondbg-launch-test-")
  defer (@fs.rmdir(directory, recursive=true) catch { _ => () })
  let source = "\{directory}/main"
  @fs.mkdir(source)
  @fs.symlink(target=source, "\{directory}/alias")
  let pkg : PackageMetadata = {
    directory: "\{directory}/alias",
    name: "example/app/main",
    relative_name: "main",
    supports_native: true,
    is_main: true,
    aliases: [],
  }
  assert_eq(
    select_package([pkg], source, Some(@fs.realpath(source))).name,
    "example/app/main",
  )
}

///|
async test "ambiguous package names are rejected" {
  let packages = launch_test_metadata()
  assert_true(
    try {
      select_package([packages[0], packages[0]], "main", None) |> ignore
      false
    } catch {
      LaunchError(message) =>
        message.contains("does not identify one local MoonBit package")
      _ => false
    },
  )
}
