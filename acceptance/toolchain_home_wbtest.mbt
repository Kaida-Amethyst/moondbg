///|
async test "unset MOON_HOME resolves HOME and reaches both discovery and build worker children" {
  guard toolchain_acceptance_enabled() else { return }
  toolchain_acceptance_mutex.acquire()
  defer toolchain_acceptance_mutex.release()
  let (moon, moondbg) = require_toolchain()
  guard @env.get_env_var("MOON_HOME") is Some(toolchain) else {
    fail("toolchain")
  }
  let directory = @fs.tmpdir(prefix="moondbg home ")
  defer @fs.rmdir(directory, recursive=true)
  let home = "\{directory}/.moon"
  @fs.mkdir("\{home}/bin", recursive=true)
  @fs.symlink(target="\{toolchain}/bin/moonc", "\{home}/bin/moonc")
  @fs.symlink(target="\{toolchain}/lib", "\{home}/lib")
  @fs.write_file(
    "\{home}/bin/moon",
    (
      #|#!/bin/sh
      #|printf 'probe MOON_HOME=%s\n' "$MOON_HOME" >&2
      #|exec "$MOONDBG_TEST_REAL_MOON" "$@"
    ),
  )
  @fs.chmod("\{home}/bin/moon", 0o700)
  let project = create_launch_project()
  defer @fs.rmdir(project, recursive=true)
  for
    arguments in [
      ["--resolve-source", "\{project}/src/app/main.mbt"],
      ["--build-worker", "check", "--target", "native", "-g"],
    ] {
    let (code, stdout, stderr) = @async.with_timeout(30000, () => {
      @process.collect_output(
        "/usr/bin/env",
        ["-u", "MOON_HOME", moondbg, ..arguments],
        cwd=project,
        inherit_env=true,
        extra_env={ "HOME": directory, "MOONDBG_TEST_REAL_MOON": moon },
      )
    })
    assert_eq(code, 0, msg=stdout.text() + stderr.text())
    assert_true(
      stderr.text().contains("probe MOON_HOME=\{home}"),
      msg=stderr.text(),
    )
  }
  // An explicitly broken toolchain must not fall back to the working HOME.
  let (code, stdout, stderr) = @process.collect_output(
    moondbg,
    ["--resolve-source", "\{project}/src/app/main.mbt"],
    inherit_env=true,
    extra_env={ "HOME": directory, "MOON_HOME": "\{directory}/missing" },
  )
  assert_true(code != 0)
  assert_true(stdout.text().contains("\{directory}/missing/bin/moon"))
  assert_false(stderr.text().contains("probe MOON_HOME="))
}
