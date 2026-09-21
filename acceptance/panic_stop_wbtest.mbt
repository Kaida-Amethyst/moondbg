///|
async test "precompiled panic without project metadata asks for manual frame selection" {
  guard toolchain_acceptance_enabled() else { return }
  toolchain_acceptance_mutex.acquire()
  defer toolchain_acceptance_mutex.release()
  let (_, moondbg) = require_toolchain()
  let fixture = "\{@fs.realpath(".")}/testdata/dwarf_probe"
  let builder = @pty_testkit.PtyProcess::spawn_debug(
    moondbg,
    fixture,
    package_name="panic_context",
  )
  defer builder.close()
  breakpoint_expect(builder, "(moondbg) ", "build fixture")
  breakpoint_quit(builder)
  let process = @pty_testkit.PtyProcess::spawn_debug(
    moondbg,
    fixture,
    package_name="_build/moondbg/native/debug/build/panic_context/panic_context.exe",
  )
  defer process.close()
  breakpoint_expect(process, "(moondbg) ", "precompiled launch")
  breakpoint_command(process, "run", [
    "Stopped (MoonBit panic)", "Project source context is unavailable; no frame selected.",
  ])
  breakpoint_command(process, "bt --all", [
    "moonbit_panic", "panic_context_lib.fail",
  ])
  breakpoint_command(process, "locals", ["No current frame is selected."])
  breakpoint_command(process, "p value", ["No current frame is selected."])
  breakpoint_command(process, "frame 2", [
    "Selected frame #2:", "panic_context_lib/fail.mbt:4",
  ])
  breakpoint_command(process, "p value", ["value:", " = 42"])
  breakpoint_quit(process)
}

///|
async test "panic selects a local library caller past core abort and inspects that frame" {
  guard toolchain_acceptance_enabled() else { return }
  toolchain_acceptance_mutex.acquire()
  defer toolchain_acceptance_mutex.release()
  let (_, moondbg) = require_toolchain()
  let fixture = "\{@fs.realpath(".")}/testdata/dwarf_probe"
  let process = @pty_testkit.PtyProcess::spawn_debug(
    moondbg,
    fixture,
    package_name="panic_context",
  )
  defer process.close()
  breakpoint_expect(process, "(moondbg) ", "startup")
  breakpoint_command(process, "run", [
    "Stopped (MoonBit panic) in @Kaida-Amethyst/moondbg-dwarf-probe/panic_context_lib.fail",
    "panic_context_lib/fail.mbt:4",
  ])
  breakpoint_command(process, "locals", ["value", "42"])
  breakpoint_command(process, "p value", ["value:", " = 42"])
  breakpoint_command(process, "bt --all", [
    "moonbit_panic", "abort", "* #2", "panic_context_lib.fail",
  ])
  breakpoint_quit(process)
}

///|
async test "REPL panic stop is automatic and independent of user function breakpoints" {
  guard toolchain_acceptance_enabled() else { return }
  toolchain_acceptance_mutex.acquire()
  defer toolchain_acceptance_mutex.release()
  let (_, moondbg) = require_toolchain()
  let fixture = "\{@fs.realpath(".")}/testdata/dwarf_probe"
  let process = @pty_testkit.PtyProcess::spawn_debug(
    moondbg,
    fixture,
    package_name="panic_stop",
  )
  defer process.close()
  breakpoint_expect(process, "(moondbg) ", "startup")
  breakpoint_command(process, "breakpoints", ["No breakpoints."])
  breakpoint_command(process, "run", ["Stopped (MoonBit panic)"])
  breakpoint_command(process, "breakpoints", ["No breakpoints."])
  breakpoint_command(process, "bt --all", ["moonbit_panic", "panic_stop.fail"])
  // Logical numbering still starts at 1. Restart installs a fresh internal
  // stop; removing the exact-function set at main must not remove that stop.
  breakpoint_command(process, "b main", [
    "Breakpoint 1 verified at function main",
  ])
  breakpoint_command(process, "run", ["Stopped (breakpoint) in main"])
  breakpoint_command(process, "disable 1", ["Breakpoint 1 disabled."])
  breakpoint_command(process, "enable 1", [
    "Breakpoint 1 enabled (current: verified).",
  ])
  breakpoint_command(process, "delete 1", ["Breakpoint 1 deleted."])
  breakpoint_command(process, "breakpoints", ["No breakpoints."])
  breakpoint_command(process, "continue", ["Stopped (MoonBit panic)"])
  breakpoint_quit(process)
}
