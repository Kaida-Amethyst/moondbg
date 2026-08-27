///|
pub(all) struct Theme {
  emit_color : Bool
  keyword : Style
  lower_identifier : Style
  upper_identifier : Style
  package_name : Style
  label : Style
  number : Style
  string : Style
  character : Style
  boolean : Style
  comment : Style
  attribute : Style
  operator : Style
  punctuation : Style
} derive(Eq, Debug)

///|
pub extend Theme with Eq::{equal, not_equal}

///|
pub extend Theme with Debug::{to_repr}

///|
pub impl Default for Theme with fn default() -> Theme {
  {
    emit_color: true,
    keyword: {
      ..Style::foreground(Color::Ansi16(Ansi16Color::BrightMagenta)),
      bold: true,
    },
    lower_identifier: Style::plain(),
    upper_identifier: Style::foreground(Color::Ansi16(Ansi16Color::BrightCyan)),
    package_name: Style::foreground(Color::Ansi16(Ansi16Color::Cyan)),
    label: Style::foreground(Color::Ansi16(Ansi16Color::BrightYellow)),
    number: Style::foreground(Color::Ansi16(Ansi16Color::BrightBlue)),
    string: Style::foreground(Color::Ansi16(Ansi16Color::Green)),
    character: Style::foreground(Color::Ansi16(Ansi16Color::BrightGreen)),
    boolean: Style::foreground(Color::Ansi16(Ansi16Color::BrightMagenta)),
    comment: {
      ..Style::foreground(Color::Ansi16(Ansi16Color::BrightBlack)),
      italic: true,
    },
    attribute: Style::foreground(Color::Ansi16(Ansi16Color::Yellow)),
    operator: Style::foreground(Color::Ansi16(Ansi16Color::BrightWhite)),
    punctuation: Style::plain(),
  }
}

///|
pub extend Theme with Default::{default}

///|
/// Disable ANSI styling while preserving the source exactly.
pub fn Theme::none() -> Theme {
  { ..Theme::default(), emit_color: false, }
}
