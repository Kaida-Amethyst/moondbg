///|
fn strip_ansi(text : StringView) -> String {
  let output = StringBuilder(size_hint=text.length())
  let plain_start = for index = 0, plain_start = 0; index < text.length(); {
    if text[index] == 0x1B &&
      index + 1 < text.length() &&
      text[index + 1] == 0x5B {
      output.write_stringview(
        text.view(start_offset=plain_start, end_offset=index),
      )
      let after_sequence = for cursor = index + 2; cursor < text.length(); {
        if text[cursor] == 0x6D {
          break cursor + 1
        }
        continue cursor + 1
      } nobreak {
        text.length()
      }
      continue after_sequence, after_sequence
    }
    continue index + 1, plain_start
  } nobreak {
    plain_start
  }
  if plain_start < text.length() {
    output.write_stringview(text.view(start_offset=plain_start))
  }
  output.to_string()
}

///|
test "basic renderer handles empty and single-line source" {
  let theme = Theme::default()
  assert_eq(render_mbt_lexical("", theme), "")
  let source = "let answer = 42"
  let rendered = render_mbt_lexical(source, theme)
  assert_eq(strip_ansi(rendered), source)
  assert_true(rendered.has_prefix("\u001b[1;95mlet\u001b[0m"))
}

///|
test "basic renderer preserves trailing whitespace after the final token" {
  let source = "let answer = 42   "
  let rendered = render_mbt_lexical(source, Theme::default())
  assert_eq(strip_ansi(rendered), source)
  assert_true(rendered.has_suffix("   "))
}

///|
test "basic renderer preserves multiline comments and blank lines" {
  let source =
    #|// heading
    #|
    #|let value = 1 // trailing
    #|
  let rendered = render_mbt_lexical(source, Theme::default())
  assert_eq(strip_ansi(rendered), source)
  assert_true(rendered.contains("\u001b[3;90m// heading\u001b[0m"))
  assert_true(rendered.contains("\u001b[3;90m// trailing\u001b[0m"))
}

///|
test "explicit semicolon is preserved and ASI emits no source text" {
  let source =
    #|let first = 1;
    #|let second = 2
    #|
  let rendered = render_mbt_lexical(source, Theme::default())
  assert_eq(strip_ansi(rendered), source)
  assert_eq(strip_ansi(rendered).split(";").length(), 2)
}

///|
test "UTF-16 locations remain correct after emoji" {
  let source =
    #|let emoji = "😀"
    #|let answer = 42
  let rendered = render_mbt_lexical(source, Theme::default())
  assert_eq(strip_ansi(rendered), source)
  assert_true(rendered.contains("\u001b[94m42\u001b[0m"))
}

///|
test "renderer respects the bounds of a source StringView" {
  let backing = "PREFIX\nlet value = 7\nSUFFIX"
  let source = backing.view(start_offset=7, end_offset=backing.length() - 6)
  let rendered = render_mbt_lexical(source, Theme::default())
  assert_eq(strip_ansi(rendered), "let value = 7\n")
  assert_false(rendered.contains("PREFIX"))
  assert_false(rendered.contains("SUFFIX"))
}

///|
test "disabled color returns source exactly" {
  let source = "let emoji = \"😀\"\n"
  let rendered = render_mbt_lexical(source, Theme::none())
  assert_eq(rendered, source)
  assert_false(rendered.contains("\u001b["))
}

///|
test "custom theme changes the selected token style" {
  let theme : Theme = {
    ..Theme::default(),
    keyword: Style::foreground(Ansi256(200)),
  }
  let source = "let value = 1"
  let rendered = render_mbt_lexical(source, theme)
  assert_eq(strip_ansi(rendered), source)
  assert_true(rendered.has_prefix("\u001b[38;5;200mlet\u001b[0m"))
}

///|
fn interpolation_test_theme() -> Theme {
  {
    ..Theme::default(),
    string: Style::foreground(Ansi256(201)),
    number: Style::foreground(Ansi256(202)),
    operator: Style::foreground(Ansi256(203)),
  }
}

