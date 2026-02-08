// Container logs management
//
// NOTE (2026-02-08): Error handling in this file has been simplified to work around
// a MoonBit compiler C code generation issue when combining async functions with
// complex catch blocks and closures. This affects native backend only.

///|
/// Build docker logs command arguments from LogOptions
fn build_logs_args(
  container_id : String,
  options : LogOptions,
) -> Array[String] {
  let args : Array[String] = ["logs"]

  // Add follow option
  if options.follow {
    args.push("-f")
  }

  // Add timestamps option
  if options.timestamps {
    args.push("-t")
  }

  // Add tail option
  match options.tail {
    Some(n) => {
      args.push("--tail")
      args.push(n.to_string())
    }
    None => ()
  }

  // Add since option
  match options.since {
    Some(timestamp) => {
      args.push("--since")
      args.push(timestamp)
    }
    None => ()
  }

  // Add until option
  match options.until {
    Some(timestamp) => {
      args.push("--until")
      args.push(timestamp)
    }
    None => ()
  }

  // Add container ID
  args.push(container_id)
  args
}

///|
/// Get all logs from the container
pub async fn Container::get_logs(
  self : Container,
) -> Result[String, TestContainerError] noraise {
  let args = ["logs", self.id]
  exec_docker(args)
}

///|
/// Get logs with specified options
pub async fn Container::get_logs_with_options(
  self : Container,
  options : LogOptions,
) -> Result[String, TestContainerError] {
  // Check if follow option is set
  if options.follow {
    return Err(
      InvalidConfiguration(
        "Cannot use follow option with get_logs_with_options. Use stream_logs instead.",
      ),
    )
  }
  let args = build_logs_args(self.id, options)
  exec_docker(args)
}

///|
/// Stream logs line by line with a callback
/// Note: This implementation collects all output first, then processes it line by line.
/// It does not support true streaming for follow=true mode.
pub async fn Container::stream_logs(
  self : Container,
  callback : (String) -> Unit,
  options? : LogOptions,
) -> Result[Unit, TestContainerError] {
  // Get options or use default
  let options = match options {
    Some(opts) => opts
    None => LogOptions::default()
  }

  // For follow mode, we need to disable it since we collect output first
  // True streaming would require more complex implementation
  let stream_options = { ..options, follow: false }
  let args = build_logs_args(self.id, stream_options)

  // Run docker logs using exec_docker (works on both native and JS backends)
  // NOTE: Simplified to avoid C code generation issue with nested match/catch
  let output_result = exec_docker(args)

  // Early return on error
  let output_text = match output_result {
    Err(e) => return Err(e)
    Ok(text) => text
  }

  // Process output line by line
  let lines = output_text.split("\n").to_array()
  for i = 0; i < lines.length(); i = i + 1 {
    let line = lines[i]
    // Convert StringView to String and call callback
    let line_str = "\{line}"
    if line_str.length() > 0 {
      callback(line_str)
    }
  }
  Ok(())
}
