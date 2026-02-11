// Container lifecycle management

///|
/// Start a container based on the image configuration
pub async fn ContainerImage::start(
  self : ContainerImage,
) -> Result[Container, TestContainerError] noraise {
  // Build docker run command arguments
  let args : Array[String] = ["run", "-d"]

  // Add port mappings (-P for random host ports)
  if self.exposed_ports.length() > 0 {
    args.push("-P")
  }

  // Add volume mounts
  for i = 0; i < self.volumes.length(); i = i + 1 {
    let volume = self.volumes[i]
    args.push("-v")
    if volume.read_only {
      args.push("\{volume.host_path}:\{volume.container_path}:ro")
    } else {
      args.push("\{volume.host_path}:\{volume.container_path}")
    }
  }

  // Add environment variables
  for i = 0; i < self.env_vars.length(); i = i + 1 {
    let (key, value) = self.env_vars[i]
    args.push("-e")
    args.push("\{key}=\{value}")
  }

  // Add image name and tag
  args.push("\{self.name}:\{self.tag}")

  // Add command if specified
  for i = 0; i < self.cmd.length(); i = i + 1 {
    args.push(self.cmd[i])
  }
  let exec_result : Result[String, TestContainerError] = exec_docker(args)
  let container_id = match exec_result {
    Err(e) =>
      return Err(
        DockerCommandFailed(
          "Failed to start container for image \{self.name}:\n\{e.to_string()}",
        ),
      )
    Ok(output) => {
      // Extract last non-empty line (container ID)
      // docker run -d may output multiple lines including pull progress
      let lines = output.split("\n").to_array()
      let mut last_line = ""
      for i = lines.length() - 1; i >= 0; i = i - 1 {
        let line_view = lines[i].trim()
        let line = "\{line_view}"
        if line.length() > 0 {
          last_line = line
          break
        }
      }
      last_line
    }
  }

  let container = { id: container_id, image: self, port_mappings: [] }
  guard container.update_port_mappings() is Ok(_) else {
    return Err(
      DockerCommandFailed(
        "Failed to get port mappings for container \{container_id}",
      ),
    )
  }
  println(
    "Started container \{container_id} for image \{self.name}:\{self.tag}",
  )
  guard self.wait_strategy is Some(strategy) else { return Ok(container) }
  match wait_for_container(container, strategy, self.wait_timeout) {
    Ok(_) => ()
    Err(wait_error) => {
      let _ = container.cleanup() catch {
        _ => {
          println(
            "Warning: Failed to cleanup container \{container_id} after wait failure",
          )
          return Err(wait_error)
        }
      }
      return Err(wait_error)
    }
  }
  Ok(container)
}

///|
/// Update port mappings by querying Docker
async fn Container::update_port_mappings(
  self : Container,
) -> Result[Unit, TestContainerError] noraise {
  if self.image.exposed_ports.length() == 0 {
    return Ok(())
  }

  // Get port mappings using docker port command
  for i = 0; i < self.image.exposed_ports.length(); i = i + 1 {
    let container_port = self.image.exposed_ports[i]
    let args = ["port", self.id, container_port.to_string()]

    // Retry logic for temporary port mapping errors
    let max_retries = 5
    let mut attempt = 0
    let mut last_error : TestContainerError? = None
    let mut success = false
    while attempt < max_retries && not(success) {
      attempt = attempt + 1
      match exec_docker(args) {
        Ok(output) =>
          // Parse output like "0.0.0.0:32768"
          // Format: [host]:port or 0.0.0.0:port
          match parse_port_mapping(output) {
            Some(host_port) => {
              self.port_mappings.push((container_port, host_port))
              success = true
            }
            None =>
              last_error = Some(
                PortMappingFailed("Failed to parse port mapping: \{output}"),
              )
          }
        Err(e) => {
          // Check if this is a temporary error (404 or not found)
          let error_msg = e.to_string()
          let is_temporary = error_msg.contains("404") ||
            error_msg.contains("not found")
          if is_temporary && attempt < max_retries {
            // Retry after 1 second
            println(
              "Warning: Port mapping failed (attempt \{attempt}/\{max_retries}): \{error_msg}",
            )
            @async.sleep(1000) catch { // 1 second
              _ =>
                return Err(
                  DockerCommandFailed("Sleep failed during port mapping retry"),
                )
            } // 1 second in nanoseconds
            last_error = Some(e)
          } else {
            // Permanent error or max retries reached
            return Err(e)
          }
        }
      }
    }

    // If we exhausted retries without success, return the last error
    if not(success) {
      match last_error {
        Some(e) => return Err(e)
        None =>
          return Err(
            PortMappingFailed(
              "Failed to get port mapping after \{max_retries} retries",
            ),
          )
      }
    }
  }
  Ok(())
}

///|
/// Get the host port mapped to a container port
pub fn Container::get_host_port(self : Container, container_port : Int) -> Int? {
  for i = 0; i < self.port_mappings.length(); i = i + 1 {
    let (cport, hport) = self.port_mappings[i]
    if cport == container_port {
      return Some(hport)
    }
  }
  None
}

///|
/// Get the container ID
pub fn Container::get_id(self : Container) -> String {
  self.id
}

///|
/// Stop the container
pub async fn Container::stop(
  self : Container,
) -> Result[Unit, TestContainerError] {
  let args = ["stop", self.id]
  exec_docker(args).map(_ => ())
}

///|
/// Remove the container
pub async fn Container::remove(
  self : Container,
) -> Result[Unit, TestContainerError] {
  let args = ["rm", self.id]
  exec_docker(args).map(_ => ())
}

///|
/// Stop and remove the container (cleanup)
pub async fn Container::cleanup(
  self : Container,
) -> Result[Unit, TestContainerError] {
  // Try to stop first, then remove
  // Ignore errors from stop (container might already be stopped)
  let _ = self.stop()
  self.remove()
}
