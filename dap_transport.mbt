///|
priv suberror DapTransportError {
  AdapterClosed
  MissingContentLength
  InvalidContentLength(String)
} derive(Debug)

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

///|
struct DapTransport {
  reader : @process.ReadFromProcess
  writer : @process.WriteToProcess
  process : @process.Process
  mut next_seq : Int
  mut closed : Bool
}

///|
async fn[X] DapTransport::start(
  group : @async.TaskGroup[X],
  adapter : String,
) -> DapTransport {
  let (child_stdin, writer) = @process.write_to_process()
  errdefer writer.close()
  let (reader, child_stdout) = @process.read_from_process()
  errdefer reader.close()
  let process = @process.spawn(
    group,
    adapter,
    [],
    inherit_env=true,
    stdin=child_stdin,
    stdout=child_stdout,
    no_wait=true,
  )
  { reader, writer, process, next_seq: 1, closed: false }
}

///|
async fn DapTransport::send_request(
  self : DapTransport,
  command : String,
  arguments : Json,
) -> Int {
  let seq = self.next_seq
  self.next_seq = seq + 1
  let message : Json = {
    "seq": seq,
    "type": "request",
    "command": command,
    "arguments": arguments,
  }
  self.writer.write(frame_message(message.stringify()))
  seq
}

///|
async fn DapTransport::receive(self : DapTransport) -> Json {
  guard read_frame(self.reader) is Some(body) else { raise AdapterClosed }
  @json.parse(body)
}

///|
fn DapTransport::close(self : DapTransport) -> Unit {
  if !self.closed {
    self.closed = true
    self.reader.close()
    self.writer.close()
    self.process.cancel()
  }
}
