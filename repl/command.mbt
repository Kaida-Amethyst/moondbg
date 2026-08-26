///|
priv enum ReplCommand {
  Quit
  Help
  Run
  Break(String, Int)
  List
  Invalid(String)
  Unknown
}

///|
fn has_command_word(input : StringView, command : StringView) -> Bool {
  guard input.strip_prefix(command) is Some(rest) else { return false }
  rest == "" || rest.has_prefix(" ") || rest.has_prefix("\t")
}

///|
fn command_arguments(input : StringView, command : StringView) -> StringView? {
  guard input.strip_prefix(command) is Some(rest) else { return None }
  guard rest == "" || rest.has_prefix(" ") || rest.has_prefix("\t") else {
    return None
  }
  Some(rest.trim(char_set=" \t"))
}

///|
fn parse_breakpoint(arguments : StringView) -> ReplCommand {
  guard arguments != "" else { return Invalid("break requires <file>:<line>") }
  guard arguments.rev_find(":") is Some(separator) else {
    return Invalid("breakpoint must use <file>:<line>")
  }
  let source = arguments[0:separator].trim(char_set=" \t")
  let line_text = arguments[separator + 1:].trim(char_set=" \t")
  guard source != "" else { return Invalid("breakpoint file cannot be empty") }
  guard line_text != "" else {
    return Invalid("breakpoint line cannot be empty")
  }
  let parsed_line = Some(@string.parse_int(line_text, base=10)) catch {
    _ => None
  }
  guard parsed_line is Some(line) else {
    return Invalid("breakpoint line must be a positive integer")
  }
  guard line > 0 else {
    return Invalid("breakpoint line must be a positive integer")
  }
  Break(source.to_owned(), line)
}

///|
fn parse_repl_command(line : StringView) -> ReplCommand {
  let input = line.trim_start(chars=" \t")
  if has_command_word(input, "quit") || has_command_word(input, "exit") {
    return Quit
  }
  match command_arguments(input, "q") {
    Some("") => return Quit
    Some(_) => return Invalid("q does not accept arguments")
    None => ()
  }
  match command_arguments(input, "help") {
    Some("") => return Help
    Some(_) => return Invalid("help does not accept arguments")
    None => ()
  }
  match command_arguments(input, "run") {
    Some("") => return Run
    Some(_) => return Invalid("run does not accept arguments")
    None => ()
  }
  match command_arguments(input, "r") {
    Some("") => return Run
    Some(_) => return Invalid("r does not accept arguments")
    None => ()
  }
  match command_arguments(input, "break") {
    Some(arguments) => return parse_breakpoint(arguments)
    None => ()
  }
  match command_arguments(input, "b") {
    Some(arguments) => return parse_breakpoint(arguments)
    None => ()
  }
  match command_arguments(input, "list") {
    Some("") => return List
    Some(_) => return Invalid("list does not accept arguments")
    None => ()
  }
  Unknown
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

///|
test "P4 local commands and aliases parse without arguments" {
  assert_true(parse_repl_command("help") is Help)
  assert_true(parse_repl_command(" run\t") is Run)
  assert_true(parse_repl_command("r") is Run)
  assert_true(parse_repl_command("list") is List)
  assert_true(parse_repl_command("q") is Quit)
}

///|
test "source breakpoints use the final colon as the line separator" {
  assert_true(
    parse_repl_command("break main/main.mbt:4") is Break("main/main.mbt", 4),
  )
  assert_true(
    parse_repl_command("b C:/project/main.mbt:12")
    is Break("C:/project/main.mbt", 12),
  )
}

///|
test "malformed P4 commands report a local parse error" {
  let commands = [
    "break", "b main.mbt", "break :4", "break main.mbt:0", "break main.mbt:nope",
    "run now", "list around",
  ]
  for command in commands {
    assert_true(parse_repl_command(command) is Invalid(_), msg=command)
  }
}
