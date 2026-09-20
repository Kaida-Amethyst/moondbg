///|
fn launch_error_message(error : Error) -> String {
  match error {
    LiveError(message) | @launch.LaunchError(message) => message
    _ => @debug.to_string(error)
  }
}

///|
async fn prepare_launch(
  arguments : Json,
  output : async (String, String) -> Unit,
) -> Json {
  validate_launch_options(arguments)
  guard arguments is Object(fields) else {
    raise LiveError("Expected launch arguments")
  }
  let has_package = fields.contains("package")
  let has_program = fields.contains("program")
  guard has_package != has_program else {
    raise LiveError("Specify exactly one of launch.package and launch.program")
  }
  guard has_package else { return launch_arguments(arguments) }
  guard fields.get("package") is Some(String(directory)) &&
    directory.has_prefix("/") else {
    raise LiveError("launch.package must be an absolute package directory path")
  }
  guard @fs.exists(directory) && @fs.kind(directory) is Directory else {
    raise LiveError("Package directory does not exist: \{directory}")
  }
  let default_cwd = @fs.realpath(directory)
  // Reject invalid cwd before starting any build subprocess.
  validate_launch_cwd(arguments, default_cwd) |> ignore
  output("console", "moondbg: Building package \{directory}\n")
  let prepared = @launch.prepare_target(directory, output~)
  output("console", "moondbg: Build succeeded. Starting debugger.\n")
  let live_fields = fields.copy()
  live_fields.remove("package")
  live_fields.set("program", Json(prepared.executable))
  if !live_fields.contains("cwd") {
    live_fields.set("cwd", Json(prepared.working_directory))
  }
  launch_arguments(Json(live_fields))
}

///|
// A single client reader lives across preparation and the live session. Never
// cancel a half-read DAP frame merely to switch from building to debugging.
async fn serve_launch(
  reader : &@io.Reader,
  writer : &@io.Writer,
  client : ConnectionSession,
  launch_seq : Int,
  arguments : Json,
) -> Unit {
  @async.with_task_group(group => {
    let inbox : @async.Queue[LiveInput] = @async.Queue(kind=Blocking(128))
    defer inbox.close()
    let input_task = group.spawn(no_wait=true, () => {
      try {
        while @dap.read_frame(reader) is Some(text) {
          inbox.put(Client(Some(text)))
        }
        inbox.put(Client(None))
      } catch {
        error =>
          if !@async.is_cancellation_error(error) {
            inbox.put(Failed(launch_error_message(error)))
          }
      }
    })
    defer input_task.cancel()
    let prepared = await_preparation(
      writer, client, launch_seq, arguments, inbox,
    )
    if prepared is Some(launch_args) {
      serve_live(inbox, writer, client, launch_seq, launch_args)
    }
  })
}

///|
async fn await_preparation(
  writer : &@io.Writer,
  client : ConnectionSession,
  launch_seq : Int,
  arguments : Json,
  inbox : @async.Queue[LiveInput],
  prepare? : async (Json, async (String, String) -> Unit) -> Json = prepare_launch,
) -> Json? {
  // Group teardown waits for cancellation cleanup before returning to the
  // caller, including all build worker processes. No 15s build deadline.
  @async.with_task_group(group => {
    let task = group.spawn(no_wait=true, () => {
      let result = Ok(
        prepare(arguments, (category, text) => {
          inbox.put(BuildOutput(category, text))
        }),
      ) catch {
        error => {
          if @async.is_cancellation_error(error) {
            raise error
          }
          Err(launch_error_message(error))
        }
      }
      inbox.put(Prepared(result))
    })
    defer task.cancel()
    let outcome = try {
      for ;; {
        match inbox.get() {
          BuildOutput(category, text) =>
            send_client(
              writer,
              client.event("output", { "category": category, "output": text }),
            )
          Prepared(Ok(args)) => break Some(args)
          Prepared(Err(message)) | Failed(message) => raise LiveError(message)
          Client(None) => {
            client.closed = true
            break None
          }
          Client(Some(text)) => {
            let (seq, command, _) = client.read_request(@json.parse(text))
            if command == "disconnect" {
              task.cancel()
              // Do not claim disconnection before the owned build has stopped.
              task.wait() catch {
                _ => ()
              }
              send_client(
                writer,
                client.response(
                  launch_seq,
                  "launch",
                  error=Some("Launch cancelled during preparation"),
                ),
              )
              send_client(writer, client.response(seq, command))
              send_client(writer, client.event("terminated", {}))
              client.closed = true
              break None
            }
            send_client(
              writer,
              client.response(
                seq,
                command,
                error=Some(
                  "Launch preparation is in progress; wait for initialized",
                ),
              ),
            )
          }
          _ => raise LiveError("Unexpected event during launch preparation")
        }
      }
    } catch {
      error => {
        if @async.is_cancellation_error(error) {
          raise error
        }
        let message = launch_error_message(error)
        send_client(
          writer,
          client.event("output", {
            "category": "stderr",
            "output": "moondbg: \{message}\n",
          }),
        )
        send_client(
          writer,
          client.response(launch_seq, "launch", error=Some(message)),
        )
        send_client(writer, client.event("terminated", {}))
        None
      }
    }
    outcome
  })
}
