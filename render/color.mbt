///|
pub(all) enum Ansi16Color {
  Black
  Red
  Green
  Yellow
  Blue
  Magenta
  Cyan
  White
  BrightBlack
  BrightRed
  BrightGreen
  BrightYellow
  BrightBlue
  BrightMagenta
  BrightCyan
  BrightWhite
} derive(Eq, Debug)

///|
pub extend Ansi16Color with Eq::{equal, not_equal}

///|
pub extend Ansi16Color with Debug::{to_repr}

///|
pub(all) enum Color {
  Ansi16(Ansi16Color)
  Ansi256(Byte)
  Rgb(Byte, Byte, Byte)
} derive(Eq, Debug)

///|
pub extend Color with Eq::{equal, not_equal}

///|
pub extend Color with Debug::{to_repr}
