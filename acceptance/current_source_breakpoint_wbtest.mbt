///|
async test "bare line breakpoints use the selected source across real caller frames" {
  guard toolchain_acceptance_enabled() else { return }
  let (moon, _) = require_development_toolchain()
  let fixture = "\{@fs.realpath(".")}/testdata/dwarf_probe"
  let main_line = unique_source_line(
    "\{fixture}/stack_frames/main.mbt",
    "let main_after_call = stack_result + main_seed",
  )
  let support_line = unique_source_line(
    "\{fixture}/stack_support/stack_support.mbt",
    "let cross_after_call = cross_result + cross_total",
  )
  let process = @pty_testkit.PtyProcess::spawn_debug(
    moon,
    fixture,
    package_name="stack_frames",
  )
  defer process.close()
  breakpoint_expect(process, "(moondbg) ", "startup")
  breakpoint_command(process, "b \{main_line}", [
    "Cannot set breakpoint by line: no stopped frame is selected. Use b <file>:<line>.",
  ])
  breakpoint_command(process, "b main", [
    "Breakpoint 1 pending at function main",
  ])
  breakpoint_command(process, "r", ["Stopped (breakpoint) in main"])
  breakpoint_command(process, "b \{main_line}", [
    "Breakpoint 2 verified at",
    "stack_frames/main.mbt:\{main_line}",
  ])
  breakpoint_command(process, "b @stack_support.enter_stack", [
    "Breakpoint 3 verified at function @stack_support.enter_stack",
  ])
  breakpoint_command(process, "c", [
    // Toolchain versions use either $ or @ in the DWARF display name.
    // This test verifies the selected function/source, not that decoration.
    "Stopped (breakpoint) in ", "Kaida-Amethyst/moondbg-dwarf-probe/stack_support.enter_stack",
  ])
  breakpoint_command(process, "break \{support_line}", [
    "Breakpoint 4 verified at",
    "stack_support/stack_support.mbt:\{support_line}",
  ])
  breakpoint_command(process, "up", ["Selected frame #1: main"])
  breakpoint_command(process, "  break\t\{main_line}", [
    "Breakpoint 5 verified at",
    "stack_frames/main.mbt:\{main_line}",
  ])
  breakpoint_command(process, "breakpoints", [
    "2  enabled  requested:",
    "stack_frames/main.mbt:\{main_line}",
    "4  enabled  requested:",
    "stack_support/stack_support.mbt:\{support_line}",
    "5  enabled  requested:",
    "stack_frames/main.mbt:\{main_line}",
  ])
  breakpoint_command(process, "down", [
    "Selected frame #0:", "stack_support.enter_stack",
  ])
  breakpoint_command(process, "c", [
    "Stopped (breakpoint) in ",
    "Kaida-Amethyst/moondbg-dwarf-probe/stack_support.enter_stack",
    "stack_support/stack_support.mbt:\{support_line}",
  ])
  breakpoint_command(process, "c", [
    "Stopped (breakpoint) in main",
    "stack_frames/main.mbt:\{main_line}",
  ])
  breakpoint_command(process, "c", ["Process exited normally (code 0)."])
  breakpoint_command(process, "b \{main_line}", [
    "Cannot set breakpoint by line: no stopped frame is selected. Use b <file>:<line>.",
  ])
  breakpoint_quit(process)
}
