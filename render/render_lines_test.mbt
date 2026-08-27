///|
fn strip_rendered_lines(lines : Array[String]) -> String {
  lines.map(line => strip_ansi_for_public_test(line)).join("\n")
}

///|
fn last_ansi_sequence_is_reset(line : StringView) -> Bool {
  match line.rev_find("\u001b[") {
    None => true
    Some(index) => line.view(start_offset=index).has_prefix("\u001b[0m")
  }
}

///|
fn assert_independent_ansi_lines(lines : Array[String]) -> Unit raise {
  for _, line in lines {
    assert_false(line.contains("\n"))
    assert_true(last_ansi_sequence_is_reset(line))
  }
}

///|
test "line renderer preserves source and isolates ANSI state" {
  let source = "let first = 1\nlet second = \"😀\"\n"
  let lines = @render.render_mbt_lines(source)
  assert_eq(lines.length(), 3)
  assert_eq(strip_rendered_lines(lines), source)
  assert_true(lines[0].contains("\u001b["))
  assert_true(lines[1].contains("\u001b["))
  assert_eq(lines[2], "")
  assert_independent_ansi_lines(lines)
}

///|
test "line renderer preserves empty lines CRLF and trailing newline" {
  let theme = @render.Theme::none()
  assert_eq(@render.render_mbt_lines("", theme~), [""])
  assert_eq(@render.render_mbt_lines("\n\n", theme~), ["", "", ""])
  let source = "let emoji = \"😀\"\r\n\r\n"
  let lines = @render.render_mbt_lines(source, theme~)
  assert_eq(lines, ["let emoji = \"😀\"\r", "\r", ""])
  assert_eq(lines.join("\n"), source)
  for _, line in lines {
    assert_false(line.contains("\u001b["))
  }
}

///|
test "line renderer highlights multiline literal interpolation and comments" {
  let theme : @render.Theme = {
    ..@render.Theme::default(),
    string: @render.Style::foreground(@render.Color::Ansi256(201)),
    number: @render.Style::foreground(@render.Color::Ansi256(202)),
    operator: @render.Style::foreground(@render.Color::Ansi256(203)),
    comment: @render.Style::foreground(@render.Color::Ansi256(204)),
  }
  let source =
    #|#|first
    #|#|second 😀
    #|$|sum \{1 + 2}
    #|$|nested \{"inner \{3}"}
    #|// comment one
    #|/// comment two
  let lines = @render.render_mbt_lines(source, theme~)
  assert_eq(lines.length(), 6)
  assert_eq(strip_rendered_lines(lines), source)
  assert_true(lines[0].contains("\u001b[38;5;201m"))
  assert_true(lines[1].contains("\u001b[38;5;201m"))
  assert_true(lines[2].contains("\u001b[38;5;202m1\u001b[0m"))
  assert_true(lines[2].contains("\u001b[38;5;203m+\u001b[0m"))
  assert_true(lines[3].contains("\u001b[38;5;202m3\u001b[0m"))
  assert_true(lines[4].contains("\u001b[38;5;204m"))
  assert_true(lines[5].contains("\u001b[38;5;204m"))
  assert_independent_ansi_lines(lines)
}
