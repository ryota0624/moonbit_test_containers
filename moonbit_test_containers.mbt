// Testcontainers for MoonBit
// A library for creating and managing Docker containers for integration testing

/// Wait strategy for container readiness
pub enum WaitStrategy {
  TcpPort(Int)  // Wait for TCP port to be open
  Seconds(Int)  // Wait for a fixed number of seconds
  HttpGet(String, Int)  // Wait for HTTP endpoint (path, expected_status_code)
} derive(Show, Eq)

/// Error type for testcontainers operations
pub enum TestContainerError {
  DockerCommandFailed(String)
  ContainerNotFound(String)
  PortMappingFailed(String)
  InvalidConfiguration(String)
  WaitStrategyTimeout(String)
} derive(Show, Eq)

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

///|
/// Log options for container logs
pub struct LogOptions {
  follow : Bool           // -f: follow log output (stream mode)
  timestamps : Bool       // -t: show timestamps
  tail : Option[Int]      // --tail N: show last N lines
  since : Option[String]  // --since: show logs since timestamp
  until : Option[String]  // --until: show logs until timestamp
}

/// Create default LogOptions
pub fn LogOptions::default() -> LogOptions {
  {
    follow: false,
    timestamps: false,
    tail: None,
    since: None,
    until: None,
  }
}

/// Set follow option
pub fn LogOptions::with_follow(self : LogOptions, follow : Bool) -> LogOptions {
  { ..self, follow }
}

/// Set timestamps option
pub fn LogOptions::with_timestamps(self : LogOptions, timestamps : Bool) -> LogOptions {
  { ..self, timestamps }
}

/// Set tail option
pub fn LogOptions::with_tail(self : LogOptions, lines : Int) -> LogOptions {
  { ..self, tail: Some(lines) }
}

/// Set since option
pub fn LogOptions::with_since(self : LogOptions, timestamp : String) -> LogOptions {
  { ..self, since: Some(timestamp) }
}

/// Set until option
pub fn LogOptions::with_until(self : LogOptions, timestamp : String) -> LogOptions {
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
  wait_strategy : Option[WaitStrategy]
  wait_timeout : Int  // seconds, default 60
}

/// Running container instance
pub struct Container {
  id : String
  image : ContainerImage
  port_mappings : Array[(Int, Int)] // (container_port, host_port)
}

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
  }
}

/// Add an exposed port to the container configuration
pub fn ContainerImage::with_exposed_port(self : ContainerImage, port : Int) -> ContainerImage {
  let ports = self.exposed_ports.copy()
  ports.push(port)
  { ..self, exposed_ports: ports }
}

/// Add an environment variable to the container configuration
pub fn ContainerImage::with_env_var(
  self : ContainerImage,
  key : String,
  value : String
) -> ContainerImage {
  let vars = self.env_vars.copy()
  vars.push((key, value))
  { ..self, env_vars: vars }
}

/// Set the command to run in the container
pub fn ContainerImage::with_cmd(self : ContainerImage, cmd : Array[String]) -> ContainerImage {
  { ..self, cmd }
}

/// Set the wait strategy for container readiness
pub fn ContainerImage::with_wait_for(
  self : ContainerImage,
  strategy : WaitStrategy
) -> ContainerImage {
  { ..self, wait_strategy: Some(strategy) }
}

/// Set the wait timeout in seconds (default: 60)
pub fn ContainerImage::with_wait_timeout(
  self : ContainerImage,
  timeout : Int
) -> ContainerImage {
  { ..self, wait_timeout: timeout }
}

