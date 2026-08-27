// Whitebox tests run within the package scope.
// Use them to validate internal helpers or invariants.
// Keep them focused; public behavior belongs in `_test.mbt`.

///|
fn render_with_style(style : Style, text : StringView) -> String {
  let output = StringBuilder()
  style.write_ansi(output, text)
  output.to_string()
}

///|
test "all ANSI16 foreground colors use their standard SGR codes" {
  let cases = [
    (Ansi16Color::Black, "\u001b[30mx\u001b[0m"),
    (Ansi16Color::Red, "\u001b[31mx\u001b[0m"),
    (Ansi16Color::Green, "\u001b[32mx\u001b[0m"),
    (Ansi16Color::Yellow, "\u001b[33mx\u001b[0m"),
    (Ansi16Color::Blue, "\u001b[34mx\u001b[0m"),
    (Ansi16Color::Magenta, "\u001b[35mx\u001b[0m"),
    (Ansi16Color::Cyan, "\u001b[36mx\u001b[0m"),
    (Ansi16Color::White, "\u001b[37mx\u001b[0m"),
    (Ansi16Color::BrightBlack, "\u001b[90mx\u001b[0m"),
    (Ansi16Color::BrightRed, "\u001b[91mx\u001b[0m"),
    (Ansi16Color::BrightGreen, "\u001b[92mx\u001b[0m"),
    (Ansi16Color::BrightYellow, "\u001b[93mx\u001b[0m"),
    (Ansi16Color::BrightBlue, "\u001b[94mx\u001b[0m"),
    (Ansi16Color::BrightMagenta, "\u001b[95mx\u001b[0m"),
    (Ansi16Color::BrightCyan, "\u001b[96mx\u001b[0m"),
    (Ansi16Color::BrightWhite, "\u001b[97mx\u001b[0m"),
  ]
  for _, case in cases {
    let (color, expected) = case
    assert_eq(
      render_with_style(Style::foreground(Ansi16(color)), "x"),
      expected,
    )
  }
}

///|
test "ANSI256 foreground supports both Byte boundaries" {
  assert_eq(
    render_with_style(Style::foreground(Ansi256(0)), "low"),
    "\u001b[38;5;0mlow\u001b[0m",
  )
  assert_eq(
    render_with_style(Style::foreground(Ansi256(255)), "high"),
    "\u001b[38;5;255mhigh\u001b[0m",
  )
}

///|
test "RGB foreground supports both Byte boundaries" {
  assert_eq(
    render_with_style(Style::foreground(Rgb(0, 0, 0)), "low"),
    "\u001b[38;2;0;0;0mlow\u001b[0m",
  )
  assert_eq(
    render_with_style(Style::foreground(Rgb(255, 255, 255)), "high"),
    "\u001b[38;2;255;255;255mhigh\u001b[0m",
  )
}

///|
test "attributes and foreground share one stable SGR sequence" {
  let style : Style = {
    foreground: Some(Ansi16(Red)),
    bold: true,
    italic: true,
    underline: true,
  }
  assert_eq(
    render_with_style(style, "combined"),
    "\u001b[1;3;4;31mcombined\u001b[0m",
  )
}

///|
test "attribute-only style has a start sequence and reset" {
  let style : Style = {
    foreground: None,
    bold: true,
    italic: false,
    underline: false,
  }
  assert_eq(render_with_style(style, "bold"), "\u001b[1mbold\u001b[0m")
}

///|
test "plain style emits neither a start sequence nor reset" {
  assert_eq(render_with_style(Style::plain(), "plain"), "plain")
}

///|
test "styled multiline text resets before and reopens after each newline" {
  assert_eq(
    render_with_style(Style::foreground(Ansi16(Red)), "first\nsecond\n"),
    "\u001b[31mfirst\u001b[0m\n\u001b[31msecond\u001b[0m\n",
  )
  assert_eq(render_with_style(Style::foreground(Ansi16(Red)), "\n\n"), "\n\n")
}

