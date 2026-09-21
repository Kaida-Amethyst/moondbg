///|
async fn breakpoint_marker_line(fixture : String, marker : String) -> Int {
  let source = @fs.read_file("\{fixture}/breakpoint_management/main.mbt").text()
  let matches = source
    .split("\n")
    .filter(line => line.contains(marker))
    .collect()
  guard matches is [statement] else {
    fail("expected unique fixture marker \{marker}")
  }
  unique_source_line(
    "\{fixture}/breakpoint_management/main.mbt",
    statement.trim().to_owned(),
  )
}

///|
fn breakpoint_expect(
  process : @pty_testkit.PtyProcess,
  expected : String,
  command : String,
) -> Unit raise {
  assert_true(
    process.expect(@utf8.encode(expected), timeout_ms=20000),
    msg="after '\{command}', expected '\{expected}'",
  )
}

///|
fn breakpoint_command(
  process : @pty_testkit.PtyProcess,
  command : String,
  expected : Array[String],
) -> Unit raise {
  assert_true(
    process.write(@utf8.encode("\{command}\r")),
    msg="write \{command}",
  )
  for fragment in expected {
    breakpoint_expect(process, fragment, command)
  }
  breakpoint_expect(process, "(moondbg) ", command)
}

///|
fn breakpoint_stopped(
  process : @pty_testkit.PtyProcess,
  command : String,
  function_name : String,
  source_line? : Int? = None,
) -> Unit raise {
  let expected = ["Stopped (breakpoint) in \{function_name}"]
  if source_line is Some(line) {
    expected.push("breakpoint_management/main.mbt:\{line}")
  }
  breakpoint_command(process, command, expected)
}

///|
fn breakpoint_quit(process : @pty_testkit.PtyProcess) -> Unit raise {
  assert_true(process.write(b"quit\r"))
  breakpoint_expect(process, "Debugger exited.", "quit")
  assert_true(process.wait(timeout_ms=10000))
}

///|
async test "T07 exact and source duplicate management preserves stable ids across runs" {
  guard toolchain_acceptance_enabled() else { return }
  toolchain_acceptance_mutex.acquire()
  defer toolchain_acceptance_mutex.release()
  let (_, moondbg) = require_toolchain()
  let fixture = "\{@fs.realpath(".")}/testdata/dwarf_probe"
  let ordinary_line = breakpoint_marker_line(
    fixture, "MOONDBG_BREAKPOINT_ORDINARY",
  )
  let checkpoint_line = breakpoint_marker_line(
    fixture, "MOONDBG_BREAKPOINT_CHECKPOINT",
  )
  let ordinary = "breakpoint_management/main.mbt:\{ordinary_line}"
  let checkpoint = "breakpoint_management/main.mbt:\{checkpoint_line}"
  let process = @pty_testkit.PtyProcess::spawn_debug(
    moondbg,
    fixture,
    package_name="breakpoint_management",
  )
  defer process.close()
  breakpoint_expect(process, "(moondbg) ", "startup")
  breakpoint_command(process, "breakpoints", ["No breakpoints."])
  breakpoint_command(process, "b main", [
    "Breakpoint 1 pending at function main",
  ])
  breakpoint_command(process, "b main", [
    "Breakpoint 2 pending at function main",
  ])
  breakpoint_command(process, "disable -1", [
    "disable requires one positive decimal breakpoint ID",
  ])
  breakpoint_command(process, "delete 999", ["Breakpoint 999 was not found."])
  breakpoint_command(process, "disable 1", ["Breakpoint 1 disabled."])
  breakpoint_command(process, "disable 1", ["Breakpoint 1 is already disabled."])
  breakpoint_stopped(process, "run", "main")
  breakpoint_command(process, "delete 2", ["Breakpoint 2 deleted."])
  breakpoint_command(process, "b \{ordinary}", [
    "Breakpoint 3 verified at", ordinary,
  ])
  breakpoint_command(process, "b \{ordinary}", [
    "Breakpoint 4 verified at", ordinary,
  ])
  breakpoint_command(process, "b \{checkpoint}", [
    "Breakpoint 5 verified at", checkpoint,
  ])
  breakpoint_command(process, "disable 3", ["Breakpoint 3 disabled."])
  breakpoint_stopped(
    process,
    "continue",
    "@Kaida-Amethyst/moondbg-dwarf-probe/breakpoint_management.ordinary",
    source_line=Some(ordinary_line),
  )
  breakpoint_command(process, "p value", ["value: Int = 10"])
  breakpoint_command(process, "locals", ["Locals:", "value: Int = 10"])
  breakpoint_command(process, "disable 4", ["Breakpoint 4 disabled."])
  breakpoint_command(process, "p value", ["value: Int = 10"])
  breakpoint_stopped(
    process,
    "continue",
    "main",
    source_line=Some(checkpoint_line),
  )
  breakpoint_command(process, "delete 5", ["Breakpoint 5 deleted."])
  breakpoint_command(process, "delete 3", ["Breakpoint 3 deleted."])
  breakpoint_command(process, "delete 4", ["Breakpoint 4 deleted."])
  breakpoint_command(process, "continue", ["Process exited normally (code 0)."])
  breakpoint_command(process, "breakpoints", [
    "1  disabled  requested: function main", "installation: not installed",
  ])
  breakpoint_command(process, "enable 1", [
    "Breakpoint 1 enabled (not installed).",
  ])
  breakpoint_command(process, "b \{checkpoint}", ["Breakpoint 6 pending at"])
  breakpoint_command(process, "delete 6", ["Breakpoint 6 deleted."])
  breakpoint_stopped(process, "run", "main")
  breakpoint_command(process, "disable 1", ["Breakpoint 1 disabled."])
  breakpoint_command(process, "continue", ["Process exited normally (code 0)."])
  breakpoint_command(process, "run", ["Process exited normally (code 0)."])
  breakpoint_command(process, "delete 1", ["Breakpoint 1 deleted."])
  breakpoint_command(process, "breakpoints", ["No breakpoints."])
  breakpoint_quit(process)
}

