///|
/// A bidirectional transport for complete DAP JSON messages.
///
/// Framing, processes and in-memory scripted sessions can implement this port;
/// request sequence allocation and response routing remain owned by
/// `DapDispatcher`.
pub(open) trait DapTransport {
  async fn send_message(Self, message : Json) -> Unit
  async fn receive_message(Self) -> Json
  fn close(Self) -> Unit
}

///|
/// Open an adapter transport for event-driven protocol frontends. The caller
/// owns message routing and must close it before leaving the task group.
pub async fn[X] open_transport(
  group : @async.TaskGroup[X],
  adapter : String,
) -> &DapTransport {
  ProcessDapTransport::start(group, adapter)
}

///|
priv struct ProcessDapTransport {
  reader : @process.ReadFromProcess
  writer : @process.WriteToProcess
  process : @process.Process
  mut closed : Bool
}

///|
async fn[X] ProcessDapTransport::start(
  group : @async.TaskGroup[X],
  adapter : String,
) -> ProcessDapTransport {
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
  { reader, writer, process, closed: false, }
}

///|
impl DapTransport for ProcessDapTransport with fn send_message(self, message) {
  self.writer.write(frame_message(message.stringify()))
}

///|
impl DapTransport for ProcessDapTransport with fn receive_message(self) {
  guard read_frame(self.reader) is Some(body) else { raise AdapterClosed }
  @json.parse(body)
}

///|
impl DapTransport for ProcessDapTransport with fn close(self) {
  if !self.closed {
    self.closed = true
    self.reader.close()
    self.writer.close()
    self.process.cancel()
  }
}
