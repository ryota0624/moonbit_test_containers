// Docker CLI execution utilities

///|
/// Execute a Docker CLI command and return the output
async fn exec_docker(
  args : Array[String],
) -> Result[String, TestContainerError] noraise {
  let command = "docker"
  try {
    let (status, output) = @process.collect_output_merged(command, args)
    let output_view = output.text()
    // Convert StringView to String and trim
    let trimmed = output_view.trim()
    let output_str = "\{trimmed}"
    if status == 0 {
      Ok(output_str)
    } else {
      Err(DockerCommandFailed(output_str))
    }
  } catch {
    e => Err(DockerCommandFailed(e.to_string()))
  }
}

///|
/// Parse port mapping output from docker port command
/// Expected format: "0.0.0.0:32768" or "[::]:32768"
fn parse_port_mapping(output : String) -> Int? {
  // Find the last colon and extract the port number after it
  let chars = output.to_array()
  let mut last_colon_idx = -1
  for i = 0; i < chars.length(); i = i + 1 {
    if chars[i] == ':' {
      last_colon_idx = i
    }
  }
  if last_colon_idx == -1 || last_colon_idx == chars.length() - 1 {
    return None
  }

  // Extract port number string
  let port_start = last_colon_idx + 1
  let port_chars : Array[Char] = []
  for i = port_start; i < chars.length(); i = i + 1 {
    port_chars.push(chars[i])
  }
  let port_str = String::from_array(port_chars)
  Some(

    // Parse to integer
    @strconv.parse_int(port_str),
  ) catch {
    _ => None
  }
}
