// Blackbox tests run against the package's public API. Use `@render` to import.
// Prefer high-level behaviors over implementation details.
// Run `moon test` to execute and `moon test --update` to refresh snapshots.

///|
fn[T : Debug] require_debug(_value : T) -> Unit {
  Repr(_value) |> ignore
}

///|
fn strip_ansi_for_public_test(text : StringView) -> String {
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
test "plain style has no foreground or attributes" {
  let style = @render.Style::plain()
  assert_eq(style.foreground, None)
  assert_false(style.bold)
  assert_false(style.italic)
  assert_false(style.underline)
  assert_eq(style, @render.Style::default())
}

///|
test "foreground style changes only the foreground" {
  let color = @render.Color::Ansi16(@render.Ansi16Color::BrightCyan)
  let style = @render.Style::foreground(color)
  assert_eq(style.foreground, Some(color))
  assert_false(style.bold)
  assert_false(style.italic)
  assert_false(style.underline)
}

///|
test "default theme enables ANSI16 colors" {
  let theme = @render.Theme::default()
  assert_true(theme.emit_color)
  assert_eq(
    theme.keyword.foreground,
    Some(@render.Color::Ansi16(@render.Ansi16Color::BrightMagenta)),
  )
  assert_true(theme.keyword.bold)
  assert_eq(theme.lower_identifier, @render.Style::plain())
  assert_eq(theme.punctuation, @render.Style::plain())
  let none = @render.Theme::none()
  assert_false(none.emit_color)
  assert_eq({ ..none, emit_color: true, }, @render.Theme::default())
}

///|
test "ANSI256 and RGB colors use Byte payloads" {
  let minimum : Byte = 0
  let maximum : Byte = 255
  assert_eq(@render.Color::Ansi256(minimum), @render.Color::Ansi256(0))
  assert_eq(@render.Color::Ansi256(maximum), @render.Color::Ansi256(255))
  assert_eq(
    @render.Color::Rgb(minimum, 127, maximum),
    @render.Color::Rgb(0, 127, 255),
  )
}

///|
test "public theme types implement Eq and Debug" {
  let theme = @render.Theme::default()
  assert_true(theme == @render.Theme::default())
  require_debug(@render.Ansi16Color::Red)
  require_debug(@render.Color::Ansi16(@render.Ansi16Color::Red))
  require_debug(@render.Style::plain())
  require_debug(theme)
}

///|
test "public renderer uses the default ANSI theme and preserves source" {
  let source = "let value = 42"
  let rendered = @render.render_mbt(source)
  debug_inspect(
    rendered,
    content=(
      #|"\u{1b}[1;95mlet\u{1b}[0m value \u{1b}[97m=\u{1b}[0m \u{1b}[94m42\u{1b}[0m"
    ),
  )
  assert_true(rendered.contains("\u001b["))
  assert_eq(strip_ansi_for_public_test(rendered), source)
}

///|
test "public renderer accepts a custom theme" {
  let theme : @render.Theme = {
    ..@render.Theme::default(),
    keyword: @render.Style::foreground(@render.Color::Rgb(1, 2, 3)),
  }
  let source = "let value = 42"
  let rendered = @render.render_mbt(source, theme~)
  debug_inspect(
    rendered,
    content=(
      #|"\u{1b}[38;2;1;2;3mlet\u{1b}[0m value \u{1b}[97m=\u{1b}[0m \u{1b}[94m42\u{1b}[0m"
    ),
  )
  assert_true(rendered.has_prefix("\u001b[38;2;1;2;3mlet\u001b[0m"))
  assert_eq(strip_ansi_for_public_test(rendered), source)
}

///|
test "public renderer returns source exactly when color is disabled" {
  let source = "let message = \"answer: \\{40 + 2}\"\n"
  assert_eq(@render.render_mbt(source, theme=@render.Theme::none()), source)
}
