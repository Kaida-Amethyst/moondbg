///|
// Moon's native async test driver runs up to ten tests concurrently in one
// event loop, even with --no-parallelize. The PTY helper waits in synchronous
// C poll calls, which would block DAP I/O and expire other tests' deadlines.
// Hold this mutex for each enabled acceptance test's complete lifetime,
// including child-process cleanup. Disabled tests never acquire it.
let toolchain_acceptance_mutex : @async.Mutex = @async.Mutex()

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
async fn require_tool(moon_home : String, name : String) -> String {
  let path = "\{moon_home}/bin/\{name}"
  assert_true(@fs.exists(path))
  assert_true(@fs.can_execute(path))
  path
}

///|
async fn require_toolchain() -> (String, String) {
  guard @env.get_env_var("MOON_HOME") is Some(moon_home) else {
    fail("MOON_HOME must select the toolchain used to build debug targets")
  }
  let moonc = require_tool(moon_home, "moonc")
  let moon = require_tool(moon_home, "moon")
  let moondbg = match @env.get_env_var("MOONDBG_ACCEPTANCE_EXECUTABLE") {
    Some(path) => @fs.realpath(path)
    None => @fs.realpath("_build/native/debug/build/main/main.exe")
  }
  assert_true(@fs.can_execute(moondbg))
  let build_package_help = collect_text(moonc, ["build-package", "-help"])
  assert_true(build_package_help.contains("-g save debugging information"))
  assert_true(build_package_help.contains("-O0  turn off optimization"))
  let link_core_help = collect_text(moonc, ["link-core", "-help"])
  assert_true(link_core_help.contains("-g save debugging information"))
  assert_true(link_core_help.contains("-O0  turn off optimization"))
  let run_help = collect_text(moon, ["run", "--help"])
  assert_true(run_help.contains("--build-only"))
  assert_true(run_help.contains("--target"))
  assert_true(run_help.contains("--debug"))
  (moon, moondbg)
}

///|
async fn unique_source_line(source_path : String, statement : String) -> Int {
  let source = @fs.read_file(source_path).text()
  let mut matched_line : Int? = None
  for line_index, line in source.split("\n") {
    guard line.trim() == statement else { continue }
    guard matched_line is None else {
      fail("source statement is not unique in \{source_path}: \{statement}")
    }
    matched_line = Some(line_index + 1)
  }
  guard matched_line is Some(line) else {
    fail("source statement was not found in \{source_path}: \{statement}")
  }
  line
}

