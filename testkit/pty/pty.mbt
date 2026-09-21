///|
/// PID of this helper's own CLI process, for read-only cleanup verification.
pub fn PtyProcess::pid(self : PtyProcess) -> Int {
  native_pid(self.native)
}

///|
#borrow(process)
extern "C" fn native_pid(process : NativePtyProcess) -> Int = "moondbg_test_pty_pid"

///|
/// Consume the earliest matching fragment: 1 for first, 2 for second, 0 on
/// timeout/EOF. Supports runtimes which either exit or raise SIGABRT on panic.
pub fn PtyProcess::expect_either(
  self : PtyProcess,
  first : Bytes,
  second : Bytes,
  timeout_ms? : Int = 20000,
) -> Int {
  native_expect_either(self.native, first, second, timeout_ms)
}

///|
#borrow(process, first, second)
extern "C" fn native_expect_either(
  process : NativePtyProcess,
  first : Bytes,
  second : Bytes,
  timeout_ms : Int,
) -> Int = "moondbg_test_pty_expect_either"

///|
priv type NativePtyProcess

///|
pub struct PtyProcess {
  priv native : NativePtyProcess
}

///|
#borrow(filter)
extern "C" fn native_spawn_self(filter : Bytes) -> NativePtyProcess = "moondbg_test_pty_spawn_self"

///|
#borrow(executable, working_directory, package_name)
extern "C" fn native_spawn_debug(
  executable : Bytes,
  working_directory : Bytes,
  package_name : Bytes,
) -> NativePtyProcess = "moondbg_test_pty_spawn_debug"

///|
extern "C" fn native_fixture_prepare() -> Bool = "moondbg_test_pty_fixture_prepare"

///|
#borrow(process, bytes)
extern "C" fn native_write(
  process : NativePtyProcess,
  bytes : Bytes,
  timeout_ms : Int,
) -> Bool = "moondbg_test_pty_write"

///|
#borrow(process, expected)
extern "C" fn native_expect(
  process : NativePtyProcess,
  expected : Bytes,
  timeout_ms : Int,
) -> Bool = "moondbg_test_pty_expect"

///|
#borrow(process)
extern "C" fn native_wait(process : NativePtyProcess, timeout_ms : Int) -> Bool = "moondbg_test_pty_wait"

///|
#borrow(process)
extern "C" fn native_adapter_started(
  process : NativePtyProcess,
  timeout_ms : Int,
) -> Bool = "moondbg_test_pty_adapter_started"

///|
#borrow(process)
extern "C" fn native_adapter_stopped(
  process : NativePtyProcess,
  timeout_ms : Int,
) -> Bool = "moondbg_test_pty_adapter_stopped"

///|
#borrow(process)
extern "C" fn native_status(process : NativePtyProcess) -> Int = "moondbg_test_pty_status"

///|
#borrow(process)
extern "C" fn native_close(process : NativePtyProcess) -> Unit = "moondbg_test_pty_close"

///|
/// Re-executes the current MoonBit test binary under a fresh PTY.
pub fn PtyProcess::spawn_self(filter : String) -> PtyProcess {
  { native: native_spawn_self(@utf8.encode(filter)), }
}

///|
/// Runs `moondbg <package>` in a selected fixture directory under a fresh PTY.
pub fn PtyProcess::spawn_debug(
  moondbg : String,
  working_directory : String,
  package_name? : String = "main",
) -> PtyProcess {
  {
    native: native_spawn_debug(
      @utf8.encode(moondbg),
      @utf8.encode(working_directory),
      @utf8.encode(package_name),
    ),
  }
}

///|
/// Makes a re-executed PTY fixture own its controlling terminal.
pub fn prepare_fixture() -> Bool {
  native_fixture_prepare()
}

///|
pub fn PtyProcess::write(
  self : PtyProcess,
  bytes : Bytes,
  timeout_ms? : Int = 2000,
) -> Bool {
  native_write(self.native, bytes, timeout_ms)
}

///|
pub fn PtyProcess::expect(
  self : PtyProcess,
  expected : Bytes,
  timeout_ms? : Int = 2000,
) -> Bool {
  native_expect(self.native, expected, timeout_ms)
}

///|
pub fn PtyProcess::wait(self : PtyProcess, timeout_ms? : Int = 5000) -> Bool {
  native_wait(self.native, timeout_ms)
}

///|
pub fn PtyProcess::adapter_started(
  self : PtyProcess,
  timeout_ms? : Int = 2000,
) -> Bool {
  native_adapter_started(self.native, timeout_ms)
}

///|
pub fn PtyProcess::adapter_stopped(
  self : PtyProcess,
  timeout_ms? : Int = 2000,
) -> Bool {
  native_adapter_stopped(self.native, timeout_ms)
}

///|
pub fn PtyProcess::status(self : PtyProcess) -> Int {
  native_status(self.native)
}

///|
pub fn PtyProcess::close(self : PtyProcess) -> Unit {
  native_close(self.native)
}
