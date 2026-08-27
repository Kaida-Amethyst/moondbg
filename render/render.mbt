///|
fn render_mbt_lexical(source : StringView, theme : Theme) -> String {
  guard theme.emit_color else { return source.to_owned() }
  let output = StringBuilder(size_hint=source.length())
  render_lexed_into(source, theme, output)
  output.to_string()
}

///|
fn render_lexed_into(
  source : StringView,
  theme : Theme,
  output : StringBuilder,
) -> Unit {
  let result = @lexer.tokens_from_string_with_utf16_location(
    comment=true,
    source,
  )
  let cursor = for _, triple in result.tokens; cursor = 0 {
    let (token, start, end) = triple
    guard start.cnum < end.cnum else { continue cursor }
    if cursor < start.cnum {
      output.write_stringview(
        source.view(start_offset=cursor, end_offset=start.cnum),
      )
    }
    render_token_into(token, source, start.cnum, end.cnum, theme, output)
    continue end.cnum
  } nobreak {
    cursor
  }
  if cursor < source.length() {
    output.write_stringview(source.view(start_offset=cursor))
  }
}

///|
fn render_token_into(
  token : @tokens.Token,
  source : StringView,
  start : Int,
  end : Int,
  theme : Theme,
  output : StringBuilder,
) -> Unit {
  match token {
    INTERP(elements) =>
      render_interpolation_into(source, elements, start, end, theme, output)
    BYTES_INTERP(elements) =>
      render_interpolation_into(source, elements, start, end, theme, output)
    MULTILINE_INTERP(elements) =>
      render_interpolation_into(source, elements, start, end, theme, output)
    REGEX_INTERP(elements) =>
      render_interpolation_into(source, elements, start, end, theme, output)
    _ => {
      let token_source = source.view(start_offset=start, end_offset=end)
      match classify_token(token.kind()) {
        None => output.write_stringview(token_source)
        Some(kind) => theme.style_for(kind).write_ansi(output, token_source)
      }
    }
  }
}

///|
fn render_interpolation_into(
  source : StringView,
  elements : @tokens.InterpLiteral,
  token_start : Int,
  token_end : Int,
  theme : Theme,
  output : StringBuilder,
) -> Unit {
  let string_style = theme.string
  let cursor = for _, element in elements; cursor = token_start {
    match element {
      InterpLit(..) => continue cursor
      InterpSource({ loc, .. }) => {
        if cursor < loc.start.cnum {
          string_style.write_ansi(
            output,
            source.view(start_offset=cursor, end_offset=loc.start.cnum),
          )
        }
        render_lexed_into(
          source.view(start_offset=loc.start.cnum, end_offset=loc.end.cnum),
          theme,
          output,
        )
        continue loc.end.cnum
      }
    }
  } nobreak {
    cursor
  }
  if cursor < token_end {
    string_style.write_ansi(
      output,
      source.view(start_offset=cursor, end_offset=token_end),
    )
  }
}