///|
async test "selected toolchain drives the MoonBit DWARF REPL closure" {
  // The default test suite returns before reading paths or starting processes.
  guard toolchain_acceptance_enabled() else { return }
  toolchain_acceptance_mutex.acquire()
  defer toolchain_acceptance_mutex.release()
  let (_, moondbg) = require_toolchain()
  let repository = @fs.realpath(".")
  let fixture = "\{repository}/testdata/dwarf_probe"
  let main_source = "\{fixture}/pkg_scope/main.mbt"
  assert_true(@fs.exists(main_source))
  let source_breakpoint_line = unique_source_line(
    main_source, "let result = @probe.increment(sum(arr)) - 1",
  )
  let source_breakpoint = "pkg_scope/main.mbt:\{source_breakpoint_line}"
  let process = @pty_testkit.PtyProcess::spawn_debug(
    moondbg,
    fixture,
    package_name="pkg_scope",
  )
  defer process.close()
  assert_eq(process.status(), 0)
  guard process.expect(b"(moondbg) ", timeout_ms=20000) else {
    process.wait(timeout_ms=100) |> ignore
    fail("moondbg did not open a prompt (PTY status \{process.status()})")
  }
  assert_true(process.write(b"b main\r"))
  assert_true(process.expect(b"Breakpoint 1 pending at function main"))
  assert_true(process.expect(b"(moondbg) "))
  assert_true(process.write(b"run\r"))
  assert_true(
    process.expect(b"Breakpoint 1 verified at function main", timeout_ms=20000),
  )
  assert_true(process.expect(b"in main", timeout_ms=10000))
  assert_true(process.expect(b"(moondbg) "))

  assert_true(process.write(@utf8.encode("b \{source_breakpoint}\r")))
  assert_true(process.expect(b"Breakpoint 2 verified at", timeout_ms=10000))
  assert_true(process.expect(@utf8.encode(source_breakpoint)))
  assert_true(process.expect(b"(moondbg) "))
  assert_true(process.write(b"b sum\r"))
  assert_true(process.expect(b"Breakpoint 3 verified at function sum"))
  assert_true(process.expect(b"(moondbg) "))
  assert_true(process.write(b"continue\r"))
  assert_true(process.expect(b"in main", timeout_ms=10000))
  assert_true(process.expect(@utf8.encode(source_breakpoint)))
  assert_true(process.expect(b"(moondbg) "))
  assert_true(process.write(b"continue\r"))
  assert_true(
    process.expect(b"moondbg-dwarf-probe/pkg_scope.sum", timeout_ms=10000),
  )
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
  assert_true(process.expect(b"moondbg-dwarf-probe/lib.identity[Int]"))
  assert_true(process.expect(b"(moondbg) "))
  assert_true(process.write(b"continue\r"))
  assert_true(process.expect(b"moondbg-dwarf-probe/lib.identity[String]"))
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
  assert_true(process.expect(b"in main", timeout_ms=10000))
  assert_true(process.expect(b"(moondbg) "))
  assert_true(process.write(b"quit\r"))
  assert_true(process.expect(b"Debugger exited."))
  assert_true(process.wait(timeout_ms=10000))
}