///|
/// Execute a Docker CLI command and return the output
async fn exec_docker(args : Array[String]) -> Result[String, TestContainerError] {
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

/// Check if a TCP port is open using netcat
async fn check_tcp_port(host : String, port : Int) -> Bool {
  // Use nc (netcat) to check if port is open
  // nc -z returns 0 if connection succeeds
  let command = "nc"
  let args = ["-z", "-w", "1", host, port.to_string()]

  try {
    let (status, _) = @process.collect_output_merged(command, args)
    status == 0
  } catch {
    _ => false
  }
}

/// Check if an HTTP endpoint returns the expected status code
async fn check_http_endpoint(
  host : String,
  port : Int,
  path : String,
  expected_status : Int
) -> Bool {
  // Construct URL
  let url = "http://\{host}:\{port}\{path}"

  try {
    // Send GET request and get response
    let (response, body) = @http.get_stream(url)
    defer body.close()

    // Check if status code matches
    response.code == expected_status
  } catch {
    // Any error (connection refused, timeout, etc.) means not ready
    _ => false
  }
}

/// Wait for TCP port to be open with timeout
async fn wait_for_tcp_port(
  host : String,
  port : Int,
  timeout_seconds : Int
) -> Result[Unit, TestContainerError] {
  // Poll every 500ms
  let poll_interval_ms = 500
  let max_attempts = (timeout_seconds * 1000) / poll_interval_ms

  for attempt = 0; attempt < max_attempts; attempt = attempt + 1 {
    if check_tcp_port(host, port) {
      return Ok(())
    }

    // Sleep between attempts
    // Using a simple busy-wait for now - will improve with proper async sleep
    let sleep_ms = poll_interval_ms
    let _ = @process.collect_output_merged("sleep", ["0.\{sleep_ms / 1000}"])
  } else {
    Err(WaitStrategyTimeout(
      "TCP port \{port} not ready after \{timeout_seconds} seconds"
    ))
  }
}

/// Wait for HTTP endpoint to return expected status code with timeout
async fn wait_for_http_endpoint(
  host : String,
  port : Int,
  path : String,
  expected_status : Int,
  timeout_seconds : Int
) -> Result[Unit, TestContainerError] {
  // Poll every 500ms
  let poll_interval_ms = 500
  let max_attempts = (timeout_seconds * 1000) / poll_interval_ms

  for attempt = 0; attempt < max_attempts; attempt = attempt + 1 {
    if check_http_endpoint(host, port, path, expected_status) {
      return Ok(())
    }

    // Sleep between attempts
    let sleep_ms = poll_interval_ms
    let _ = @process.collect_output_merged("sleep", ["0.\{sleep_ms / 1000}"])
  } else {
    Err(WaitStrategyTimeout(
      "HTTP endpoint \{path} did not return status \{expected_status} after \{timeout_seconds} seconds"
    ))
  }
}

/// Execute wait strategy for container
async fn wait_for_container(
  container : Container,
  strategy : WaitStrategy,
  timeout : Int
) -> Result[Unit, TestContainerError] {
  match strategy {
    Seconds(seconds) => {
      // Simple delay using sleep command
      try {
        let _ = @process.collect_output_merged("sleep", [seconds.to_string()])
        Ok(())
      } catch {
        e => Err(DockerCommandFailed("Sleep failed: \{e.to_string()}"))
      }
    }
    TcpPort(container_port) => {
      // Get the mapped host port
      match container.get_host_port(container_port) {
        Some(host_port) => {
          // Wait for TCP port to be open
          wait_for_tcp_port("localhost", host_port, timeout)
        }
        None => {
          Err(InvalidConfiguration(
            "Cannot wait for TCP port \{container_port}: port not mapped"
          ))
        }
      }
    }
    HttpGet(path, expected_status) => {
      // For HttpGet, we need to determine which port to use
      // If there's only one exposed port, use that
      // Otherwise, this is a configuration error
      if container.image.exposed_ports.length() == 0 {
        return Err(InvalidConfiguration(
          "Cannot wait for HTTP endpoint: no ports exposed"
        ))
      }

      // Use the first exposed port
      let container_port = container.image.exposed_ports[0]

      match container.get_host_port(container_port) {
        Some(host_port) => {
          // Wait for HTTP endpoint to be ready
          wait_for_http_endpoint("localhost", host_port, path, expected_status, timeout)
        }
        None => {
          Err(InvalidConfiguration(
            "Cannot wait for HTTP endpoint: port \{container_port} not mapped"
          ))
        }
      }
    }
  }
}

///|
/// Build docker logs command arguments from LogOptions
fn build_logs_args(container_id : String, options : LogOptions) -> Array[String] {
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

/// Get all logs from the container
pub async fn Container::get_logs(
  self : Container
) -> Result[String, TestContainerError] {
  let args = ["logs", self.id]
  exec_docker(args)
}

/// Get logs with specified options
pub async fn Container::get_logs_with_options(
  self : Container,
  options : LogOptions
) -> Result[String, TestContainerError] {
  // Check if follow option is set
  if options.follow {
    return Err(InvalidConfiguration(
      "Cannot use follow option with get_logs_with_options. Use stream_logs instead."
    ))
  }

  let args = build_logs_args(self.id, options)
  exec_docker(args)
}

/// Read logs line by line from a process output
async fn read_logs_line_by_line(
  reader : @process.ReadFromProcess,
  callback : (String) -> Unit
) -> Result[Unit, TestContainerError] {
  try {
    loop {
      match reader.read_line() {
        Ok(line) => {
          // Convert StringView to String
          let line_str = "\{line}"
          callback(line_str)
        }
        Err(@io.EOF) => break
        Err(e) => return Err(DockerCommandFailed("Failed to read log line: \{e}"))
      }
    }
    Ok(())
  } catch {
    e => Err(DockerCommandFailed("Log streaming error: \{e.to_string()}"))
  }
}

/// Stream logs line by line with a callback
pub async fn Container::stream_logs(
  self : Container,
  callback : (String) -> Unit,
  options : LogOptions = LogOptions::default()
) -> Result[Unit, TestContainerError] {
  // Build arguments with follow enabled
  let stream_options = { ..options, follow: true }
  let args = build_logs_args(self.id, stream_options)

  try {
    // Create a pipe for reading process output
    let (reader, writer) = @process.read_from_process()

    // Start docker logs process with stdout redirected to pipe
    let exit_code = @process.run("docker", args, stdout=writer)

    // Read logs line by line
    match read_logs_line_by_line(reader, callback) {
      Ok(_) => {
        // Check exit code
        if exit_code == 0 {
          Ok(())
        } else {
          Err(DockerCommandFailed("Docker logs exited with code \{exit_code}"))
        }
      }
      Err(e) => Err(e)
    }
  } catch {
    e => Err(DockerCommandFailed("Failed to stream logs: \{e.to_string()}"))
  }
}

///|
/// Start a container based on the image configuration
pub async fn ContainerImage::start(self : ContainerImage) -> Result[Container, TestContainerError] {
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
      let container = {
        id: container_id,
        image: self,
        port_mappings: [],
      }
      // Get port mappings if ports were exposed
      match container.update_port_mappings() {
        Ok(_) => {
          // Execute wait strategy if specified
          match self.wait_strategy {
            Some(strategy) => {
              match wait_for_container(container, strategy, self.wait_timeout) {
                Ok(_) => Ok(container)
                Err(e) => {
                  // Cleanup container on wait failure
                  let _ = container.cleanup()
                  Err(e)
                }
              }
            }
            None => Ok(container)
          }
        }
        Err(e) => Err(e)
      }
    }
    Err(e) => Err(e)
  }
}

