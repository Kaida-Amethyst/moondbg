///|
priv struct FrameworkTestBackend {}

///|
impl @moondbg.DebugBackend for FrameworkTestBackend with fn launch(
  _self,
  _executable,
  _breakpoints,
) {
  @moondbg.RunOutcome::exited(Some(0))
}

///|
impl @moondbg.DebugBackend for FrameworkTestBackend with fn continue_execution(
  _self,
  _thread,
) {
  @moondbg.RunOutcome::exited(Some(0))
}

///|
impl @moondbg.DebugBackend for FrameworkTestBackend with fn next(_self, _thread) {
  @moondbg.RunOutcome::exited(Some(0))
}

///|
impl @moondbg.DebugBackend for FrameworkTestBackend with fn step(_self, _thread) {
  @moondbg.RunOutcome::exited(Some(0))
}

///|
impl @moondbg.DebugBackend for FrameworkTestBackend with fn finish(
  _self,
  _thread,
) {
  @moondbg.RunOutcome::exited(Some(0))
}

///|
impl @moondbg.DebugBackend for FrameworkTestBackend with fn find_variable(
  _self,
  _thread,
  _frame,
  name,
) {
  @moondbg.VariableLookupResult::not_found(name)
}

///|
impl @moondbg.DebugBackend for FrameworkTestBackend with fn breakpoint_snapshots(
  _self,
) {
  []
}

///|
impl @moondbg.DebugBackend for FrameworkTestBackend with fn take_output(_self) {
  []
}

///|
impl @moondbg.DebugBackend for FrameworkTestBackend with fn disconnect(_self) {
  ()
}

///|
impl @moondbg.DebugBackend for FrameworkTestBackend with fn close(_self) {
  ()
}

///|
fn framework_test_context() -> ReplContext raise {
  let backend = FrameworkTestBackend::{ }
  let session = @moondbg.DebugSession::new("/tmp/program", backend)
  let renderer = HumanRenderer::new()
  ReplContext::new(session, default_command_registry(), renderer)
}

///|
async fn execute_framework_command(
  context : ReplContext,
  line : StringView,
) -> CommandResult {
  guard context.registry.parse_line(line) is RegistryCommand(command) else {
    fail("expected a constructed command for '\{line}'")
  }
  command.execute(context)
}

///|
fn conflicting_spec(name : String, aliases : Array[String]) -> CommandSpec {
  CommandSpec::new(name, aliases, name, "test", parse_help_command)
}

///|
test "P5 registry rejects canonical name and alias conflicts" {
  let duplicate_name = try {
    CommandRegistry::new([
      conflicting_spec("one", []),
      conflicting_spec("one", []),
    ])
    |> ignore
    false
  } catch {
    CommandNameConflict("one") => true
    _ => false
  }
  assert_true(duplicate_name)
  let alias_conflict = try {
    CommandRegistry::new([
      conflicting_spec("one", ["shared"]),
      conflicting_spec("two", ["shared"]),
    ])
    |> ignore
    false
  } catch {
    CommandNameConflict("shared") => true
    _ => false
  }
  assert_true(alias_conflict)
  let canonical_alias_conflict = try {
    CommandRegistry::new([
      conflicting_spec("one", ["shared"]),
      conflicting_spec("shared", []),
    ])
    |> ignore
    false
  } catch {
    CommandNameConflict("shared") => true
    _ => false
  }
  assert_true(canonical_alias_conflict)
}

///|
test "P5 registry lookup resolves fixed aliases to their canonical specs" {
  let registry = default_command_registry()
  guard registry.lookup("quit") is Some(quit) &&
    registry.lookup("exit") is Some(exit) &&
    registry.lookup("q") is Some(q) else {
    fail("quit and its aliases should be registered")
  }
  assert_eq(quit.name, "quit")
  assert_eq(exit.name, "quit")
  assert_eq(q.name, "quit")
  assert_true(registry.lookup("quitter") is None)
}

///|
test "P5 registry resolves every legacy alias through command specs" {
  let registry = default_command_registry()
  for
    entry in [
      ("b", "break"),
      ("r", "run"),
      ("c", "continue"),
      ("n", "next"),
      ("s", "step"),
      ("fin", "finish"),
      ("p", "print"),
    ] {
    guard registry.lookup(entry.0) is Some(spec) else {
      fail("missing alias '\{entry.0}'")
    }
    assert_eq(spec.name, entry.1)
  }
}

///|
test "P5 help metadata is derived from registry order" {
  let entries = default_command_registry().help_entries()
  assert_eq(entries.length(), 10)
  assert_eq(entries[0].usage, "break <file>:<line>")
  assert_eq(entries[0].aliases, ["b"])
  assert_eq(entries[0].alias_usage(), "b <file>:<line>")
  assert_eq(entries[0].summary, "Set a source breakpoint")
  assert_eq(entries[8].usage, "help")
  assert_eq(entries[9].usage, "quit")
  assert_eq(entries[9].aliases, ["q", "exit"])
  assert_eq(entries[9].alias_usage(), "q, exit")
  assert_eq(entries[9].summary, "Exit moondbg")
}

///|
test "P5 human help renderer preserves existing column layout" {
  let entries = default_command_registry().help_entries()
  assert_eq(
    format_help_entry(entries[0]),
    "  break <file>:<line>  b <file>:<line>  Set a source breakpoint",
  )
  assert_eq(
    format_help_entry(entries[9]),
    "  quit                  q, exit          Exit moondbg",
  )
}

