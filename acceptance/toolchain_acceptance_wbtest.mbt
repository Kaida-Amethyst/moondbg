///|
fn toolchain_acceptance_enabled() -> Bool {
  @env.get_env_var("MOONDBG_TOOLCHAIN_ACCEPTANCE") == Some("1")
}

///|
async fn collect_text(executable : String, arguments : Array[String]) -> String {
  let (status, output) = @process.collect_stdout(
    executable,
    arguments,
    inherit_env=true,
  )
  assert_eq(status, 0)
  output.text()
}

///|
async fn require_development_tool(moon_home : String, name : String) -> String {
  let path = "\{moon_home}/bin/\{name}"
  assert_true(@fs.kind(path, follow_symlink=false) is @fs.SymLink)
  assert_true(@fs.exists(path))
  assert_true(@fs.can_execute(path))
  path
}

///|
async fn require_development_toolchain() -> (String, String) {
  guard @env.get_env_var("MOON_HOME") is Some(moon_home) &&
    @env.get_env_var("HOME") is Some(home) else {
    fail("MOON_HOME and HOME must be set")
  }
  assert_eq(moon_home, "\{home}/.moon_dev")
  let moonc = require_development_tool(moon_home, "moonc")
  let moon = require_development_tool(moon_home, "moon")
  require_development_tool(moon_home, "moondbg") |> ignore
  let build_package_help = collect_text(moonc, ["build-package", "-help"])
  assert_true(build_package_help.contains("-debug-info {none|minimal|full}"))
  let link_core_help = collect_text(moonc, ["link-core", "-help"])
  assert_true(link_core_help.contains("-debug-info {none|minimal|full}"))
  let debug_help = collect_text(moon, ["debug", "--help"])
  assert_true(debug_help.contains("moon debug [OPTIONS] <PACKAGE>"))
  (moon, moon_home)
}

///|
async test "development toolchain drives the MoonBit DWARF REPL closure" {
  // The default test suite returns before reading paths or starting processes.
  guard toolchain_acceptance_enabled() else { return }
  let (moon, _moon_home) = require_development_toolchain()
  let repository = @fs.realpath(".")
  let fixture = "\{repository}/testdata/dwarf_probe"
  assert_true(@fs.exists("\{fixture}/main/main.mbt"))
  let process = @pty_testkit.PtyProcess::spawn_debug(moon, fixture)
  defer process.close()
  assert_eq(process.status(), 0)
  guard process.expect(b"(moondbg) ", timeout_ms=20000) else {
    process.wait(timeout_ms=100) |> ignore
    fail("moon debug did not open a prompt (PTY status \{process.status()})")
  }
  assert_true(process.write(b"b main\r"))
  assert_true(process.expect(b"Breakpoint 1 pending at function main"))
  assert_true(process.expect(b"(moondbg) "))
  assert_true(process.write(b"run\r"))
  assert_true(
    process.expect(b"Breakpoint 1 verified at function main", timeout_ms=20000),
  )
  assert_true(process.expect(b"in moonbit_main", timeout_ms=10000))
  assert_true(process.expect(b"(moondbg) "))

  assert_true(process.write(b"b main/main.mbt:13\r"))
  assert_true(process.expect(b"Breakpoint 2 verified at", timeout_ms=10000))
  assert_true(process.expect(b"main/main.mbt:13"))
  assert_true(process.expect(b"(moondbg) "))
  assert_true(process.write(b"b sum\r"))
  assert_true(process.expect(b"Breakpoint 3 verified at function sum"))
  assert_true(process.expect(b"(moondbg) "))
  assert_true(process.write(b"continue\r"))
  assert_true(process.expect(b"in moonbit_main", timeout_ms=10000))
  assert_true(process.expect(b"main/main.mbt:13"))
  assert_true(process.expect(b"(moondbg) "))
  assert_true(process.write(b"continue\r"))
  assert_true(process.expect(b"moondbg-dwarf-probe/main.sum", timeout_ms=10000))
  assert_true(process.expect(b"(moondbg) "))

  assert_true(process.write(b"b @probe.increment\r"))
  assert_true(
    process.expect(b"Breakpoint 4 verified at function @probe.increment"),
  )
  assert_true(process.expect(b"(moondbg) "))
  assert_true(process.write(b"continue\r"))
  assert_true(process.expect(b"moondbg-dwarf-probe/lib.increment"))
  assert_true(process.expect(b"(moondbg) "))
  assert_true(process.write(b"b @probe.identity\r"))
  assert_true(
    process.expect(
      b"Breakpoint 5 verified at function @probe.identity (2 locations)",
    ),
  )
  assert_true(process.expect(b"(moondbg) "))
  assert_true(process.write(b"continue\r"))
  assert_true(process.expect(b"moondbg-dwarf-probe/lib.identity|[Int]|"))
  assert_true(process.expect(b"(moondbg) "))
  assert_true(process.write(b"continue\r"))
  assert_true(process.expect(b"moondbg-dwarf-probe/lib.identity|[String]|"))
  assert_true(process.expect(b"(moondbg) "))
  assert_true(process.write(b"b missing\r"))
  assert_true(process.expect(b"Breakpoint 6 rejected at function missing"))
  assert_true(process.expect(b"(moondbg) "))

  assert_true(process.write(b"run\r"))
  assert_true(process.expect(b"Restarting program.", timeout_ms=20000))
  assert_true(process.expect(b"Breakpoint 2 verified at", timeout_ms=10000))
  assert_true(process.expect(b"Breakpoint 1 verified at function main"))
  assert_true(process.expect(b"Breakpoint 3 verified at function sum"))
  assert_true(
    process.expect(b"Breakpoint 4 verified at function @probe.increment"),
  )
  assert_true(
    process.expect(
      b"Breakpoint 5 verified at function @probe.identity (2 locations)",
    ),
  )
  assert_true(process.expect(b"Breakpoint 6 rejected at function missing"))
  assert_true(process.expect(b"in moonbit_main", timeout_ms=10000))
  assert_true(process.expect(b"(moondbg) "))
  assert_true(process.write(b"quit\r"))
  assert_true(process.expect(b"Debugger exited."))
  assert_true(process.wait(timeout_ms=10000))
}

