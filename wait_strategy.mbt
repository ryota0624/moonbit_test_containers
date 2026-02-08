// Wait strategies for container readiness

///|
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

///|
/// Check if an HTTP endpoint returns the expected status code
async fn check_http_endpoint(
  host : String,
  port : Int,
  path : String,
  expected_status : Int,
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

///|
/// Wait for TCP port to be open with timeout
async fn wait_for_tcp_port(
  host : String,
  port : Int,
  timeout_seconds : Int,
) -> Result[Unit, TestContainerError] noraise{
  // Poll every 500ms
  let poll_interval_ms = 500
  let max_attempts = timeout_seconds * 1000 / poll_interval_ms
  for attempt = 0; attempt < max_attempts; attempt = attempt + 1 {
    let port_check = check_tcp_port(host, port) catch {
      _ => false
    } 
    if port_check {
      return Ok(())
    }

    // Sleep between attempts using async sleep
    let sleep_ns = poll_interval_ms * 1000000 // Convert ms to nanoseconds
    @async.sleep(sleep_ns) catch {
      _ => {
        // Ignore sleep errors
        return Err(
          DockerCommandFailed("Sleep failed during wait"),
        )
      }
    }

  } else {
    Err(
      WaitStrategyTimeout(
        "TCP port \{port} not ready after \{timeout_seconds} seconds",
      ),
    )
  }
}

///|
/// Wait for HTTP endpoint to return expected status code with timeout
async fn wait_for_http_endpoint(
  host : String,
  port : Int,
  path : String,
  expected_status : Int,
  timeout_seconds : Int,
) -> Result[Unit, TestContainerError] noraise {
  // Poll every 500ms
  let poll_interval_ms = 500
  let max_attempts = timeout_seconds * 1000 / poll_interval_ms
  for attempt = 0; attempt < max_attempts; attempt = attempt + 1 {
    let ready = check_http_endpoint(host, port, path, expected_status) catch {
      _ => false
    }
    if ready {
      return Ok(())
    }

    // Sleep between attempts using async sleep
    let sleep_ns = poll_interval_ms * 1000000 // Convert ms to nanoseconds
    @async.sleep(sleep_ns) catch {
      _ => {
        // Ignore sleep errors
        return Err(
          DockerCommandFailed("Sleep failed during wait"),
        )
      }
    }

  } else {
    Err(
      WaitStrategyTimeout(
        "HTTP endpoint \{path} did not return status \{expected_status} after \{timeout_seconds} seconds",
      ),
    )
  }
}

///|
/// Execute wait strategy for container
async fn wait_for_container(
  container : Container,
  strategy : WaitStrategy,
  timeout : Int,
) -> Result[Unit, TestContainerError] noraise {
  match strategy {
    Seconds(seconds) =>
      // Simple delay using async sleep
      try {
        let sleep_ns = seconds * 1000000000 // Convert seconds to nanoseconds
        @async.sleep(sleep_ns)
        Ok(())
      } catch {
        e => Err(DockerCommandFailed("Sleep failed: \{e.to_string()}"))
      }
    TcpPort(container_port) =>
      // Get the mapped host port
      match container.get_host_port(container_port) {
        Some(host_port) =>
          // Wait for TCP port to be open
          wait_for_tcp_port("localhost", host_port, timeout)
        None =>
          Err(
            InvalidConfiguration(
              "Cannot wait for TCP port \{container_port}: port not mapped",
            ),
          )
      }
    HttpGet(path, expected_status) => {
      // For HttpGet, we need to determine which port to use
      // If there's only one exposed port, use that
      // Otherwise, this is a configuration error
      if container.image.exposed_ports.length() == 0 {
        return Err(
          InvalidConfiguration(
            "Cannot wait for HTTP endpoint: no ports exposed",
          ),
        )
      }

      // Use the first exposed port
      let container_port = container.image.exposed_ports[0]
      match container.get_host_port(container_port) {
        Some(host_port) =>
          // Wait for HTTP endpoint to be ready
          wait_for_http_endpoint(
            "localhost", host_port, path, expected_status, timeout,
          )
        None =>
          Err(
            InvalidConfiguration(
              "Cannot wait for HTTP endpoint: port \{container_port} not mapped",
            ),
          )
      }
    }
  }
}
