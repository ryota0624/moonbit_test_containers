// Testcontainers for MoonBit
// Type definitions for container management

///|
/// Wait strategy for container readiness
pub enum WaitStrategy {
  TcpPort(Int) // Wait for TCP port to be open
  Seconds(Int) // Wait for a fixed number of seconds
  HttpGet(String, Int) // Wait for HTTP endpoint (path, expected_status_code)
  LogMessage(String) // Wait for a specific message in container logs
} derive(Show, Eq)

///|
/// Error type for testcontainers operations
pub enum TestContainerError {
  DockerCommandFailed(String)
  ContainerNotFound(String)
  PortMappingFailed(String)
  InvalidConfiguration(String)
  WaitStrategyTimeout(String)
} derive(Show, Eq)

///|
/// Volume mount configuration
pub struct VolumeMount {
  host_path : String // Host filesystem path
  container_path : String // Container filesystem path
  read_only : Bool // Mount as read-only (default: false)
}

///|
/// Log options for container logs
pub struct LogOptions {
  follow : Bool // -f: follow log output (stream mode)
  timestamps : Bool // -t: show timestamps
  tail : Int? // --tail N: show last N lines
  since : String? // --since: show logs since timestamp
  until : String? // --until: show logs until timestamp
}

///|
/// Create default LogOptions
pub fn LogOptions::default() -> LogOptions {
  { follow: false, timestamps: false, tail: None, since: None, until: None }
}

///|
/// Set follow option
pub fn LogOptions::with_follow(self : LogOptions, follow : Bool) -> LogOptions {
  { ..self, follow, }
}

///|
/// Set timestamps option
pub fn LogOptions::with_timestamps(
  self : LogOptions,
  timestamps : Bool,
) -> LogOptions {
  { ..self, timestamps, }
}

///|
/// Set tail option
pub fn LogOptions::with_tail(self : LogOptions, lines : Int) -> LogOptions {
  { ..self, tail: Some(lines) }
}

///|
/// Set since option
pub fn LogOptions::with_since(
  self : LogOptions,
  timestamp : String,
) -> LogOptions {
  { ..self, since: Some(timestamp) }
}

///|
/// Set until option
pub fn LogOptions::with_until(
  self : LogOptions,
  timestamp : String,
) -> LogOptions {
  { ..self, until: Some(timestamp) }
}

///|
/// Container image configuration
pub struct ContainerImage {
  name : String
  tag : String
  exposed_ports : Array[Int]
  env_vars : Array[(String, String)]
  cmd : Array[String]
  wait_strategy : WaitStrategy?
  wait_timeout : Int // seconds, default 60
  volumes : Array[VolumeMount] // volume mounts
}

///|
/// Running container instance
pub struct Container {
  id : String
  image : ContainerImage
  port_mappings : Array[(Int, Int)] // (container_port, host_port)
}

///|
/// Create a new container image configuration
pub fn ContainerImage::new(name : String, tag : String) -> ContainerImage {
  {
    name,
    tag,
    exposed_ports: [],
    env_vars: [],
    cmd: [],
    wait_strategy: None,
    wait_timeout: 60,
    volumes: [],
  }
}

///|
/// Add an exposed port to the container configuration
pub fn ContainerImage::with_exposed_port(
  self : ContainerImage,
  port : Int,
) -> ContainerImage {
  let ports = self.exposed_ports.copy()
  ports.push(port)
  { ..self, exposed_ports: ports }
}

///|
/// Add an environment variable to the container configuration
pub fn ContainerImage::with_env_var(
  self : ContainerImage,
  key : String,
  value : String,
) -> ContainerImage {
  let vars = self.env_vars.copy()
  vars.push((key, value))
  { ..self, env_vars: vars }
}

///|
/// Set the command to run in the container
pub fn ContainerImage::with_cmd(
  self : ContainerImage,
  cmd : Array[String],
) -> ContainerImage {
  { ..self, cmd, }
}

///|
/// Set the wait strategy for container readiness
pub fn ContainerImage::with_wait_for(
  self : ContainerImage,
  strategy : WaitStrategy,
) -> ContainerImage {
  { ..self, wait_strategy: Some(strategy) }
}

///|
/// Set the wait timeout in seconds (default: 60)
pub fn ContainerImage::with_wait_timeout(
  self : ContainerImage,
  timeout : Int,
) -> ContainerImage {
  { ..self, wait_timeout: timeout }
}

///|
/// Add a volume mount to the container configuration
pub fn ContainerImage::with_volume(
  self : ContainerImage,
  host_path : String,
  container_path : String,
) -> ContainerImage {
  let volumes = self.volumes.copy()
  volumes.push({ host_path, container_path, read_only: false })
  { ..self, volumes, }
}

///|
/// Add a read-only volume mount to the container configuration
pub fn ContainerImage::with_volume_ro(
  self : ContainerImage,
  host_path : String,
  container_path : String,
) -> ContainerImage {
  let volumes = self.volumes.copy()
  volumes.push({ host_path, container_path, read_only: true })
  { ..self, volumes, }
}
