///|
test "CLI help names its required target" {
  let help = command().render_help()
  assert_true(help.contains("moondbg"))
  assert_true(help.contains("<target>"))
}

///|
test "CLI accepts exactly one executable" {
  let matches = command().parse(argv=["hello.exe"], env={})
  assert_eq(target_argument(matches), "hello.exe")
  assert_true(
    try {
      debug_context_argument(matches).current_package() |> ignore
      false
    } catch {
      @debugger.MissingCurrentPackage => true
      _ => false
    },
  )
}

///|
test "CLI constructs resolved package context" {
  let matches = command().parse(
    argv=[
      "--current-package", "example/app/main", "--package-alias", "util=example/lib/util",
      "--package-alias", "json=moonbitlang/core/json", "hello.exe",
    ],
    env={},
  )
  let context = debug_context_argument(matches)
  assert_eq(context.current_package(), "example/app/main")
  assert_eq(context.package_for_alias("util"), "example/lib/util")
  assert_eq(context.package_for_alias("json"), "moonbitlang/core/json")
  assert_true(
    try {
      context.package_for_alias("missing") |> ignore
      false
    } catch {
      @debugger.UnknownPackageAlias("missing") => true
      _ => false
    },
  )
}

///|
test "CLI rejects malformed or context-free aliases" {
  let malformed = command().parse(
    argv=[
      "--current-package", "example/app", "--package-alias", "util", "hello.exe",
    ],
    env={},
  )
  assert_true(
    try {
      debug_context_argument(malformed) |> ignore
      false
    } catch {
      InvalidPackageAliasArgument(_) => true
      _ => false
    },
  )
  let context_free = command().parse(
    argv=["--package-alias", "util=example/lib/util", "hello.exe"],
    env={},
  )
  assert_true(
    try {
      debug_context_argument(context_free) |> ignore
      false
    } catch {
      PackageAliasWithoutCurrentPackage => true
      _ => false
    },
  )
}
