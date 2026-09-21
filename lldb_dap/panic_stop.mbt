///|
/// Install outside setFunctionBreakpoints: that request replaces only the
/// adapter's user-function breakpoint collection, not this LLDB-owned one.
/// The launch command runs after target creation and before execution on every
/// run. A missing symbol stays pending (e.g. when debugging a C executable).
fn panic_breakpoint_command() -> String {
  "!breakpoint set --name moonbit_panic --breakpoint-name __moondbg_panic"
}

///|
/// Recognize only a breakpoint at the exact runtime entry. Do not search caller
/// frames: an ensuing SIGABRT, a step inside the runtime, or another crash must
/// retain its original reason even when moonbit_panic appears on the stack.
fn panic_stop_reason(reason : String, top_function : String?) -> String {
  // Apple LLDB-DAP appends this annotation for the optimized runtime, even
  // when the user's MoonBit code was built with -g -O0.
  if reason == "breakpoint" &&
    top_function is Some("moonbit_panic" | "moonbit_panic [opt]") {
    "MoonBit panic"
  } else {
    reason
  }
}

///|
test "panic stop recognition does not relabel steps signals or similar symbols" {
  assert_eq(
    panic_stop_reason("breakpoint", Some("moonbit_panic")),
    "MoonBit panic",
  )
  assert_eq(
    panic_stop_reason("breakpoint", Some("moonbit_panic [opt]")),
    "MoonBit panic",
  )
  for name in ["moonbit_main", "moonbit_panic_helper", "abort"] {
    assert_eq(panic_stop_reason("breakpoint", Some(name)), "breakpoint")
  }
  assert_eq(panic_stop_reason("breakpoint", None), "breakpoint")
  for reason in ["step", "step over", "signal SIGABRT", "EXC_BAD_ACCESS"] {
    assert_eq(panic_stop_reason(reason, Some("moonbit_panic")), reason)
  }
}
