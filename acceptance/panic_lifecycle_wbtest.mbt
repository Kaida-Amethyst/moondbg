///|
/// Observe only descendants of the exact process owned by this test. Snapshot
/// before disconnect so reparenting cannot hide leaked adapters/debuggees.
async fn owned_descendants(root : Int) -> Array[Int] {
  let table = collect_text("/bin/ps", ["-axo", "pid=,ppid="])
  let parents : Map[Int, Int] = Map([])
  for line in table.split("\n") {
    let fields = line.split(" ").filter(field => field != "").collect()
    if fields is [pid, parent] {
      parents.set(@string.parse_int(pid), @string.parse_int(parent))
    }
  }
  let owned : Map[Int, Bool] = Map([(root, true)])
  for ;; {
    let before = owned.length()
    for pid, parent in parents {
      if owned.contains(parent) {
        owned.set(pid, true)
      }
    }
    if owned.length() == before {
      break
    }
  }
  owned.remove(root)
  owned.keys().collect()
}

///|
async fn assert_processes_gone(pids : Array[Int]) -> Unit {
  @async.with_timeout(5000, () => {
    for ;; {
      let mut alive = false
      for pid in pids {
        let (code, _, _) = @process.collect_output(
          "/bin/kill",
          ["-0", pid.to_string()],
          inherit_env=true,
        )
        if code == 0 {
          alive = true
        }
      }
      if !alive {
        break
      }
      @async.sleep(25)
    }
  })
}

///|
async fn build_panic_signal_probe(directory : String) -> String {
  let program = "\{directory}/panic-signal.exe"
  let (code, _, stderr) = @process.collect_output(
    "cc",
    [
      "-g",
      "-O0",
      "\{@fs.realpath(".")}/testdata/panic_signal/main.c",
      "-o",
      program,
    ],
    inherit_env=true,
  )
  assert_eq(code, 0, msg=stderr.text())
  program
}

///|
fn repl_continue_panic(process : @pty_testkit.PtyProcess) -> Bool raise {
  assert_true(process.write(b"continue\r"))
  let outcome = process.expect_either(
    b"Process exited with code ", b"Stopped (signal SIGABRT)",
  )
  assert_true(
    outcome > 0,
    msg="panic continuation must exit nonnormally or stop on SIGABRT",
  )
  if outcome == 1 {
    breakpoint_expect(process, "1.", "panic exit code")
  }
  breakpoint_expect(process, "(moondbg) ", "continue panic")
  outcome == 2
}

///|
async test "REPL direct panic bounds abort and normal completion rerun and clean up" {
  guard toolchain_acceptance_enabled() else { return }
  toolchain_acceptance_mutex.acquire()
  defer toolchain_acceptance_mutex.release()
  let (_, moondbg) = require_toolchain()
  let fixture = "\{@fs.realpath(".")}/testdata/dwarf_probe"
  for
    package_name in [
      "panic_stop", "panic_bounds", "panic_context", "panic_normal",
    ] {
    let process = @pty_testkit.PtyProcess::spawn_debug(
      moondbg,
      fixture,
      package_name~,
    )
    defer process.close()
    breakpoint_expect(process, "(moondbg) ", "startup")
    let cli_pid = process.pid()
    let observed : Array[Int] = []
    for _ in 0..<2 {
      if package_name == "panic_normal" {
        breakpoint_command(process, "run", [
          "panic lifecycle normal exit", "Process exited normally (code 0).",
        ])
      } else {
        breakpoint_command(
          process,
          "run",
          if package_name == "panic_context" {
            [
              "panic context example", "Stopped (MoonBit panic)", "Continuing resumes panic termination",
            ]
          } else {
            ["Stopped (MoonBit panic)", "Continuing resumes panic termination"]
          },
        )
        let owned = owned_descendants(cli_pid)
        for pid in owned {
          observed.push(pid)
        }
        assert_true(
          owned.length() >= 2,
          msg="must observe adapter and debuggee before cleanup",
        )
        let aborted = repl_continue_panic(process)
        if !aborted {
          // The adapter may be retained for the next run. At least the target
          // disappears, and quitting below must clean up every retained child.
          assert_true(owned_descendants(cli_pid).length() < owned.length())
        }
      }
    }
    if package_name != "panic_normal" {
      breakpoint_command(process, "run", ["Stopped (MoonBit panic)"])
    }
    let owned = owned_descendants(cli_pid)
    breakpoint_quit(process)
    assert_processes_gone(owned)
    assert_processes_gone(observed)
    assert_processes_gone([cli_pid])
  }
}

///|
async test "REPL panic then real SIGABRT is not relabelled and rerun replaces the process" {
  guard toolchain_acceptance_enabled() else { return }
  toolchain_acceptance_mutex.acquire()
  defer toolchain_acceptance_mutex.release()
  let (_, moondbg) = require_toolchain()
  let directory = @fs.tmpdir(prefix="moondbg-panic-signal-")
  defer @fs.rmdir(directory, recursive=true)
  let program = build_panic_signal_probe(directory)
  let process = @pty_testkit.PtyProcess::spawn_debug(
    moondbg,
    directory,
    package_name=program,
  )
  defer process.close()
  breakpoint_expect(process, "(moondbg) ", "startup")
  breakpoint_command(process, "run", ["Stopped (MoonBit panic)"])
  let previous = owned_descendants(process.pid())
  assert_true(previous.length() >= 2)
  assert_true(repl_continue_panic(process))
  breakpoint_command(process, "run", ["Stopped (MoonBit panic)"])
  assert_processes_gone(previous)
  let owned = owned_descendants(process.pid())
  breakpoint_quit(process)
  assert_processes_gone(owned)
}
