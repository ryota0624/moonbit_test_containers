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
    e => return Err(DockerCommandFailed(e.to_string()))
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
