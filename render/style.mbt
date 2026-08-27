///|
pub(all) struct Style {
  foreground : Color?
  bold : Bool
  italic : Bool
  underline : Bool
} derive(Eq, Debug)

///|
pub extend Style with Eq::{equal, not_equal}

///|
pub extend Style with Debug::{to_repr}

///|
pub fn Style::plain() -> Style {
  { foreground: None, bold: false, italic: false, underline: false, }
}

///|
pub fn Style::foreground(color : Color) -> Style {
  { foreground: Some(color), bold: false, italic: false, underline: false, }
}

///|
pub impl Default for Style with fn default() -> Style {
  Style::plain()
}

///|
pub extend Style with Default::{default}

///|
const ANSI_RESET : String = "\u001b[0m"

///|
fn Ansi16Color::sgr_code(self : Ansi16Color) -> Int {
  match self {
    Black => 30
    Red => 31
    Green => 32
    Yellow => 33
    Blue => 34
    Magenta => 35
    Cyan => 36
    White => 37
    BrightBlack => 90
    BrightRed => 91
    BrightGreen => 92
    BrightYellow => 93
    BrightBlue => 94
    BrightMagenta => 95
    BrightCyan => 96
    BrightWhite => 97
  }
}

///|
fn Style::ansi_parameters(self : Style) -> Array[Int] {
  let parameters : Array[Int] = []
  if self.bold {
    parameters.push(1)
  }
  if self.italic {
    parameters.push(3)
  }
  if self.underline {
    parameters.push(4)
  }
  match self.foreground {
    None => ()
    Some(Ansi16(color)) => parameters.push(color.sgr_code())
    Some(Ansi256(color)) => {
      parameters.push(38)
      parameters.push(5)
      parameters.push(color.to_int())
    }
    Some(Rgb(red, green, blue)) => {
      parameters.push(38)
      parameters.push(2)
      parameters.push(red.to_int())
      parameters.push(green.to_int())
      parameters.push(blue.to_int())
    }
  }
  parameters
}

///|
fn Style::write_ansi(
  self : Style,
  output : StringBuilder,
  text : StringView,
) -> Unit {
  let parameters = self.ansi_parameters()
  guard parameters.length() > 0 else {
    output.write_stringview(text)
    return
  }
  for line_index, line in text.split("\n") {
    if line_index > 0 {
      output.write_char('\n')
    }
    guard !line.is_empty() else { continue }
    output.write_string("\u001b[")
    for parameter_index, parameter in parameters {
      if parameter_index > 0 {
        output.write_char(';')
      }
      output.write_object(parameter)
    }
    output.write_char('m')
    output.write_stringview(line)
    output.write_string(ANSI_RESET)
  }
}
