///|
async fn create_launch_project() -> String {
  let directory = @fs.tmpdir(prefix="moondbg launch ")
  @fs.write_file(
    "\{directory}/moon.mod.json",
    "{\"name\":\"example/launch\",\"source\":\"src\"}",
  )
  @fs.mkdir("\{directory}/src/app", recursive=true)
  @fs.mkdir("\{directory}/src/lib", recursive=true)
  @fs.write_file(
    "\{directory}/src/app/moon.pkg",
    (
      #|pkgtype(kind: "executable")
      #|import { "example/launch/lib" @util, }
    ),
  )
  @fs.write_file(
    "\{directory}/src/app/main.mbt",
    (
      #|fn main {
      #|  let result = @util.increment(41)
      #|  println(result)
      #|}
    ),
  )
  @fs.write_file("\{directory}/src/lib/moon.pkg", "")
  @fs.write_file(
    "\{directory}/src/lib/lib.mbt",
    (
      #|pub fn increment(value : Int) -> Int {
      #|  value + 1
      #|}
    ),
  )
  directory
}

///|
async fn launch_failure(
  executable : String,
  directory : String,
  target : String,
) -> String {
  let (code, stdout, stderr) = @async.with_timeout(30000, () => {
    @process.collect_output(
      executable,
      [target],
      cwd=directory,
      inherit_env=true,
      extra_env={ "MOONDBG_LLDB_DAP": "/must-not-start-for-invalid-package" },
    )
  })
  assert_true(code != 0, msg="expected launch rejection for \{target}")
  assert_false(stdout.text().contains("(moondbg)"))
  let diagnostic = stderr.text()
  assert_true(diagnostic != "")
  assert_false(diagnostic.contains("debugger adapter failed"))
  diagnostic
}

///|
async test "package launch resolves source directories names aliases and paths containing spaces" {
  guard toolchain_acceptance_enabled() else { return }
  toolchain_acceptance_mutex.acquire()
  defer toolchain_acceptance_mutex.release()
  let (_, moondbg) = require_toolchain()
  let directory = create_launch_project()
  defer @fs.rmdir(directory, recursive=true)
  for
    (cwd, target) in [
      (directory, "app"),
      (directory, "example/launch/app"),
      (directory, "src/app"),
      ("\{directory}/src/app", "."),
    ] {
    let process = @pty_testkit.PtyProcess::spawn_debug(
      moondbg,
      cwd,
      package_name=target,
    )
    defer process.close()
    breakpoint_expect(process, "(moondbg) ", "launch \{target}")
    breakpoint_command(process, "b @util.increment", [
      "Breakpoint 1 pending at function @util.increment",
    ])
    breakpoint_command(process, "run", [
      "Breakpoint 1 verified at function @util.increment", "example/launch/lib.increment",
    ])
    // LLDB may spell the scalar type as int or Int; verify the binding/value.
    breakpoint_command(process, "p value", ["value:", " = 41"])
    breakpoint_command(process, "continue", [
      "42", "Process exited normally (code 0).",
    ])
    breakpoint_quit(process)
  }
}

///|
async test "package launch rejects libraries missing packages and nonexecutable files" {
  guard toolchain_acceptance_enabled() else { return }
  toolchain_acceptance_mutex.acquire()
  defer toolchain_acceptance_mutex.release()
  let (_, moondbg) = require_toolchain()
  let directory = create_launch_project()
  defer @fs.rmdir(directory, recursive=true)
  for target in ["lib", "missing-package", "src/app/main.mbt"] {
    launch_failure(moondbg, directory, target) |> ignore
  }
  assert_false(
    @fs.exists("\{directory}/_build/moondbg/native/debug/build/lib/lib.exe"),
  )
}

///|
async test "package launch rejects unsupported native targets and reports compiler failures" {
  guard toolchain_acceptance_enabled() else { return }
  toolchain_acceptance_mutex.acquire()
  defer toolchain_acceptance_mutex.release()
  let (_, moondbg) = require_toolchain()
  let directory = create_launch_project()
  defer @fs.rmdir(directory, recursive=true)
  @fs.write_file(
    "\{directory}/src/app/moon.pkg",
    (
      #|pkgtype(kind: "executable")
      #|supported_targets = "js"
    ),
  )
  let diagnostic = launch_failure(moondbg, directory, "app")
  assert_true(diagnostic.contains("native"), msg=diagnostic)
  @fs.write_file(
    "\{directory}/src/app/moon.pkg",
    "pkgtype(kind: \"executable\")",
  )
  @fs.write_file(
    "\{directory}/src/app/main.mbt",
    "fn main { println(missing_launch_value) }",
  )
  let diagnostic = launch_failure(moondbg, directory, "app")
  assert_true(diagnostic.contains("missing_launch_value"), msg=diagnostic)
}
