///|
async fn send_client(writer : &@io.Writer, message : Json) -> Unit {
  writer.write(@dap.frame_message(message.stringify()))
}

///|
async fn serve_live(
  inbox : @async.Queue[LiveInput],
  writer : &@io.Writer,
  client : ConnectionSession,
  launch_seq : Int,
  prepared : PreparedLaunch,
) -> Unit {
  @async.with_task_group(group => {
    let transport = @dap.open_transport(group, find_adapter()) catch {
      error => {
        send_client(
          writer,
          client.response(
            launch_seq,
            "launch",
            error=Some(@debug.to_string(error)),
          ),
        )
        send_client(writer, client.event("terminated", {}))
        return
      }
    }
    defer transport.close()
    let session : LiveSession = {
      client,
      transport,
      launch_seq,
      launch_answered: false,
      pending: {},
      next_seq: 1,
      configured: false,
      ready: false,
      stopped: false,
      execution_revision: 0,
      pause_revision: None,
      exited: false,
      ended: false,
      closing: false,
      deadline: Some(@async.now() + 15000),
      inspection: InspectionState::new(),
      capabilities: {},
      functions: FunctionState::new(prepared.context),
    }
    defer session.inspection.jobs.close()
    let inspection_task = group.spawn(no_wait=true, () => {
      session.inspect_worker(inbox)
    })
    defer inspection_task.cancel()
    defer session.functions.jobs.close()
    let function_task = group.spawn(no_wait=true, () => {
      session.function_worker(inbox)
    })
    defer function_task.cancel()
    let adapter_task = group.spawn(no_wait=true, () => {
      try {
        for ;; {
          inbox.put(Adapter(transport.receive_message()))
        }
      } catch {
        error =>
          if !@async.is_cancellation_error(error) {
            inbox.put(Failed(@debug.to_string(error))) catch {
              _ => ()
            }
          }
      }
    })
    defer adapter_task.cancel()
    // One writer per direction, one reader per direction. The inbox is the
    // sole state owner: no concurrent RunOutcome reader can steal responses.
    try {
      session.request(0, "initialize", {
        "adapterID": "lldb",
        "clientID": "moondbg",
        "clientName": "moondbg",
        "linesStartAt1": true,
        "columnsStartAt1": true,
        "pathFormat": "path",
        "supportsRunInTerminalRequest": false,
      })
      while !client.closed {
        let deadline = session.pending
          .values()
          .fold(init=session.deadline, (acc, request) => {
            Some(
              match acc {
                Some(end) => end.min(request.deadline)
                None => request.deadline
              },
            )
          })
        let received = match deadline {
          Some(end) =>
            @async.with_timeout_opt((end - @async.now()).to_int().max(1), () => {
              inbox.get()
            })
          None => Some(inbox.get())
        }
        guard received is Some(input) else {
          if session.ended && !session.closing {
            break
          }
          raise LiveError("lldb-dap request or configuration timed out.")
        }
        match input {
          Prepared(_) | BuildOutput(_, _) =>
            raise LiveError("Unexpected late build event")
          Client(Some(text)) => session.on_client(writer, @json.parse(text))
          Client(None) => break
          Adapter(message) =>
            session.on_adapter(writer, message, launch_seq, prepared.arguments)
          Failed(message) => {
            if session.ended {
              break
            }
            raise LiveError(message)
          }
          InspectRead(epoch, command, args, reply) =>
            if session.inspection_epoch() == Some(epoch) {
              session.request(0, command, args, inspection_reply=Some(reply))
            } else {
              reply.close(
                error=LiveError("Variable request belongs to a stale stop"),
              )
            }
          InspectDone(seq, result) =>
            session.complete_inspection(writer, seq, result)
          FunctionRead(command, args, reply) =>
            if session.closing || session.ended {
              reply.close(
                error=LiveError(
                  "Session ended during function breakpoint update",
                ),
              )
            } else {
              session.request(0, command, args, function_reply=Some(reply))
            }
          FunctionDone(result) => session.complete_functions(writer, result)
        }
      }
    } catch {
      error => {
        session.cancel_functions(writer, @debug.to_string(error)) catch {
          _ => ()
        }
        session.invalidate_inspection(writer) catch {
          _ => ()
        }
        session.cancel_launch(writer, @debug.to_string(error)) catch {
          _ => ()
        }
        for request in session.pending.values() {
          guard request.client_seq > 0 && request.command != "launch" else {
            continue
          }
          send_client(
            writer,
            client.response(
              request.client_seq,
              request.command,
              error=Some(@debug.to_string(error)),
            ),
          ) catch {
            _ => ()
          }
        }
        send_client(
          writer,
          client.event("output", {
            "category": "stderr",
            "output": "moondbg: \{@debug.to_string(error)}\n",
          }),
        ) catch {
          _ => ()
        }
      }
    }
    // EOF and error also own shutdown. Keep the adapter reader draining while
    // requesting target termination; only then close/cancel its process.
    if !client.closed {
      (@async.with_timeout_opt(3000, () => {
        session.request(0, "disconnect", { "terminateDebuggee": true })
        for ;; {
          match inbox.get() {
            Adapter(
              {
                "type": String("response"),
                "command": String("disconnect"),
                ..
              }
            ) => break
            Failed(_) => break
            _ => ()
          }
        }
      }) catch {
        _ => None
      })
      |> ignore
    }
    if session.finish() is Some(event) {
      send_client(writer, event) catch {
        _ => ()
      }
    }
  })
}
