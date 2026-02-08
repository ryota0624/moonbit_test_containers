// Container lifecycle management

///|
/// Start a container based on the image configuration
pub async fn ContainerImage::start(
  self : ContainerImage,
) -> Result[Container, TestContainerError] {
  // Build docker run command arguments
  let args : Array[String] = ["run", "-d"]

  // Add port mappings (-P for random host ports)
  if self.exposed_ports.length() > 0 {
    args.push("-P")
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

  // Execute docker run
  match exec_docker(args) {
    Ok(container_id) => {
      let container = { id: container_id, image: self, port_mappings: [] }
      // Get port mappings if ports were exposed
      match container.update_port_mappings() {
        Ok(_) =>
          // Execute wait strategy if specified
          match self.wait_strategy {
            Some(strategy) =>
              match wait_for_container(container, strategy, self.wait_timeout) {
                Ok(_) => Ok(container)
                Err(e) => {
                  // Cleanup container on wait failure
                  let _ = container.cleanup()
                  Err(e)
                }
              }
            None => Ok(container)
          }
        Err(e) => Err(e)
      }
    }
    Err(e) => Err(e)
  }
}

///|
/// Update port mappings by querying Docker
async fn Container::update_port_mappings(
  self : Container,
) -> Result[Unit, TestContainerError] {
  if self.image.exposed_ports.length() == 0 {
    return Ok(())
  }

  // Get port mappings using docker port command
  for i = 0; i < self.image.exposed_ports.length(); i = i + 1 {
    let container_port = self.image.exposed_ports[i]
    let args = ["port", self.id, container_port.to_string()]
    match exec_docker(args) {
      Ok(output) =>
        // Parse output like "0.0.0.0:32768"
        // Format: [host]:port or 0.0.0.0:port
        match parse_port_mapping(output) {
          Some(host_port) =>
            self.port_mappings.push((container_port, host_port))
          None =>
            return Err(
              PortMappingFailed("Failed to parse port mapping: \{output}"),
            )
        }
      Err(e) => return Err(e)
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
  match exec_docker(args) {
    Ok(_) => Ok(())
    Err(e) => Err(e)
  }
}

///|
/// Remove the container
pub async fn Container::remove(
  self : Container,
) -> Result[Unit, TestContainerError] {
  let args = ["rm", self.id]
  match exec_docker(args) {
    Ok(_) => Ok(())
    Err(e) => Err(e)
  }
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
