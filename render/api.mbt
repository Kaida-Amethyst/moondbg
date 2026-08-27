///|
/// Render MoonBit source code with an optional ANSI terminal theme.
/// Use `Theme::none()` to return the source without ANSI styling.
pub fn render_mbt(
  source : StringView,
  theme? : Theme = Theme::default(),
) -> String {
  render_mbt_lexical(source, theme)
}

///|
/// Render MoonBit source as independently styled terminal lines.
/// Each returned string excludes its source newline and leaves ANSI state reset.
pub fn render_mbt_lines(
  source : StringView,
  theme? : Theme = Theme::default(),
) -> Array[String] {
  render_mbt(source, theme~).split("\n").map(line => line.to_owned()).collect()
}