///|
async test "development toolchain recursively prints MoonBit structs" {
  guard toolchain_acceptance_enabled() else { return }
  let (moon, _moon_home) = require_development_toolchain()
  let repository = @fs.realpath(".")
  let fixture = "\{repository}/testdata/dwarf_probe"
  assert_true(@fs.exists("\{fixture}/point/main.mbt"))
  let process = @pty_testkit.PtyProcess::spawn_debug(
    moon,
    fixture,
    package_name="point",
  )
  defer process.close()
  assert_eq(process.status(), 0)
  guard process.expect(b"(moondbg) ", timeout_ms=20000) else {
    process.wait(timeout_ms=100) |> ignore
    fail(
      "moon debug point did not open a prompt (PTY status \{process.status()})",
    )
  }
  assert_true(process.write(b"b distance\r"))
  assert_true(process.expect(b"Breakpoint 1 pending at function distance"))
  assert_true(process.expect(b"(moondbg) "))
  assert_true(process.write(b"b is_parallel\r"))
  assert_true(process.expect(b"Breakpoint 2 pending at function is_parallel"))
  assert_true(process.expect(b"(moondbg) "))
  assert_true(process.write(b"run\r"))
  assert_true(process.expect(b"point.distance", timeout_ms=20000))
  assert_true(process.expect(b"(moondbg) "))

  for _ in 0..<2 {
    assert_true(process.write(b"p p1\r"))
    assert_true(process.expect(b"p1: Point = {"))
    assert_true(process.expect(b"x: Double = 1"))
    assert_true(process.expect(b"y: Double = 2"))
    assert_true(process.expect(b"(moondbg) "))
  }

  for _ in 0..<2 {
    assert_true(process.write(b"p p1.x\r"))
    assert_true(process.expect(b"p1.x: Double = 1"))
    assert_true(process.expect(b"(moondbg) "))
  }
  assert_true(process.write(b"p p1.y\r"))
  assert_true(process.expect(b"p1.y: Double = 2"))
  assert_true(process.expect(b"(moondbg) "))
  assert_true(process.write(b"p p1.z\r"))
  assert_true(process.expect(b"Field 'z' was not found in 'p1'."))
  assert_true(process.expect(b"(moondbg) "))
  assert_true(process.write(b"p p1.x.value\r"))
  assert_true(
    process.expect(
      b"Cannot access field 'value' because 'p1.x' is not a struct.",
    ),
  )
  assert_true(process.expect(b"(moondbg) "))
  assert_true(process.write(b"p dx\r"))
  assert_true(
    process.expect(b"Variable 'dx' is unavailable at the current location."),
  )
  assert_true(process.expect(b"(moondbg) "))

  assert_true(process.write(b"next\r"))
  assert_true(process.expect(b"point.distance", timeout_ms=10000))
  assert_true(process.expect(b"(moondbg) "))
  assert_true(process.write(b"p p1.x\r"))
  assert_true(process.expect(b"p1.x: Double = 1"))
  assert_true(process.expect(b"(moondbg) "))

  assert_true(process.write(b"continue\r"))
  assert_true(process.expect(b"point.is_parallel", timeout_ms=10000))
  assert_true(process.expect(b"(moondbg) "))
  assert_true(process.write(b"p line1\r"))
  assert_true(process.expect(b"line1: Line = {"))
  assert_true(process.expect(b"start: Point = {"))
  assert_true(process.expect(b"x: Double = 1"))
  assert_true(process.expect(b"y: Double = 2"))
  assert_true(process.expect(b"end: Point = {"))
  assert_true(process.expect(b"x: Double = 4"))
  assert_true(process.expect(b"y: Double = 6"))
  assert_true(process.expect(b"(moondbg) "))
  assert_true(process.write(b"p line1.start.x\r"))
  assert_true(process.expect(b"line1.start.x: Double = 1"))
  assert_true(process.expect(b"(moondbg) "))
  assert_true(process.write(b"p line1.end.y\r"))
  assert_true(process.expect(b"line1.end.y: Double = 6"))
  assert_true(process.expect(b"(moondbg) "))
  for _ in 0..<2 {
    assert_true(process.write(b"p line1.start\r"))
    assert_true(process.expect(b"line1.start: Point = {"))
    assert_true(process.expect(b"x: Double = 1"))
    assert_true(process.expect(b"y: Double = 2"))
    assert_true(process.expect(b"(moondbg) "))
  }
  assert_true(process.write(b"p dx1\r"))
  assert_true(
    process.expect(b"Variable 'dx1' is unavailable at the current location."),
  )
  assert_true(process.expect(b"(moondbg) "))
  assert_true(process.write(b"quit\r"))
  assert_true(process.expect(b"Debugger exited."))
  assert_true(process.wait(timeout_ms=10000))
}

