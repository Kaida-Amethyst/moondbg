///|
async test "source discovery only selects the exact production executable package" {
  guard toolchain_acceptance_enabled() else { return }
  toolchain_acceptance_mutex.acquire()
  defer toolchain_acceptance_mutex.release()
  let (_, moondbg) = require_toolchain()
  let directory = create_launch_project()
  defer @fs.rmdir(directory, recursive=true)
  @fs.write_file(
    "\{directory}/src/app/app_test.mbt",
    "test { assert_eq(1, 1) }",
  )
  for
    (relative, succeeds) in [
      ("src/app/main.mbt", true),
      ("src/lib/lib.mbt", false),
      ("src/app/app_test.mbt", false),
    ] {
    let (code, stdout, _) = @process.collect_output(
      moondbg,
      ["--resolve-source", "\{directory}/\{relative}"],
      inherit_env=true,
      extra_env={ "MOONDBG_LLDB_DAP": "/must-not-start-for-discovery" },
    )
    let result = @json.parse(stdout.text())
    if succeeds {
      assert_eq(code, 0)
      assert_true(
        result
        is {
          "protocolVersion": Number(1, ..),
          "name": String("example/launch/app"),
          "package": String(pkg),
          ..
        } &&
        pkg == @fs.realpath("\{directory}/src/app"),
        msg=result.stringify(),
      )
    } else {
      assert_true(code != 0)
      assert_true(
        result
        is { "protocolVersion": Number(1, ..), "error": String(message), .. } &&
        message.contains("未确定 main 函数位置"),
        msg=result.stringify(),
      )
    }
  }
  assert_false(@fs.exists("\{directory}/_build/moondbg/native/debug/build"))
  // Realpath comparisons must work even if the editor opened a symlink.
  @fs.symlink(target="\{directory}/src/app/main.mbt", "\{directory}/linked.mbt")
  let (code, stdout, _) = @process.collect_output(
    moondbg,
    ["--resolve-source", "\{directory}/linked.mbt"],
    inherit_env=true,
  )
  assert_eq(code, 0, msg=stdout.text())
}
