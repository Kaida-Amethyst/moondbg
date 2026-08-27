///|
fn frame_message(body : String) -> String {
  "Content-Length: " +
  @utf8.encode(body).length().to_string() +
  "\r\n\r\n" +
  body
}

///|
fn parse_content_length(line : String) -> Int? {
  let trimmed = line.trim(char_set="\r\n ")
  let prefix = "content-length:"
  guard trimmed.to_lower().strip_prefix(prefix) is Some(length) else {
    return None
  }
  Some(@string.parse_int(length.trim(), base=10)) catch {
    _ => None
  }
}

///|
async fn read_frame(reader : &@io.Reader) -> String? {
  let mut content_length = -1
  for ;; {
    guard reader.read_until("\n") is Some(line) else { return None }
    if line.trim(char_set="\r\n") == "" {
      break
    }
    if parse_content_length(line) is Some(length) {
      guard length >= 0 else { raise InvalidContentLength(line) }
      content_length = length
    }
  }
  guard content_length >= 0 else { raise MissingContentLength }
  Some(@utf8.decode(reader.read_exactly(content_length)))
}