///|
async test "P5 help command returns structured registry help" {
  let context = framework_test_context()
  let result = execute_framework_command(context, "help")
  assert_true(result.control is ContinueRepl)
  assert_true(result.legacy_action is None)
  guard result.events is [HelpPresentation(entries)] else {
    fail("help should return one structured presentation event")
  }
  assert_eq(entries.length(), context.registry.specs.length())
  assert_eq(entries[8].summary, "Show this help")
}

///|
test "P5 help parser rejects arguments through its spec factory" {
  assert_true(
    default_command_registry().parse_line("help now")
    is RegistryInvalid("help does not accept arguments"),
  )
}

///|
async test "P5 quit and exit accept leading whitespace and ignored arguments" {
  let context = framework_test_context()
  let commands = [
    "exit", "quit", " exit 0", "   quit 1122", "\texit", "quit\tignored",
  ]
  for command in commands {
    let result = execute_framework_command(context, command)
    assert_true(result.control is ExitRepl, msg=command)
    assert_eq(result.events.length(), 0)
    assert_true(result.legacy_action is None)
  }
}

///|
async test "P5 q remains a no-argument quit alias" {
  let context = framework_test_context()
  assert_true(execute_framework_command(context, "q").control is ExitRepl)
  assert_true(
    context.registry.parse_line("q now")
    is RegistryInvalid("q does not accept arguments"),
  )
}

///|
test "P5 quit and exit require exact lowercase command words" {
  let registry = default_command_registry()
  for command in ["", "   ", "exiting", "exit0", "quitter", "QUIT"] {
    assert_true(registry.parse_line(command) is RegistryUnknown, msg=command)
  }
}

///|
async test "P5 legacy bridge receives run stepping print and list actions" {
  let context = framework_test_context()
  assert_true(
    execute_framework_command(context, "run").legacy_action is Some(LegacyRun),
  )
  assert_true(
    execute_framework_command(context, "n").legacy_action
    is Some(LegacyStepExecution(LegacyStepOver)),
  )
  assert_true(
    execute_framework_command(context, "p answer").legacy_action
    is Some(LegacyPrintVariable("answer")),
  )
  assert_true(
    execute_framework_command(context, "list --count 12").legacy_action
    is Some(LegacyList(12)),
  )
}

///|
async test "P5 legacy no-argument commands retain full names and aliases" {
  let context = framework_test_context()
  for command in ["run", "r"] {
    assert_true(
      execute_framework_command(context, command).legacy_action
      is Some(LegacyRun),
      msg=command,
    )
  }
  for command in ["continue", "c"] {
    assert_true(
      execute_framework_command(context, command).legacy_action
      is Some(LegacyContinue),
      msg=command,
    )
  }
  for command in ["next", "n"] {
    assert_true(
      execute_framework_command(context, command).legacy_action
      is Some(LegacyStepExecution(LegacyStepOver)),
      msg=command,
    )
  }
  for command in ["step", "s"] {
    assert_true(
      execute_framework_command(context, command).legacy_action
      is Some(LegacyStepExecution(LegacyStepInto)),
      msg=command,
    )
  }
  for command in ["finish", "fin"] {
    assert_true(
      execute_framework_command(context, command).legacy_action
      is Some(LegacyStepExecution(LegacyStepOut)),
      msg=command,
    )
  }
}

///|
async test "P5 legacy list retains default and LLDB count options" {
  let context = framework_test_context()
  assert_true(
    execute_framework_command(context, "list").legacy_action
    is Some(LegacyList(5)),
  )
  assert_true(
    execute_framework_command(context, " list -c 10\t").legacy_action
    is Some(LegacyList(10)),
  )
  assert_true(
    execute_framework_command(context, "list --count\t12").legacy_action
    is Some(LegacyList(12)),
  )
}

///|
async test "P5 legacy variable parser retains simple names" {
  let context = framework_test_context()
  assert_true(
    execute_framework_command(context, "print answer").legacy_action
    is Some(LegacyPrintVariable("answer")),
  )
  assert_true(
    execute_framework_command(context, "p input").legacy_action
    is Some(LegacyPrintVariable("input")),
  )
  assert_true(
    execute_framework_command(context, "p 结果").legacy_action
    is Some(LegacyPrintVariable("结果")),
  )
}

///|
async test "P5 legacy breakpoint parser keeps the final colon separator" {
  let context = framework_test_context()
  assert_true(
    execute_framework_command(context, "break main/main.mbt:4").legacy_action
    is Some(LegacyBreak("main/main.mbt", 4)),
  )
  assert_true(
    execute_framework_command(context, "b C:/project/main.mbt:12").legacy_action
    is Some(LegacyBreak("C:/project/main.mbt", 12)),
  )
}

///|
test "P5 legacy factories retain local validation" {
  let registry = default_command_registry()
  let commands = [
    "break", "b main.mbt", "break :4", "break main.mbt:0", "break main.mbt:nope",
    "run now", "continue now", "next now", "n now", "step 1", "s 1", "finish frame",
    "fin frame", "p", "print", "p point.x", "p items[3]", "p answer + 1", "p 42",
    "list -c", "list --count", "list -c 0", "list -c -1", "list -c ten", "list -c 10 more",
    "list 10", "list --lines 10", "list around",
  ]
  for command in commands {
    assert_true(registry.parse_line(command) is RegistryInvalid(_), msg=command)
  }
}

///|
test "P5 legacy command-like prefixes remain unknown" {
  let registry = default_command_registry()
  for command in ["f", "nexted", "stepping", "finished"] {
    assert_true(registry.parse_line(command) is RegistryUnknown, msg=command)
  }
}
