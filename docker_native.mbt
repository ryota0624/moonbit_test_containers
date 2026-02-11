// Docker command executor for native backend
// Uses @process.collect_output_merged

///|
/// Execute docker command using native process execution
#cfg(target="native")
pub async fn exec_docker(
  args : Array[String],
) -> Result[String, TestContainerError] noraise {
  let command = "docker"
  let (status, output) = @process.collect_output_merged(command, args) catch {
    e => {
      let error_msg = e.to_string()
      // Check if error indicates Docker CLI is not installed
      if error_msg.contains("No such file") ||
        error_msg.contains("not found") ||
        error_msg.contains("command not found") {
        return Err(
          DockerCommandFailed(
            "Docker CLI is not installed or not available in PATH.\n\nPlease install Docker to use this library:\n- macOS: https://docs.docker.com/desktop/install/mac-install/\n- Windows: https://docs.docker.com/desktop/install/windows-install/\n- Linux: https://docs.docker.com/desktop/install/linux-install/\n\nAfter installation, make sure 'docker' command is available in your PATH.",
          ),
        )
      }
      return Err(DockerCommandFailed(error_msg))
    }
  }
  let output_view = output.text() catch {
    e => return Err(DockerCommandFailed(e.to_string()))
  }
  // Convert StringView to String and trim
  let trimmed = output_view.trim()
  let output_str = "\{trimmed}"
  if status == 0 {
    Ok(output_str)
  } else {
    Err(DockerCommandFailed(output_str))
  }
}