///|
async test "T07 family all locations zero handles and selected frame survive management" {
  guard toolchain_acceptance_enabled() else { return }
  toolchain_acceptance_mutex.acquire()
  defer toolchain_acceptance_mutex.release()
  let (_, moondbg) = require_toolchain()
  let fixture = "\{@fs.realpath(".")}/testdata/dwarf_probe"
  let checkpoint_line = breakpoint_marker_line(
    fixture, "MOONDBG_BREAKPOINT_CHECKPOINT",
  )
  let second_checkpoint_line = breakpoint_marker_line(
    fixture, "MOONDBG_BREAKPOINT_SECOND_CHECKPOINT",
  )
  let generic_line = breakpoint_marker_line(
    fixture, "MOONDBG_BREAKPOINT_GENERIC",
  )
  let process = @pty_testkit.PtyProcess::spawn_debug(
    moondbg,
    fixture,
    package_name="breakpoint_management",
  )
  defer process.close()
  breakpoint_expect(process, "(moondbg) ", "startup")
  breakpoint_command(process, "b main", [
    "Breakpoint 1 pending at function main",
  ])
  breakpoint_command(process, "b identity", [
    "Breakpoint 2 pending at function identity",
  ])
  breakpoint_command(
    process,
    "b breakpoint_management/main.mbt:\{checkpoint_line}",
    ["Breakpoint 3 pending at"],
  )
  breakpoint_command(
    process,
    "b breakpoint_management/main.mbt:\{second_checkpoint_line}",
    ["Breakpoint 4 pending at"],
  )
  breakpoint_command(process, "b missing", [
    "Breakpoint 5 pending at function missing",
  ])
  breakpoint_stopped(process, "run", "main")
  breakpoint_command(process, "breakpoints", [
    "2  enabled  requested: function identity",
    "locations: 2",
    "actual:",
    "breakpoint_management/main.mbt:\{generic_line}",
    "5  enabled  requested: function missing",
    "installation: current: rejected:",
    "locations: 0",
  ])
  breakpoint_command(process, "disable 2", ["Breakpoint 2 disabled."])
  breakpoint_stopped(process, "run", "main")
  breakpoint_stopped(
    process,
    "continue",
    "main",
    source_line=Some(checkpoint_line),
  )
  breakpoint_command(process, "enable 2", [
    "Breakpoint 2 enabled (current: verified).",
  ])
  breakpoint_command(process, "delete 3", ["Breakpoint 3 deleted."])
  breakpoint_command(process, "delete 1", ["Breakpoint 1 deleted."])
  breakpoint_command(process, "disable 5", ["Breakpoint 5 disabled."])
  breakpoint_command(process, "enable 5", [
    "Breakpoint 5 enabled (current: rejected:",
  ])
  breakpoint_command(process, "delete 5", ["Breakpoint 5 deleted."])
  breakpoint_stopped(
    process,
    "continue",
    "@Kaida-Amethyst/moondbg-dwarf-probe/breakpoint_management.identity[Int]",
    source_line=Some(generic_line),
  )
  breakpoint_command(process, "p value", ["value: Int = 21"])
  breakpoint_command(process, "frame 1", ["Selected frame #1: main"])
  // The current toolchain reports caller locals as unavailable before management.
  // Preserve that observation; the selected top frame's value remains readable.
  breakpoint_command(process, "p second", [
    "Variable 'second' is unavailable at the current location.",
  ])
  breakpoint_command(process, "locals", [
    "Locals:", "second: Int = <unavailable>",
  ])
  breakpoint_command(process, "disable 4", ["Breakpoint 4 disabled."])
  breakpoint_command(process, "enable 4", [
    "Breakpoint 4 enabled (current: verified).",
  ])
  breakpoint_command(process, "bt", ["* #1 [moonbit] main"])
  breakpoint_command(process, "p second", [
    "Variable 'second' is unavailable at the current location.",
  ])
  breakpoint_command(process, "locals", [
    "Locals:", "second: Int = <unavailable>",
  ])
  breakpoint_command(process, "list", ["second_int"])
  breakpoint_command(process, "frame 0", ["Selected frame #0:"])
  breakpoint_command(process, "p value", ["value: Int = 21"])
  breakpoint_stopped(
    process,
    "continue",
    "@Kaida-Amethyst/moondbg-dwarf-probe/breakpoint_management.identity[Double]",
    source_line=Some(generic_line),
  )
  breakpoint_command(process, "p value", ["value: Double = 2.5"])
  breakpoint_command(process, "delete 2", ["Breakpoint 2 deleted."])
  breakpoint_stopped(
    process,
    "continue",
    "main",
    source_line=Some(second_checkpoint_line),
  )
  breakpoint_command(process, "delete 4", ["Breakpoint 4 deleted."])
  breakpoint_command(process, "continue", ["Process exited normally (code 0)."])
  breakpoint_command(process, "breakpoints", ["No breakpoints."])
  breakpoint_quit(process)
}