/// Update port mappings by querying Docker
async fn Container::update_port_mappings(self : Container) -> Result[Unit, TestContainerError] {
  if self.image.exposed_ports.length() == 0 {
    return Ok(())
  }

  // Get port mappings using docker port command
  for i = 0; i < self.image.exposed_ports.length(); i = i + 1 {
    let container_port = self.image.exposed_ports[i]
    let args = ["port", self.id, container_port.to_string()]

    match exec_docker(args) {
      Ok(output) => {
        // Parse output like "0.0.0.0:32768"
        // Format: [host]:port or 0.0.0.0:port
        match parse_port_mapping(output) {
          Some(host_port) => {
            self.port_mappings.push((container_port, host_port))
          }
          None => {
            return Err(
              PortMappingFailed("Failed to parse port mapping: \{output}"),
            )
          }
        }
      }
      Err(e) => return Err(e)
    }
  }

  Ok(())
}

/// Parse port mapping output from docker port command
/// Expected format: "0.0.0.0:32768" or "[::]:32768"
fn parse_port_mapping(output : String) -> Option[Int] {
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

  // Parse to integer
  try {
    Some(@strconv.parse_int(port_str))
  } catch {
    _ => None
  }
}

/// Get the host port mapped to a container port
pub fn Container::get_host_port(
  self : Container,
  container_port : Int
) -> Option[Int] {
  for i = 0; i < self.port_mappings.length(); i = i + 1 {
    let (cport, hport) = self.port_mappings[i]
    if cport == container_port {
      return Some(hport)
    }
  }
  None
}

/// Get the container ID
pub fn Container::get_id(self : Container) -> String {
  self.id
}

///|
/// Stop the container
pub async fn Container::stop(self : Container) -> Result[Unit, TestContainerError] {
  let args = ["stop", self.id]
  match exec_docker(args) {
    Ok(_) => Ok(())
    Err(e) => Err(e)
  }
}

/// Remove the container
pub async fn Container::remove(self : Container) -> Result[Unit, TestContainerError] {
  let args = ["rm", self.id]
  match exec_docker(args) {
    Ok(_) => Ok(())
    Err(e) => Err(e)
  }
}

/// Stop and remove the container (cleanup)
pub async fn Container::cleanup(self : Container) -> Result[Unit, TestContainerError] {
  // Try to stop first, then remove
  // Ignore errors from stop (container might already be stopped)
  let _ = self.stop()
  self.remove()
}
