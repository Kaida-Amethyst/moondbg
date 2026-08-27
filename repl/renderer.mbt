///|
priv struct HumanRenderer {}

///|
fn HumanRenderer::new() -> HumanRenderer {
  HumanRenderer::{ }
}

///|
fn help_padding(width : Int, content_length : Int) -> String {
  let padding = width - content_length
  " ".repeat(if padding > 1 { padding } else { 2 })
}

///|
fn format_help_entry(entry : CommandHelpEntry) -> String {
  let alias_usage = entry.alias_usage()
  guard alias_usage != "" else {
    let padding = help_padding(38, entry.usage.length())
    return "  \{entry.usage}\{padding}\{entry.summary}"
  }
  let multiple_aliases = entry.aliases.length() > 1
  let usage_width = if multiple_aliases { 22 } else { 21 }
  let usage_padding = help_padding(usage_width, entry.usage.length())
  let alias_padding = help_padding(17, alias_usage.length())
  "  \{entry.usage}\{usage_padding}\{alias_usage}\{alias_padding}\{entry.summary}"
}

///|
fn render_help(entries : Array[CommandHelpEntry]) -> Unit {
  println("Commands:")
  for entry in entries {
    println(format_help_entry(entry))
  }
}

///|
impl PresentationRenderer for HumanRenderer with fn render(_self, events) {
  for event in events {
    match event {
      HelpPresentation(entries) => render_help(entries)
      ErrorPresentation(message) => println(message)
    }
  }
}
