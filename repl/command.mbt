///|
priv enum ReplCommand {
  Quit
  Unknown
}

///|
fn has_command_word(input : StringView, command : StringView) -> Bool {
  guard input.strip_prefix(command) is Some(rest) else { return false }
  rest == "" || rest.has_prefix(" ") || rest.has_prefix("\t")
}

///|
fn parse_repl_command(line : StringView) -> ReplCommand {
  let input = line.trim_start(chars=" \t")
  if has_command_word(input, "quit") || has_command_word(input, "exit") {
    Quit
  } else {
    Unknown
  }
}

///|
test "quit and exit accept leading whitespace and ignored arguments" {
  let commands = [
    "exit", "quit", " exit 0", "   quit 1122", "\texit", "quit\tignored",
  ]
  for command in commands {
    assert_true(parse_repl_command(command) is Quit, msg=command)
  }
}

///|
test "quit and exit require an exact lowercase command word" {
  let commands = ["", "   ", "exiting", "exit0", "quitter", "QUIT"]
  for command in commands {
    assert_true(parse_repl_command(command) is Unknown, msg=command)
  }
}
