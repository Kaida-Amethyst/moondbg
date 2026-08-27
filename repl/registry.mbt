///|
priv suberror CommandRegistryError {
  CommandNameConflict(String)
} derive(Debug)

///|
priv struct CommandSpec {
  name : String
  aliases : Array[String]
  usage : String
  summary : String
  parser : (StringView, StringView) -> CommandParseResult
}

///|
fn CommandSpec::new(
  name : String,
  aliases : Array[String],
  usage : String,
  summary : String,
  parser : (StringView, StringView) -> CommandParseResult,
) -> CommandSpec {
  { name, aliases, usage, summary, parser, }
}

///|
fn CommandSpec::parse(
  self : CommandSpec,
  invoked_name : StringView,
  arguments : StringView,
) -> CommandParseResult {
  (self.parser)(invoked_name, arguments)
}

///|
fn CommandSpec::help_entry(self : CommandSpec) -> CommandHelpEntry {
  {
    name: self.name,
    aliases: self.aliases.copy(),
    usage: self.usage,
    summary: self.summary,
  }
}

///|
priv struct CommandRegistry {
  specs : Array[CommandSpec]
  names : Map[String, Int]
}

///|
fn CommandRegistry::new(
  specs : Array[CommandSpec],
) -> CommandRegistry raise CommandRegistryError {
  let names : Map[String, Int] = Map([])
  for index, spec in specs.iter2() {
    guard names.get(spec.name) is None else {
      raise CommandNameConflict(spec.name)
    }
    names.set(spec.name, index)
    for name in spec.aliases {
      guard names.get(name) is None else { raise CommandNameConflict(name) }
      names.set(name, index)
    }
  }
  { specs, names, }
}

///|
fn CommandRegistry::lookup(
  self : CommandRegistry,
  name : StringView,
) -> CommandSpec? {
  guard self.names.get(name.to_owned()) is Some(index) else { return None }
  Some(self.specs[index])
}

///|
fn CommandRegistry::help_entries(
  self : CommandRegistry,
) -> Array[CommandHelpEntry] {
  self.specs.map(spec => spec.help_entry())
}

///|
priv enum RegistryParseResult {
  RegistryCommand(&ReplCommand)
  RegistryInvalid(String)
  RegistryUnknown
}

///|
fn CommandRegistry::parse_line(
  self : CommandRegistry,
  line : StringView,
) -> RegistryParseResult {
  guard parse_command_invocation(line) is Some(invocation) else {
    return RegistryUnknown
  }
  guard self.lookup(invocation.name) is Some(spec) else {
    return RegistryUnknown
  }
  match spec.parse(invocation.name, invocation.arguments) {
    ParsedCommand(command) => RegistryCommand(command)
    InvalidCommand(message) => RegistryInvalid(message)
  }
}

///|
fn default_command_registry() -> CommandRegistry raise CommandRegistryError {
  CommandRegistry::new([
    break_command_spec(),
    run_command_spec(),
    continue_command_spec(),
    next_command_spec(),
    step_command_spec(),
    finish_command_spec(),
    legacy_print_command_spec(),
    legacy_list_command_spec(),
    help_command_spec(),
    quit_command_spec(),
  ])
}
