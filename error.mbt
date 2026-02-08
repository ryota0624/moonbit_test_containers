// Error handling for testcontainers

///|
/// Convert error to string for display
pub fn TestContainerError::to_string(self : TestContainerError) -> String {
  match self {
    DockerCommandFailed(msg) => "Docker command failed: \{msg}"
    ContainerNotFound(id) => "Container not found: \{id}"
    PortMappingFailed(msg) => "Port mapping failed: \{msg}"
    InvalidConfiguration(msg) => "Invalid configuration: \{msg}"
    WaitStrategyTimeout(msg) => "Wait strategy timeout: \{msg}"
  }
}
