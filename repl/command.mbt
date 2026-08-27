///|
/// One immutable command constructed from one REPL input.
priv trait ReplCommand {
  async fn execute(Self, context : ReplContext) -> CommandResult
}

///|
/// The command name and remaining input after the REPL has split one line.
priv struct CommandInvocation {
  name : String
  arguments : String
}

///|
fn CommandInvocation::new(
  name : StringView,
  arguments : StringView,
) -> CommandInvocation {
  { name: name.to_owned(), arguments: arguments.to_owned(), }
}

///|
fn command_word_end(input : StringView) -> Int {
  for offset, character in input.iter2() {
    if character == ' ' || character == '\t' {
      return offset
    }
  }
  input.length()
}

///|
fn parse_command_invocation(line : StringView) -> CommandInvocation? {
  let input = line.trim_start(chars=" \t")
  guard input != "" else { return None }
  let word_end = command_word_end(input)
  CommandInvocation::new(
    input[:word_end],
    input[word_end:].trim(char_set=" \t"),
  )
  |> Some
}

///|
/// Result of the parser/factory owned by one CommandSpec.
priv enum CommandParseResult {
  ParsedCommand(&ReplCommand)
  InvalidCommand(String)
}

///|
fn[C : ReplCommand] parsed_command(command : C) -> CommandParseResult {
  ParsedCommand(command)
}

///|
fn invalid_command(message : String) -> CommandParseResult {
  InvalidCommand(message)
}

///|
test "command invocation splits one exact word after leading whitespace" {
  assert_true(
    parse_command_invocation("  break main.mbt:4")
    is Some({ name: "break", arguments: "main.mbt:4", }),
  )
  assert_true(
    parse_command_invocation("\trun\t") is Some({ name: "run", arguments: "", }),
  )
}

///|
test "blank input has no command invocation" {
  assert_true(parse_command_invocation("") is None)
  assert_true(parse_command_invocation(" \t ") is None)
}