///|
async test "development toolchain recursively prints MoonBit structs" {
  guard toolchain_acceptance_enabled() else { return }
  toolchain_acceptance_mutex.acquire()
  defer toolchain_acceptance_mutex.release()
  let (_, moondbg) = require_toolchain()
  let repository = @fs.realpath(".")
  let fixture = "\{repository}/testdata/dwarf_probe"
  assert_true(@fs.exists("\{fixture}/point/main.mbt"))
  let process = @pty_testkit.PtyProcess::spawn_debug(
    moondbg,
    fixture,
    package_name="point",
  )
  defer process.close()
  assert_eq(process.status(), 0)
  guard process.expect(b"(moondbg) ", timeout_ms=20000) else {
    process.wait(timeout_ms=100) |> ignore
    fail("moondbg point did not open a prompt (PTY status \{process.status()})")
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
  toolchain_acceptance_mutex.acquire()
  defer toolchain_acceptance_mutex.release()
  let (_, moondbg) = require_toolchain()
  let repository = @fs.realpath(".")
  let fixture = "\{repository}/testdata/dwarf_probe"
  assert_true(@fs.exists("\{fixture}/fixed_array_int/main.mbt"))
  let process = @pty_testkit.PtyProcess::spawn_debug(
    moondbg,
    fixture,
    package_name="fixed_array_int",
  )
  defer process.close()
  assert_eq(process.status(), 0)
  guard process.expect(b"(moondbg) ", timeout_ms=20000) else {
    process.wait(timeout_ms=100) |> ignore
    fail(
      "moondbg fixed_array_int did not open a prompt (PTY status \{process.status()})",
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

///|
async test "development toolchain prints bounded Array values across stops" {
  guard toolchain_acceptance_enabled() else { return }
  toolchain_acceptance_mutex.acquire()
  defer toolchain_acceptance_mutex.release()
  let (_, moondbg) = require_toolchain()
  let repository = @fs.realpath(".")
  let fixture = "\{repository}/testdata/dwarf_probe"
  assert_true(@fs.exists("\{fixture}/array_double/main.mbt"))
  let process = @pty_testkit.PtyProcess::spawn_debug(
    moondbg,
    fixture,
    package_name="array_double",
  )
  defer process.close()
  assert_eq(process.status(), 0)
  guard process.expect(b"(moondbg) ", timeout_ms=20000) else {
    process.wait(timeout_ms=100) |> ignore
    fail(
      "moondbg array_double did not open a prompt (PTY status \{process.status()})",
    )
  }
  assert_true(process.write(b"b sum\r"))
  assert_true(process.expect(b"Breakpoint 1 pending at function sum"))
  assert_true(process.expect(b"(moondbg) "))
  assert_true(process.write(b"run\r"))
  assert_true(process.expect(b"array_double.sum", timeout_ms=20000))
  assert_true(process.expect(b"(moondbg) "))

  for _ in 0..<2 {
    assert_true(process.write(b"p arr\r"))
    assert_true(process.expect(b"arr: Array[Double] with length = 10"))
    assert_true(process.expect(b"[1, 2, 3, 4, 5, 6, 7, 8, 9, 10]"))
    assert_true(process.expect(b"(moondbg) "))
  }

  assert_true(process.write(b"continue\r"))
  assert_true(process.expect(b"array_double.sum", timeout_ms=10000))
  assert_true(process.expect(b"(moondbg) "))
  for _ in 0..<2 {
    assert_true(process.write(b"p arr\r"))
    assert_true(process.expect(b"arr: Array[Double] with length = 100"))
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

///|
async test "development toolchain shallowly prints an active boxed enum" {
  guard toolchain_acceptance_enabled() else { return }
  toolchain_acceptance_mutex.acquire()
  defer toolchain_acceptance_mutex.release()
  let (_, moondbg) = require_toolchain()
  let repository = @fs.realpath(".")
  let fixture = "\{repository}/testdata/dwarf_probe"
  assert_true(@fs.exists("\{fixture}/list/main.mbt"))
  let process = @pty_testkit.PtyProcess::spawn_debug(
    moondbg,
    fixture,
    package_name="list",
  )
  defer process.close()
  assert_eq(process.status(), 0)
  guard process.expect(b"(moondbg) ", timeout_ms=20000) else {
    process.wait(timeout_ms=100) |> ignore
    fail("moondbg list did not open a prompt (PTY status \{process.status()})")
  }
  assert_true(process.write(b"b list/main.mbt:34\r"))
  assert_true(process.expect(b"Breakpoint 1 pending at list/main.mbt:34"))
  assert_true(process.expect(b"(moondbg) "))
  assert_true(process.write(b"run\r"))
  assert_true(process.expect(b"list/main.mbt:34", timeout_ms=20000))
  assert_true(process.expect(b"(moondbg) "))

  for _ in 0..<2 {
    assert_true(process.write(b"p list\r"))
    assert_true(process.expect(b"list: List"))
    assert_true(process.expect(b"Cons(3, List)"))
    assert_true(process.expect(b"(moondbg) "))
  }
  assert_true(process.write(b"quit\r"))
  assert_true(process.expect(b"Debugger exited."))
  assert_true(process.wait(timeout_ms=10000))
}

///|
async test "development toolchain precisely inspects Array struct elements" {
  guard toolchain_acceptance_enabled() else { return }
  toolchain_acceptance_mutex.acquire()
  defer toolchain_acceptance_mutex.release()
  let (_, moondbg) = require_toolchain()
  let repository = @fs.realpath(".")
  let fixture = "\{repository}/testdata/dwarf_probe"
  assert_true(@fs.exists("\{fixture}/array_points/main.mbt"))
  let process = @pty_testkit.PtyProcess::spawn_debug(
    moondbg,
    fixture,
    package_name="array_points",
  )
  defer process.close()
  assert_eq(process.status(), 0)
  guard process.expect(b"(moondbg) ", timeout_ms=20000) else {
    process.wait(timeout_ms=100) |> ignore
    fail(
      "moondbg array_points did not open a prompt (PTY status \{process.status()})",
    )
  }
  assert_true(process.write(b"b array_points/main.mbt:25\r"))
  assert_true(
    process.expect(b"Breakpoint 1 pending at array_points/main.mbt:25"),
  )
  assert_true(process.expect(b"(moondbg) "))
  assert_true(process.write(b"run\r"))
  assert_true(process.expect(b"array_points/main.mbt:25", timeout_ms=20000))
  assert_true(process.expect(b"(moondbg) "))

  for _ in 0..<2 {
    assert_true(process.write(b"p arr[0]\r"))
    assert_true(process.expect(b"arr[0]: Point = {"))
    assert_true(process.expect(b"x: Double = 1"))
    assert_true(process.expect(b"y: Double = 2"))
    assert_true(process.expect(b"(moondbg) "))
  }
  assert_true(process.write(b"p arr[0].x\r"))
  assert_true(process.expect(b"arr[0].x: Double = 1"))
  assert_true(process.expect(b"(moondbg) "))
  assert_true(process.write(b"p arr[3]\r"))
  assert_true(
    process.expect(b"Index 3 is out of bounds for 'arr' with length 3."),
  )
  assert_true(process.expect(b"(moondbg) "))
  assert_true(process.write(b"quit\r"))
  assert_true(process.expect(b"Debugger exited."))
  assert_true(process.wait(timeout_ms=10000))
}

///|
async test "development toolchain navigates stack frames and caller locals" {
  guard toolchain_acceptance_enabled() else { return }
  toolchain_acceptance_mutex.acquire()
  defer toolchain_acceptance_mutex.release()
  let (_, moondbg) = require_toolchain()
  let repository = @fs.realpath(".")
  let fixture = "\{repository}/testdata/dwarf_probe"
  let support_source = "\{fixture}/stack_support/stack_support.mbt"
  let main_source = "\{fixture}/stack_frames/main.mbt"
  let leaf_line = unique_source_line(
    support_source, "generic_envelope.envelope_code + leaf_payload.payload_code + leaf_adjustment // MOONDBG_STACK_LEAF_BREAKPOINT",
  )
  let inner_shadow_line = unique_source_line(
    support_source, "recursive_frame(3, shadowed_value, ordinary_payload)",
  )
  let after_call_line = unique_source_line(
    main_source, "let main_after_call = stack_result + main_seed",
  )
  let process = @pty_testkit.PtyProcess::spawn_debug(
    moondbg,
    fixture,
    package_name="stack_frames",
  )
  defer process.close()
  assert_eq(process.status(), 0)
  guard process.expect(b"(moondbg) ", timeout_ms=20000) else {
    process.wait(timeout_ms=100) |> ignore
    fail(
      "moondbg stack_frames did not open a prompt (PTY status \{process.status()})",
    )
  }
  assert_true(
    process.write(
      @utf8.encode("b stack_support/stack_support.mbt:\{leaf_line}\r"),
    ),
  )
  assert_true(process.expect(b"Breakpoint 1 pending at"))
  assert_true(process.expect(b"(moondbg) "))
  assert_true(
    process.write(@utf8.encode("b stack_frames/main.mbt:\{after_call_line}\r")),
  )
  assert_true(process.expect(b"Breakpoint 2 pending at"))
  assert_true(process.expect(b"(moondbg) "))
  assert_true(
    process.write(
      @utf8.encode("b stack_support/stack_support.mbt:\{inner_shadow_line}\r"),
    ),
  )
  assert_true(process.expect(b"Breakpoint 3 pending at"))
  assert_true(process.expect(b"(moondbg) "))
  assert_true(process.write(b"run\r"))
  assert_true(process.expect(b"stack_support.ordinary_frame", timeout_ms=20000))
  assert_true(process.expect(b"(moondbg) "))
  assert_true(process.write(b"p shadowed_value\r"))
  assert_true(process.expect(b"shadowed_value: int = 340"))
  assert_true(process.expect(b"(moondbg) "))
  assert_true(process.write(b"continue\r"))
  assert_true(
    process.expect(
      b"moondbg-dwarf-probe/stack_support.generic_leaf[Int]",
      timeout_ms=20000,
    ),
  )
  assert_true(process.expect(b"(moondbg) "))

  assert_true(process.write(b"bt\r"))
  assert_true(process.expect(b"* #0 [moonbit]"))
  assert_true(
    process.expect(b"moondbg-dwarf-probe/stack_support.generic_leaf[Int]"),
  )
  assert_true(process.expect(b"#3 [moonbit]"))
  assert_true(process.expect(b"stack_support.recursive_frame"))
  assert_true(process.expect(b"#5 [moonbit]"))
  assert_true(process.expect(b"stack_support.ordinary_frame"))
  assert_true(process.expect(b"#6 [moonbit]"))
  assert_true(process.expect(b"stack_support.enter_stack"))
  assert_true(process.expect(b"#7 [moonbit] main"))
  assert_true(process.expect(b"(moondbg) "))

  assert_true(process.write(b"bt --all\r"))
  assert_true(process.expect(b"#8 [native] main"))
  assert_true(process.expect(b"#9 [native] start"))
  assert_true(process.expect(b"(moondbg) "))
  assert_true(process.write(b"frame 3\r"))
  assert_true(process.expect(b"Selected frame #3:"))
  assert_true(process.expect(b"stack_support.recursive_frame"))
  assert_true(process.expect(b"(moondbg) "))
  assert_true(process.write(b"locals\r"))
  assert_true(process.expect(b"recursion_depth: Int = 2"))
  assert_true(process.expect(b"depth_marker: Int = 390"))
  assert_true(process.expect(b"(moondbg) "))
  assert_true(process.write(b"p recursion_depth\r"))
  assert_true(process.expect(b"recursion_depth: int = 2"))
  assert_true(process.expect(b"(moondbg) "))
  assert_true(process.write(b"list\r"))
  assert_true(process.expect(b"recursive_frame"))
  assert_true(process.expect(b"(moondbg) "))
  assert_true(process.write(b"up\r"))
  assert_true(process.expect(b"Selected frame #4:"))
  assert_true(process.expect(b"(moondbg) "))
  assert_true(process.write(b"down\r"))
  assert_true(process.expect(b"Selected frame #3:"))
  assert_true(process.expect(b"(moondbg) "))

  assert_true(process.write(b"frame 5\r"))
  assert_true(process.expect(b"Selected frame #5:"))
  assert_true(process.expect(b"stack_support.ordinary_frame"))
  assert_true(process.expect(b"(moondbg) "))
  assert_true(process.write(b"locals\r"))
  assert_true(process.expect(b"shadowed_value: Int = <unavailable>"))
  assert_true(process.expect(b"(moondbg) "))
  assert_true(process.write(b"p shadowed_value\r"))
  assert_true(
    process.expect(
      b"Variable 'shadowed_value' is unavailable at the current location.",
    ),
  )
  assert_true(process.expect(b"(moondbg) "))

  assert_true(process.write(b"continue\r"))
  assert_true(process.expect(b"in main", timeout_ms=20000))
  assert_true(process.expect(b"stack_frames/main.mbt"))
  assert_true(process.expect(b"(moondbg) "))
  assert_true(process.write(b"bt\r"))
  assert_true(process.expect(b"* #0 [moonbit] main"))
  assert_true(process.expect(b"(moondbg) "))
  assert_true(process.write(b"locals\r"))
  assert_true(process.expect(b"main_seed: Int = 7"))
  assert_true(process.expect(b"stack_result: Int = 669"))
  assert_true(process.expect(b"(moondbg) "))
  assert_true(process.write(b"p stack_result\r"))
  assert_true(process.expect(b"stack_result: int = 669"))
  assert_true(process.expect(b"(moondbg) "))
  assert_true(process.write(b"continue\r"))
  assert_true(process.expect(b"begin terminal output", timeout_ms=10000))
  assert_true(process.expect(b"stack fixture result: 676"))
  assert_true(process.expect(b"end terminal output"))
  assert_true(process.expect(b"Process exited normally (code 0)."))
  assert_true(process.expect(b"(moondbg) "))
  assert_true(process.write(b"quit\r"))
  assert_true(process.expect(b"Debugger exited."))
  assert_true(process.wait(timeout_ms=10000))
}
