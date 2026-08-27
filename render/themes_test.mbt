///|
fn theme_color_signature(theme : @render.Theme) -> Array[@render.Color?] {
  [
    theme.keyword.foreground,
    theme.lower_identifier.foreground,
    theme.upper_identifier.foreground,
    theme.package_name.foreground,
    theme.label.foreground,
    theme.number.foreground,
    theme.string.foreground,
    theme.character.foreground,
    theme.boolean.foreground,
    theme.comment.foreground,
    theme.attribute.foreground,
    theme.operator.foreground,
    theme.punctuation.foreground,
  ]
}

///|
fn built_in_themes() -> Array[@render.Theme] {
  [
    @render.Theme::dracula(),
    @render.Theme::one_dark(),
    @render.Theme::monokai(),
    @render.Theme::nord(),
    @render.Theme::gruvbox_dark(),
    @render.Theme::solarized_dark(),
    @render.Theme::solarized_light(),
    @render.Theme::tokyo_night(),
  ]
}

///|
test "built-in theme color mappings remain stable" {
  let themes = built_in_themes()
  debug_inspect(
    [
      theme_color_signature(themes[0]),
      theme_color_signature(themes[1]),
      theme_color_signature(themes[2]),
      theme_color_signature(themes[3]),
      theme_color_signature(themes[4]),
      theme_color_signature(themes[5]),
      theme_color_signature(themes[6]),
      theme_color_signature(themes[7]),
    ],
    content=(
      #|[
      #|  [
      #|    Some(Rgb(0xff, 0x79, 0xc6)),
      #|    Some(Rgb(0xf8, 0xf8, 0xf2)),
      #|    Some(Rgb(0x8b, 0xe9, 0xfd)),
      #|    Some(Rgb(0x8b, 0xe9, 0xfd)),
      #|    Some(Rgb(0xff, 0xb8, 0x6c)),
      #|    Some(Rgb(0xbd, 0x93, 0xf9)),
      #|    Some(Rgb(0xf1, 0xfa, 0x8c)),
      #|    Some(Rgb(0xf1, 0xfa, 0x8c)),
      #|    Some(Rgb(0xbd, 0x93, 0xf9)),
      #|    Some(Rgb(0x62, 0x72, 0xa4)),
      #|    Some(Rgb(0x50, 0xfa, 0x7b)),
      #|    Some(Rgb(0xff, 0x79, 0xc6)),
      #|    Some(Rgb(0xf8, 0xf8, 0xf2)),
      #|  ],
      #|  [
      #|    Some(Rgb(0xc6, 0x78, 0xdd)),
      #|    Some(Rgb(0xab, 0xb2, 0xbf)),
      #|    Some(Rgb(0xe5, 0xc0, 0x7b)),
      #|    Some(Rgb(0x56, 0xb6, 0xc2)),
      #|    Some(Rgb(0x61, 0xaf, 0xef)),
      #|    Some(Rgb(0xd1, 0x9a, 0x66)),
      #|    Some(Rgb(0x98, 0xc3, 0x79)),
      #|    Some(Rgb(0x98, 0xc3, 0x79)),
      #|    Some(Rgb(0xd1, 0x9a, 0x66)),
      #|    Some(Rgb(0x5c, 0x63, 0x70)),
      #|    Some(Rgb(0xd1, 0x9a, 0x66)),
      #|    Some(Rgb(0xab, 0xb2, 0xbf)),
      #|    Some(Rgb(0xab, 0xb2, 0xbf)),
      #|  ],
      #|  [
      #|    Some(Rgb(0xf9, 0x26, 0x72)),
      #|    Some(Rgb(0xf8, 0xf8, 0xf2)),
      #|    Some(Rgb(0xa6, 0xe2, 0x2e)),
      #|    Some(Rgb(0x66, 0xd9, 0xef)),
      #|    Some(Rgb(0x66, 0xd9, 0xef)),
      #|    Some(Rgb(0xae, 0x81, 0xff)),
      #|    Some(Rgb(0xe6, 0xdb, 0x74)),
      #|    Some(Rgb(0xe6, 0xdb, 0x74)),
      #|    Some(Rgb(0xae, 0x81, 0xff)),
      #|    Some(Rgb(0x75, 0x71, 0x5e)),
      #|    Some(Rgb(0xa6, 0xe2, 0x2e)),
      #|    Some(Rgb(0xf9, 0x26, 0x72)),
      #|    Some(Rgb(0xf8, 0xf8, 0xf2)),
      #|  ],
      #|  [
      #|    Some(Rgb(0x81, 0xa1, 0xc1)),
      #|    Some(Rgb(0xd8, 0xde, 0xe9)),
      #|    Some(Rgb(0x8f, 0xbc, 0xbb)),
      #|    Some(Rgb(0x88, 0xc0, 0xd0)),
      #|    Some(Rgb(0x5e, 0x81, 0xac)),
      #|    Some(Rgb(0xb4, 0x8e, 0xad)),
      #|    Some(Rgb(0xa3, 0xbe, 0x8c)),
      #|    Some(Rgb(0xeb, 0xcb, 0x8b)),
      #|    Some(Rgb(0xb4, 0x8e, 0xad)),
      #|    Some(Rgb(0x4c, 0x56, 0x6a)),
      #|    Some(Rgb(0xd0, 0x87, 0x70)),
      #|    Some(Rgb(0x81, 0xa1, 0xc1)),
      #|    Some(Rgb(0xec, 0xef, 0xf4)),
      #|  ],
      #|  [
      #|    Some(Rgb(0xfb, 0x49, 0x34)),
      #|    Some(Rgb(0xeb, 0xdb, 0xb2)),
      #|    Some(Rgb(0xfa, 0xbd, 0x2f)),
      #|    Some(Rgb(0x8e, 0xc0, 0x7c)),
      #|    Some(Rgb(0x83, 0xa5, 0x98)),
      #|    Some(Rgb(0xd3, 0x86, 0x9b)),
      #|    Some(Rgb(0xb8, 0xbb, 0x26)),
      #|    Some(Rgb(0x8e, 0xc0, 0x7c)),
      #|    Some(Rgb(0xd3, 0x86, 0x9b)),
      #|    Some(Rgb(0x92, 0x83, 0x74)),
      #|    Some(Rgb(0xfa, 0xbd, 0x2f)),
      #|    Some(Rgb(0xfe, 0x80, 0x19)),
      #|    Some(Rgb(0xeb, 0xdb, 0xb2)),
      #|  ],
      #|  [
      #|    Some(Rgb(0x85, 0x99, 0x00)),
      #|    Some(Rgb(0x83, 0x94, 0x96)),
      #|    Some(Rgb(0xb5, 0x89, 0x00)),
      #|    Some(Rgb(0x26, 0x8b, 0xd2)),
      #|    Some(Rgb(0xcb, 0x4b, 0x16)),
      #|    Some(Rgb(0x2a, 0xa1, 0x98)),
      #|    Some(Rgb(0x2a, 0xa1, 0x98)),
      #|    Some(Rgb(0xcb, 0x4b, 0x16)),
      #|    Some(Rgb(0xd3, 0x36, 0x82)),
      #|    Some(Rgb(0x58, 0x6e, 0x75)),
      #|    Some(Rgb(0xb5, 0x89, 0x00)),
      #|    Some(Rgb(0x85, 0x99, 0x00)),
      #|    Some(Rgb(0x83, 0x94, 0x96)),
      #|  ],
      #|  [
      #|    Some(Rgb(0x85, 0x99, 0x00)),
      #|    Some(Rgb(0x65, 0x7b, 0x83)),
      #|    Some(Rgb(0xb5, 0x89, 0x00)),
      #|    Some(Rgb(0x26, 0x8b, 0xd2)),
      #|    Some(Rgb(0xcb, 0x4b, 0x16)),
      #|    Some(Rgb(0x2a, 0xa1, 0x98)),
      #|    Some(Rgb(0x2a, 0xa1, 0x98)),
      #|    Some(Rgb(0xcb, 0x4b, 0x16)),
      #|    Some(Rgb(0xd3, 0x36, 0x82)),
      #|    Some(Rgb(0x93, 0xa1, 0xa1)),
      #|    Some(Rgb(0xb5, 0x89, 0x00)),
      #|    Some(Rgb(0x85, 0x99, 0x00)),
      #|    Some(Rgb(0x65, 0x7b, 0x83)),
      #|  ],
      #|  [
      #|    Some(Rgb(0xbb, 0x9a, 0xf7)),
      #|    Some(Rgb(0xc0, 0xca, 0xf5)),
      #|    Some(Rgb(0x7d, 0xcf, 0xff)),
      #|    Some(Rgb(0x2a, 0xc3, 0xde)),
      #|    Some(Rgb(0xe0, 0xaf, 0x68)),
      #|    Some(Rgb(0xff, 0x9e, 0x64)),
      #|    Some(Rgb(0x9e, 0xce, 0x6a)),
      #|    Some(Rgb(0x73, 0xda, 0xca)),
      #|    Some(Rgb(0xff, 0x9e, 0x64)),
      #|    Some(Rgb(0x51, 0x59, 0x7d)),
      #|    Some(Rgb(0x73, 0xda, 0xca)),
      #|    Some(Rgb(0x89, 0xdd, 0xff)),
      #|    Some(Rgb(0x89, 0xdd, 0xff)),
      #|  ],
      #|]
    ),
  )
  for theme in themes {
    assert_true(theme.comment.italic)
    assert_false(theme.comment.bold)
    assert_false(theme.comment.underline)
  }
}

///|
test "every built-in theme renders truecolor without changing source" {
  let source =
    #|/// Theme coverage.
    #|#deprecated("demo")
    #|pub struct Point { x : Int }
    #|fn describe(point : Point, label~ : String) -> Bool {
    #|  let answer = 42 + 'M'.to_int()
    #|  @json.Json::string("\{label}: \{answer}") == true
    #|}
  let themes = built_in_themes()
  for theme in themes {
    assert_true(theme.emit_color)
    let rendered = @render.render_mbt(source, theme~)
    assert_true(rendered.contains("\u001b[38;2;"))
    assert_eq(strip_ansi_for_public_test(rendered), source)
  }
  for first in 0..<themes.length() {
    for second in (first + 1)..<themes.length() {
      assert_false(themes[first] == themes[second])
    }
  }
}