///|
test "theme maps every highlight kind to its corresponding style" {
  let theme = Theme::default()
  assert_eq(theme.style_for(Keyword), theme.keyword)
  assert_eq(theme.style_for(LowerIdentifier), theme.lower_identifier)
  assert_eq(theme.style_for(UpperIdentifier), theme.upper_identifier)
  assert_eq(theme.style_for(PackageName), theme.package_name)
  assert_eq(theme.style_for(Label), theme.label)
  assert_eq(theme.style_for(Number), theme.number)
  assert_eq(theme.style_for(String), theme.string)
  assert_eq(theme.style_for(Character), theme.character)
  assert_eq(theme.style_for(Boolean), theme.boolean)
  assert_eq(theme.style_for(Comment), theme.comment)
  assert_eq(theme.style_for(Attribute), theme.attribute)
  assert_eq(theme.style_for(Operator), theme.operator)
  assert_eq(theme.style_for(Punctuation), theme.punctuation)
}

///|
test "representative tokens cover every highlight category" {
  assert_true(classify_token(@tokens.TK_FN) is Some(Keyword))
  assert_true(classify_token(@tokens.TK_LIDENT) is Some(LowerIdentifier))
  assert_true(classify_token(@tokens.TK_UIDENT) is Some(UpperIdentifier))
  assert_true(classify_token(@tokens.TK_PACKAGE_NAME) is Some(PackageName))
  assert_true(classify_token(@tokens.TK_POST_LABEL) is Some(Label))
  assert_true(classify_token(@tokens.TK_INT) is Some(Number))
  assert_true(classify_token(@tokens.TK_STRING) is Some(String))
  assert_true(classify_token(@tokens.TK_CHAR) is Some(Character))
  assert_true(classify_token(@tokens.TK_TRUE) is Some(Boolean))
  assert_true(classify_token(@tokens.TK_COMMENT) is Some(Comment))
  assert_true(classify_token(@tokens.TK_ATTRIBUTE) is Some(Attribute))
  assert_true(classify_token(@tokens.TK_INFIX1) is Some(Operator))
  assert_true(classify_token(@tokens.TK_IMPLIES) is Some(Operator))
  assert_true(classify_token(@tokens.TK_LPAREN) is Some(Punctuation))
}

///|
test "accessors preserve lexical identifier and number categories" {
  assert_true(classify_token(@tokens.TK_DOT_LIDENT) is Some(LowerIdentifier))
  assert_true(classify_token(@tokens.TK_DOT_UIDENT) is Some(UpperIdentifier))
  assert_true(classify_token(@tokens.TK_DOT_INT) is Some(Number))
}

///|
test "labels and package names have dedicated categories" {
  assert_true(classify_token(@tokens.TK_POST_LABEL) is Some(Label))
  assert_true(classify_token(@tokens.TK_POST_LABEL_TRANSPARENT) is Some(Label))
  assert_true(classify_token(@tokens.TK_PACKAGE_NAME) is Some(PackageName))
}

///|
test "all interpolation token kinds are strings" {
  assert_true(classify_token(@tokens.TK_INTERP) is Some(String))
  assert_true(classify_token(@tokens.TK_BYTES_INTERP) is Some(String))
  assert_true(classify_token(@tokens.TK_MULTILINE_INTERP) is Some(String))
  assert_true(classify_token(@tokens.TK_REGEX_INTERP) is Some(String))
}

///|
test "explicit and automatic semicolons are punctuation" {
  let explicit = @tokens.Token::SEMI(true).kind()
  let automatic = @tokens.Token::SEMI(false).kind()
  assert_true(classify_token(explicit) is Some(Punctuation))
  assert_true(classify_token(automatic) is Some(Punctuation))
}

///|
test "newline and EOF do not receive a highlight style" {
  assert_true(classify_token(@tokens.TK_NEWLINE) is None)
  assert_true(classify_token(@tokens.TK_EOF) is None)
}
