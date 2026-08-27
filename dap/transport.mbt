///|
priv struct DapTransport {
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
  { reader, writer, process, next_seq: 1, closed: false, }
}

///|
async fn DapTransport::send_request(
  self : DapTransport,
  command : String,
  arguments : Json,
) -> Int {
  let seq = self.next_seq
  self.next_seq = seq + 1
  let message = request_message(seq, { command, arguments, })
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