///|
fn lexer_has_token_kind(
  source : StringView,
  expected : @tokens.TokenKind,
) -> Bool {
  let result = @lexer.tokens_from_string_with_utf16_location(
    comment=true,
    source,
  )
  for _, triple in result.tokens {
    if triple.0.kind() == expected {
      return true
    }
  }
  false
}

///|
test "ordinary interpolation switches between string and expression styles" {
  let source = "\"sum: \\{1 + 2}\""
  assert_true(lexer_has_token_kind(source, @tokens.TK_INTERP))
  let rendered = render_mbt_lexical(source, interpolation_test_theme())
  assert_eq(
    rendered, "\u001b[38;5;201m\"sum: \\{\u001b[0m\u001b[38;5;202m1\u001b[0m \u001b[38;5;203m+\u001b[0m \u001b[38;5;202m2\u001b[0m\u001b[38;5;201m}\"\u001b[0m",
  )
  assert_eq(strip_ansi(rendered), source)
}

///|
test "one string can contain multiple interpolations" {
  let source = "\"first \\{1}, second \\{2}\""
  assert_true(lexer_has_token_kind(source, @tokens.TK_INTERP))
  let rendered = render_mbt_lexical(source, interpolation_test_theme())
  assert_eq(strip_ansi(rendered), source)
  assert_eq(rendered.split("\u001b[38;5;202m").length(), 3)
  assert_true(rendered.contains("\u001b[38;5;201m}, second \\{\u001b[0m"))
}

///|
test "nested interpolation recursively highlights the inner expression" {
  let source = "\"outer \\{\"inner \\{1 + 2}\"}\""
  assert_true(lexer_has_token_kind(source, @tokens.TK_INTERP))
  let rendered = render_mbt_lexical(source, interpolation_test_theme())
  assert_eq(strip_ansi(rendered), source)
  assert_true(rendered.contains("\u001b[38;5;202m1\u001b[0m"))
  assert_true(rendered.contains("\u001b[38;5;203m+\u001b[0m"))
  assert_true(rendered.contains("\u001b[38;5;201m}\"\u001b[0m"))
}

///|
test "bytes multiline and regex interpolations recurse into expressions" {
  let cases = [
    ("b\"bytes \\{1}\"", @tokens.TK_BYTES_INTERP),
    ("$|multiline \\{1}\n", @tokens.TK_MULTILINE_INTERP),
    ("re\"regex \\{1}\"", @tokens.TK_REGEX_INTERP),
  ]
  for _, case in cases {
    let (source, expected_kind) = case
    assert_true(lexer_has_token_kind(source, expected_kind))
    let rendered = render_mbt_lexical(source, interpolation_test_theme())
    assert_eq(strip_ansi(rendered), source)
    assert_true(rendered.contains("\u001b[38;5;202m1\u001b[0m"))
  }
}

///|
test "UTF-16 locations remain correct inside an interpolation expression" {
  let source = "\"emoji \\{(\"😀\", 42)}\""
  assert_true(lexer_has_token_kind(source, @tokens.TK_INTERP))
  let rendered = render_mbt_lexical(source, interpolation_test_theme())
  assert_eq(strip_ansi(rendered), source)
  assert_true(rendered.contains("\u001b[38;5;202m42\u001b[0m"))
}

///|
test "interpolation source locations cover only the expression" {
  let source = "\"left \\{  1 + 2  } right\""
  let result = @lexer.tokens_from_string_with_utf16_location(
    comment=true,
    source,
  )
  guard result.tokens[0].0 is INTERP(elements) else {
    fail("expected an INTERP token")
  }
  guard elements[1] is InterpSource({ loc, .. }) else {
    fail("expected an interpolation source")
  }
  assert_eq(
    source.view(start_offset=loc.start.cnum, end_offset=loc.end.cnum).to_owned(),
    "1 + 2",
  )
}
