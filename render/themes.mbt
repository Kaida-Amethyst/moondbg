///|
fn rgb_style(red : Byte, green : Byte, blue : Byte) -> Style {
  Style::foreground(Color::Rgb(red, green, blue))
}

///|
fn italic_rgb_style(red : Byte, green : Byte, blue : Byte) -> Style {
  { ..rgb_style(red, green, blue), italic: true, }
}

///|
/// A Dracula-inspired theme for dark terminal backgrounds.
pub fn Theme::dracula() -> Theme {
  {
    emit_color: true,
    keyword: rgb_style(255, 121, 198),
    lower_identifier: rgb_style(248, 248, 242),
    upper_identifier: rgb_style(139, 233, 253),
    package_name: rgb_style(139, 233, 253),
    label: rgb_style(255, 184, 108),
    number: rgb_style(189, 147, 249),
    string: rgb_style(241, 250, 140),
    character: rgb_style(241, 250, 140),
    boolean: rgb_style(189, 147, 249),
    comment: italic_rgb_style(98, 114, 164),
    attribute: rgb_style(80, 250, 123),
    operator: rgb_style(255, 121, 198),
    punctuation: rgb_style(248, 248, 242),
  }
}

///|
/// A One Dark-inspired theme for dark terminal backgrounds.
pub fn Theme::one_dark() -> Theme {
  {
    emit_color: true,
    keyword: rgb_style(198, 120, 221),
    lower_identifier: rgb_style(171, 178, 191),
    upper_identifier: rgb_style(229, 192, 123),
    package_name: rgb_style(86, 182, 194),
    label: rgb_style(97, 175, 239),
    number: rgb_style(209, 154, 102),
    string: rgb_style(152, 195, 121),
    character: rgb_style(152, 195, 121),
    boolean: rgb_style(209, 154, 102),
    comment: italic_rgb_style(92, 99, 112),
    attribute: rgb_style(209, 154, 102),
    operator: rgb_style(171, 178, 191),
    punctuation: rgb_style(171, 178, 191),
  }
}

///|
/// A classic Monokai-inspired theme for dark terminal backgrounds.
pub fn Theme::monokai() -> Theme {
  {
    emit_color: true,
    keyword: rgb_style(249, 38, 114),
    lower_identifier: rgb_style(248, 248, 242),
    upper_identifier: rgb_style(166, 226, 46),
    package_name: rgb_style(102, 217, 239),
    label: rgb_style(102, 217, 239),
    number: rgb_style(174, 129, 255),
    string: rgb_style(230, 219, 116),
    character: rgb_style(230, 219, 116),
    boolean: rgb_style(174, 129, 255),
    comment: italic_rgb_style(117, 113, 94),
    attribute: rgb_style(166, 226, 46),
    operator: rgb_style(249, 38, 114),
    punctuation: rgb_style(248, 248, 242),
  }
}

///|
/// A Nord-inspired theme for dark terminal backgrounds.
pub fn Theme::nord() -> Theme {
  {
    emit_color: true,
    keyword: rgb_style(129, 161, 193),
    lower_identifier: rgb_style(216, 222, 233),
    upper_identifier: rgb_style(143, 188, 187),
    package_name: rgb_style(136, 192, 208),
    label: rgb_style(94, 129, 172),
    number: rgb_style(180, 142, 173),
    string: rgb_style(163, 190, 140),
    character: rgb_style(235, 203, 139),
    boolean: rgb_style(180, 142, 173),
    comment: italic_rgb_style(76, 86, 106),
    attribute: rgb_style(208, 135, 112),
    operator: rgb_style(129, 161, 193),
    punctuation: rgb_style(236, 239, 244),
  }
}

///|
/// A Gruvbox Dark-inspired theme for dark terminal backgrounds.
pub fn Theme::gruvbox_dark() -> Theme {
  {
    emit_color: true,
    keyword: rgb_style(251, 73, 52),
    lower_identifier: rgb_style(235, 219, 178),
    upper_identifier: rgb_style(250, 189, 47),
    package_name: rgb_style(142, 192, 124),
    label: rgb_style(131, 165, 152),
    number: rgb_style(211, 134, 155),
    string: rgb_style(184, 187, 38),
    character: rgb_style(142, 192, 124),
    boolean: rgb_style(211, 134, 155),
    comment: italic_rgb_style(146, 131, 116),
    attribute: rgb_style(250, 189, 47),
    operator: rgb_style(254, 128, 25),
    punctuation: rgb_style(235, 219, 178),
  }
}

///|
/// A Solarized Dark-inspired theme for dark terminal backgrounds.
pub fn Theme::solarized_dark() -> Theme {
  {
    emit_color: true,
    keyword: rgb_style(133, 153, 0),
    lower_identifier: rgb_style(131, 148, 150),
    upper_identifier: rgb_style(181, 137, 0),
    package_name: rgb_style(38, 139, 210),
    label: rgb_style(203, 75, 22),
    number: rgb_style(42, 161, 152),
    string: rgb_style(42, 161, 152),
    character: rgb_style(203, 75, 22),
    boolean: rgb_style(211, 54, 130),
    comment: italic_rgb_style(88, 110, 117),
    attribute: rgb_style(181, 137, 0),
    operator: rgb_style(133, 153, 0),
    punctuation: rgb_style(131, 148, 150),
  }
}

///|
/// A Solarized Light-inspired theme for light terminal backgrounds.
pub fn Theme::solarized_light() -> Theme {
  {
    emit_color: true,
    keyword: rgb_style(133, 153, 0),
    lower_identifier: rgb_style(101, 123, 131),
    upper_identifier: rgb_style(181, 137, 0),
    package_name: rgb_style(38, 139, 210),
    label: rgb_style(203, 75, 22),
    number: rgb_style(42, 161, 152),
    string: rgb_style(42, 161, 152),
    character: rgb_style(203, 75, 22),
    boolean: rgb_style(211, 54, 130),
    comment: italic_rgb_style(147, 161, 161),
    attribute: rgb_style(181, 137, 0),
    operator: rgb_style(133, 153, 0),
    punctuation: rgb_style(101, 123, 131),
  }
}

///|
/// A Tokyo Night-inspired theme for dark terminal backgrounds.
pub fn Theme::tokyo_night() -> Theme {
  {
    emit_color: true,
    keyword: rgb_style(187, 154, 247),
    lower_identifier: rgb_style(192, 202, 245),
    upper_identifier: rgb_style(125, 207, 255),
    package_name: rgb_style(42, 195, 222),
    label: rgb_style(224, 175, 104),
    number: rgb_style(255, 158, 100),
    string: rgb_style(158, 206, 106),
    character: rgb_style(115, 218, 202),
    boolean: rgb_style(255, 158, 100),
    comment: italic_rgb_style(81, 89, 125),
    attribute: rgb_style(115, 218, 202),
    operator: rgb_style(137, 221, 255),
    punctuation: rgb_style(137, 221, 255),
  }
}
