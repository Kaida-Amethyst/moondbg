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
#borrow(executable, working_directory)
extern "C" fn native_spawn_debug(
  executable : Bytes,
  working_directory : Bytes,
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
/// Runs `moon debug main` in a selected fixture directory under a fresh PTY.
pub fn PtyProcess::spawn_debug(
  moon : String,
  working_directory : String,
) -> PtyProcess {
  {
    native: native_spawn_debug(
      @utf8.encode(moon),
      @utf8.encode(working_directory),
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