///|
async test "development toolchain prints bounded FixedArray values across stops" {
  guard toolchain_acceptance_enabled() else { return }
  let (moon, _moon_home) = require_development_toolchain()
  let repository = @fs.realpath(".")
  let fixture = "\{repository}/testdata/dwarf_probe"
  assert_true(@fs.exists("\{fixture}/fixed_array_int/main.mbt"))
  let process = @pty_testkit.PtyProcess::spawn_debug(
    moon,
    fixture,
    package_name="fixed_array_int",
  )
  defer process.close()
  assert_eq(process.status(), 0)
  guard process.expect(b"(moondbg) ", timeout_ms=20000) else {
    process.wait(timeout_ms=100) |> ignore
    fail(
      "moon debug fixed_array_int did not open a prompt (PTY status \{process.status()})",
    )
  }
  assert_true(process.write(b"b sum\r"))
  assert_true(process.expect(b"Breakpoint 1 pending at function sum"))
  assert_true(process.expect(b"(moondbg) "))
  assert_true(process.write(b"run\r"))
  assert_true(process.expect(b"fixed_array_int.sum", timeout_ms=20000))
  assert_true(process.expect(b"(moondbg) "))

  for _ in 0..<2 {
    assert_true(process.write(b"p arr\r"))
    assert_true(process.expect(b"arr: FixedArray[Int] with length = 10"))
    assert_true(process.expect(b"[1, 2, 3, 4, 5, 6, 7, 8, 9, 10]"))
    assert_true(process.expect(b"(moondbg) "))
  }

  assert_true(process.write(b"continue\r"))
  assert_true(process.expect(b"fixed_array_int.sum", timeout_ms=10000))
  assert_true(process.expect(b"(moondbg) "))
  for _ in 0..<2 {
    assert_true(process.write(b"p arr\r"))
    assert_true(process.expect(b"arr: FixedArray[Int] with length = 100"))
    assert_true(
      process.expect(
        b"[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, ..., 100]",
      ),
    )
    assert_true(process.expect(b"(moondbg) "))
  }
  assert_true(process.write(b"quit\r"))
  assert_true(process.expect(b"Debugger exited."))
  assert_true(process.wait(timeout_ms=10000))
}
