// Wait strategies for container readiness
// Common functions used by both native and JavaScript backends
//
// Backend-specific implementations:
// - check_tcp_port: See wait_strategy_native.mbt and wait_strategy_js.mbt
// - check_http_endpoint: See wait_strategy_native.mbt and wait_strategy_js.mbt
//
// NOTE (2026-02-08): Error handling in this file has been simplified to work around
// a MoonBit compiler C code generation issue. Complex catch blocks with closures
// can cause "too many arguments to function" errors in generated C code.
// This affects native backend only; JavaScript backend works correctly.

///|
/// Wait for TCP port to be open with timeout
async fn wait_for_tcp_port(
  host : String,
  port : Int,
  timeout_seconds : Int,
) -> Result[Unit, TestContainerError] noraise {
  // Poll every 500ms
  // NOTE: Simplified error handling to work around C code generation issue
  let poll_interval_ms = 500
  let max_attempts = timeout_seconds * 1000 / poll_interval_ms
  for attempt = 0; attempt < max_attempts; attempt = attempt + 1 {
    // Check port - ignore errors and treat as not ready
    let port_ready = check_tcp_port(host, port) catch { _ => false }
    if port_ready {
      return Ok(())
    }

    // Sleep between attempts - ignore sleep errors
    @async.sleep(poll_interval_ms) catch {
      _ => ()
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
  // NOTE: Simplified error handling to work around C code generation issue
  let poll_interval_ms = 500
  let max_attempts = timeout_seconds * 1000 / poll_interval_ms
  for attempt = 0; attempt < max_attempts; attempt = attempt + 1 {
    // Check endpoint - ignore errors and treat as not ready
    let endpoint_ready = check_http_endpoint(host, port, path, expected_status) catch {
      _ => false
    }
    if endpoint_ready {
      return Ok(())
    }

    // Sleep between attempts - ignore sleep errors
    @async.sleep(poll_interval_ms) catch {
      _ => ()
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
    Seconds(seconds) => {
      // Simple delay using async sleep (milliseconds)
      let sleep_ms = seconds * 1000 // Convert seconds to milliseconds
      @async.sleep(sleep_ms) catch {
        e => return Err(DockerCommandFailed("Sleep failed: \{e.to_string()}"))
      }
      Ok(())
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
