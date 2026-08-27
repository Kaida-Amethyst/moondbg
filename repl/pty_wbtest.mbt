///|
async test "REPL PTY fixture child" {
  guard @env.get_env_var("MOONDBG_PTY_FIXTURE") == Some("1") &&
    @env.get_env_var("MOONDBG_LLDB_DAP") is Some(executable) else {
    return
  }
  guard @pty_testkit.prepare_fixture() else {
    fail("PTY fixture could not acquire its controlling terminal")
  }
  run(executable)
}

///|
fn spawn_repl_fixture() -> @pty_testkit.PtyProcess raise {
  let process = @pty_testkit.PtyProcess::spawn_self("pty_wbtest.mbt:0-1")
  assert_eq(process.status(), 0)
  process
}

///|
fn expect_prompt(process : @pty_testkit.PtyProcess) -> Unit raise {
  assert_true(process.expect(b"(moondbg) ", timeout_ms=3000))
}

///|
fn assert_adapter_cleanup(process : @pty_testkit.PtyProcess) -> Unit raise {
  assert_true(process.wait(timeout_ms=5000))
  assert_true(process.adapter_stopped(timeout_ms=3000))
}

///|
test "REPL prompt and local help do not wait for a blocked adapter" {
  guard @env.get_env_var("MOONDBG_PTY_FIXTURE") != Some("1") else { return }
  let process = spawn_repl_fixture()
  defer process.close()
  expect_prompt(process)
  assert_true(process.adapter_started(timeout_ms=3000))
  assert_true(process.write(b"help\r"))
  assert_true(process.expect(b"Commands:"))
  expect_prompt(process)
  assert_true(process.write(b"quit\r"))
  assert_true(process.expect(b"Debugger exited."))
  assert_adapter_cleanup(process)
}

///|
test "REPL exit alias terminates without confirmation" {
  guard @env.get_env_var("MOONDBG_PTY_FIXTURE") != Some("1") else { return }
  let process = spawn_repl_fixture()
  defer process.close()
  expect_prompt(process)
  assert_true(process.adapter_started(timeout_ms=3000))
  assert_true(process.write(b"exit 0\r"))
  assert_true(process.expect(b"Debugger exited."))
  assert_adapter_cleanup(process)
}

///|
test "REPL Ctrl-C discards input and redraws the prompt" {
  guard @env.get_env_var("MOONDBG_PTY_FIXTURE") != Some("1") else { return }
  let process = spawn_repl_fixture()
  defer process.close()
  expect_prompt(process)
  assert_true(process.adapter_started(timeout_ms=3000))
  assert_true(process.write(Bytes::from_array([b'\x03'])))
  expect_prompt(process)
  assert_true(process.write(b"quit\r"))
  assert_true(process.expect(b"Debugger exited."))
  assert_adapter_cleanup(process)
}

///|
test "REPL Ctrl-D returns EOF and cleans up the adapter" {
  guard @env.get_env_var("MOONDBG_PTY_FIXTURE") != Some("1") else { return }
  let process = spawn_repl_fixture()
  defer process.close()
  expect_prompt(process)
  assert_true(process.adapter_started(timeout_ms=3000))
  assert_true(process.write(Bytes::from_array([b'\x04'])))
  assert_true(process.expect(b"Debugger exited."))
  assert_adapter_cleanup(process)
}
