///|
extern "C" fn start_build_group() -> Int = "moondbg_build_group_start"

///|
extern "C" fn cancel_build_group(pid : Int) -> Unit = "moondbg_build_group_cancel"

///|
async fn selected_moon() -> String {
  guard @env.get_env_var("MOON_HOME") is Some(home) && home.has_prefix("/") else {
    raise LaunchError("MOON_HOME must be an absolute toolchain directory")
  }
  for tool in ["moon", "moonc"] {
    validate_executable("\{home}/bin/\{tool}") |> ignore
  }
  "\{home}/bin/moon"
}

///|
/// Private executable entry point. No protocol, readline or shell is involved.
/// The parent owns this worker and its process group for the entire build.
pub async fn run_worker(arguments : Array[String]) -> Int {
  guard arguments is ["check" | "run", ..] else {
    raise LaunchError("Invalid private build worker arguments")
  }
  guard start_build_group() == 0 else {
    raise LaunchError(
      "Unable to isolate build processes (package builds require POSIX)",
    )
  }
  @process.run(selected_moon(), arguments, inherit_env=true)
}

///|
// Keep an incomplete trailing UTF-8 codepoint for the next read.
fn utf8_complete_prefix(bytes : Bytes) -> Int {
  guard bytes.length() > 0 else { return 0 }
  let start = for i = bytes.length() - 1; i > 0 &&
                 (bytes[i].to_int() & 0xc0) == 0x80; {
    continue i - 1
  } nobreak {
    i
  }
  let lead = bytes[start].to_int()
  let width = if lead >= 0xf0 && lead <= 0xf4 {
    4
  } else if lead >= 0xe0 && lead <= 0xef {
    3
  } else if lead >= 0xc2 && lead <= 0xdf {
    2
  } else {
    1
  }
  if bytes.length() - start < width {
    start
  } else {
    bytes.length()
  }
}

///|
async fn stream_build_output(
  reader : &@io.Reader,
  category : String,
  output : async (String, String) -> Unit,
  capture? : @buffer.Buffer,
) -> Unit {
  let pending = @buffer.Buffer()
  while reader.read_some(max_len=8192) is Some(chunk) {
    if capture is Some(capture) {
      guard capture.length() + chunk.length() <= 16777216 else {
        raise LaunchError("moon stdout exceeded the 16 MiB build-output limit")
      }
      capture.write_bytes(chunk)
    }
    pending.write_bytes(chunk)
    let bytes = pending.to_bytes()
    let end = utf8_complete_prefix(bytes)
    if end > 0 {
      output(category, @utf8.decode_lossy(bytes[:end]))
    }
    pending.reset()
    pending.write_bytes(bytes[end:])
  }
  if !pending.is_empty() {
    output(category, @utf8.decode_lossy(pending.to_bytes()))
  }
}

///|
async fn run_moon(
  project : String,
  arguments : Array[String],
  output~ : async (String, String) -> Unit,
  isolated? : Bool = true,
) -> String {
  let moon = selected_moon()
  guard @env.args() is [entry, ..] else {
    raise LaunchError("Missing executable entry")
  }
  let worker = if @fs.exists(entry) { @fs.realpath(entry) } else { entry }
  output("console", "moondbg: moon \{arguments[0]} (native debug)\n")
  @async.with_task_group(group => {
    let (stdout, out) = @process.read_from_process()
    defer stdout.close()
    let (stderr, err) = @process.read_from_process()
    defer stderr.close()
    let input = @process.redirect_from_file("/dev/null")
    let process = @process.spawn(
      group,
      if isolated {
        worker
      } else {
        moon
      },
      if isolated {
        ["--build-worker", ..arguments]
      } else {
        arguments
      },
      cwd=project,
      inherit_env=true,
      stdin=input,
      stdout=out,
      stderr=err,
      cancel_handler=if isolated {
        @process.CancellationHandler(pid => cancel_build_group(pid))
      } else {
        @process.hard_cancel()
      },
      no_wait=true,
    )
    let captured = @buffer.Buffer()
    let out_task = group.spawn(() => {
      stream_build_output(stdout, "stdout", output, capture=captured)
    })
    let err_task = group.spawn(() => {
      stream_build_output(stderr, "stderr", output)
    })
    let status = process.wait()
    out_task.wait()
    err_task.wait()
    guard status == 0 else {
      raise LaunchError("moon \{arguments[0]} failed (exit status \{status})")
    }
    @utf8.decode(captured.to_bytes())
  })
}
