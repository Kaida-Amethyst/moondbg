///|
/// Shared client sequence space plus the connection-test state machine.
priv struct ConnectionSession {
  mut next_seq : Int
  mut last_request_seq : Int
  mut initialized : Bool
  mut launch_seq : Int?
  mut finished : Bool
  mut closed : Bool
}

///|
priv suberror ConnectionError {
  InvalidClientRequest
  HandshakeTimeout
} derive(Debug)

///|
fn ConnectionSession::new() -> ConnectionSession {
  {
    next_seq: 1,
    last_request_seq: 0,
    initialized: false,
    launch_seq: None,
    finished: false,
    closed: false,
  }
}

///|
fn ConnectionSession::response(
  self : ConnectionSession,
  request_seq : Int,
  command : String,
  body? : Json = {},
  error? : String? = None,
) -> Json {
  let seq = self.next_seq
  self.next_seq += 1
  match error {
    Some(message) =>
      {
        "seq": seq,
        "type": "response",
        "request_seq": request_seq,
        "command": command,
        "success": false,
        "message": message,
      }
    None =>
      {
        "seq": seq,
        "type": "response",
        "request_seq": request_seq,
        "command": command,
        "success": true,
        "body": body,
      }
  }
}

///|
fn ConnectionSession::event(
  self : ConnectionSession,
  name : String,
  body : Json,
) -> Json {
  let seq = self.next_seq
  self.next_seq += 1
  { "seq": seq, "type": "event", "event": name, "body": body }
}

///|
#warnings("-unused_value")
fn ConnectionSession::handle(
  self : ConnectionSession,
  message : Json,
) -> Array[Json] raise {
  let (seq, command, arguments) = self.read_request(message)
  self.handle_request(seq, command, arguments)
}

///|
fn ConnectionSession::read_request(
  self : ConnectionSession,
  message : Json,
) -> (Int, String, Json) raise {
  guard message
    is {
      "seq": Number(raw_seq, ..),
      "type": String("request"),
      "command": String(command),
      ..
    } &&
    raw_seq >= 1 &&
    raw_seq <= 2147483647 &&
    raw_seq == raw_seq.to_int().to_double() &&
    raw_seq.to_int() > self.last_request_seq &&
    command != "" else {
    raise InvalidClientRequest
  }
  let seq = raw_seq.to_int()
  self.last_request_seq = seq
  let arguments : Json = match message {
    { "arguments": arguments, .. } => arguments
    _ => {}
  }
  (seq, command, arguments)
}

///|
fn ConnectionSession::handle_request(
  self : ConnectionSession,
  seq : Int,
  command : String,
  arguments : Json,
) -> Array[Json] {
  if command == "disconnect" {
    let messages = []
    if self.launch_seq is Some(pending) {
      messages.push(
        self.response(
          pending,
          "launch",
          error=Some("Connection test cancelled."),
        ),
      )
      self.launch_seq = None
    }
    messages.push(self.response(seq, command))
    self.closed = true
    return messages
  }
  if command == "initialize" && !self.initialized {
    if arguments is { "pathFormat": String("uri"), .. } ||
      arguments is { "linesStartAt1": False, .. } ||
      arguments is { "columnsStartAt1": False, .. } {
      return [
        self.response(
          seq,
          command,
          error=Some(
            "moondbg requires native paths and 1-based lines and columns.",
          ),
        ),
      ]
    }
    self.initialized = true
    return [
      self.response(seq, command, body={
        "supportsConfigurationDoneRequest": true,
        "supportsFunctionBreakpoints": true,
        "supportsConditionalBreakpoints": false,
        "supportsEvaluateForHovers": true,
        "supportsTerminateRequest": false,
        "supportsRestartRequest": false,
        "exceptionBreakpointFilters": [
          {
            "filter": "moonbit-panic",
            "label": "MoonBit panic",
            "default": true,
            "description": "Stop at MoonBit panic before process exit. Disabling this does not disable SIGABRT stops.",
          },
        ],
      }),
    ]
  }
  // VS Code can request threads after launch while processing terminated.
  // There is no target and therefore no thread to show.
  if self.initialized && command == "threads" {
    return [self.response(seq, command, body={ "threads": [] })]
  }
  guard self.initialized && !self.finished else {
    return [
      self.response(
        seq,
        command,
        error=Some("No active connection test. Initialize first."),
      ),
    ]
  }
  match command {
    "launch" => {
      guard self.launch_seq is None &&
        arguments is { "connectionTest": True, .. } else {
        return [
          self.response(
            seq,
            command,
            error=Some(
              "Only one launch with connectionTest: true is supported; no program will be run.",
            ),
          ),
        ]
      }
      // Reply to launch only after configurationDone. The reader must remain
      // available for VS Code's configuration requests in the meantime.
      self.launch_seq = Some(seq)
      [self.event("initialized", {})]
    }
    "configurationDone" => {
      guard self.launch_seq is Some(pending) else {
        return [
          self.response(
            seq,
            command,
            error=Some("Launch the connection test first."),
          ),
        ]
      }
      self.launch_seq = None
      self.finished = true
      [
        self.response(seq, command),
        self.response(pending, "launch"),
        self.event("output", {
          "category": "console",
          "output": "DAP 连接验证成功。未启动用户程序或 lldb-dap；验证会话已结束。\n",
        }),
        self.event("terminated", {}),
      ]
    }
    "setBreakpoints" | "setFunctionBreakpoints" => {
      guard arguments is { "breakpoints": Array(points), .. } else {
        return [
          self.response(
            seq,
            command,
            error=Some("Expected a breakpoints array."),
          ),
        ]
      }
      // Existing editor breakpoints must not appear verified in this smoke test.
      let rejected : Array[Json] = points.map(_ => {
        "verified": false,
        "message": "Connection test only; no program is loaded.",
      })
      [self.response(seq, command, body={ "breakpoints": rejected })]
    }
    "setExceptionBreakpoints" => {
      let enabled = panic_filter(arguments) catch {
        error =>
          return [
            self.response(seq, command, error=Some(launch_error_message(error))),
          ]
      }
      if enabled {
        return [
          self.response(seq, command, body={
            "breakpoints": [
              {
                "verified": false,
                "message": "Connection test only; no program is loaded.",
              },
            ],
          }),
        ]
      }
      [self.response(seq, command, body={ "breakpoints": [] })]
    }
    _ =>
      [
        self.response(
          seq,
          command,
          error=Some("Unsupported request in connection-test mode: \{command}"),
        ),
      ]
  }
}
