// Integration tests for testcontainers
// Note: These tests require Docker to be installed and running

///|
/// Test basic container lifecycle with Redis
async test "redis container lifecycle" {
  // Create and start a Redis container with wait strategy
  let container = ContainerImage::new("redis", "7.2.4")
    .with_exposed_port(6379)
    .with_env_var("REDIS_PORT", "6379")
    .with_wait_for(WaitStrategy::TcpPort(6379))
    .with_wait_timeout(30)
    .start()

  match container {
    Ok(c) => {
      // Verify container ID is not empty
      let id = c.get_id()
      if id.length() == 0 {
        abort("Container ID is empty")
      }
      println("Redis container started: \{id}")

      // Verify port mapping exists
      match c.get_host_port(6379) {
        Some(host_port) => {
          if host_port <= 0 {
            abort("Invalid host port: \{host_port}")
          }
          println("Redis container running on port: \{host_port}")
        }
        None => abort("Port mapping not found")
      }

      // Cleanup
      match c.cleanup() {
        Ok(_) => println("Container cleaned up successfully")
        Err(e) => {
          println("Cleanup failed: \{e.to_string()}")
          abort("Cleanup failed")
        }
      }
    }
    Err(e) => {
      println("Failed to start container: \{e.to_string()}")
      abort("Container start failed")
    }
  }
}

///|
/// Test container with multiple environment variables
async test "container with env vars" {
  let container = ContainerImage::new("alpine", "3.19")
    .with_env_var("TEST_VAR1", "value1")
    .with_env_var("TEST_VAR2", "value2")
    .with_cmd(["sleep", "5"])
    .start()

  match container {
    Ok(c) => {
      if c.get_id().length() == 0 {
        abort("Container ID is empty")
      }
      println("Alpine container started: \{c.get_id()}")

      // Cleanup
      let _ = c.cleanup()
    }
    Err(e) => {
      println("Failed to start container: \{e.to_string()}")
      abort("Container start failed")
    }
  }
}

///|
/// Test stopping and removing container separately
async test "stop and remove container" {
  let container = ContainerImage::new("alpine", "3.19")
    .with_cmd(["sleep", "10"])
    .start()

  match container {
    Ok(c) => {
      let id = c.get_id()
      println("Container started: \{id}")

      // Stop the container
      match c.stop() {
        Ok(_) => println("Container stopped")
        Err(e) => {
          println("Stop failed: \{e.to_string()}")
          abort("Stop failed")
        }
      }

      // Remove the container
      match c.remove() {
        Ok(_) => println("Container removed")
        Err(e) => {
          println("Remove failed: \{e.to_string()}")
          abort("Remove failed")
        }
      }
    }
    Err(e) => {
      println("Failed to start container: \{e.to_string()}")
      abort("Container start failed")
    }
  }
}

///|
/// Test error handling for invalid image
async test "invalid image error handling" {
  let container = ContainerImage::new("nonexistent-image-xyz", "999.999.999")
    .start()

  match container {
    Ok(_) => abort("Expected error but got success")
    Err(e) => {
      println("Got expected error: \{e.to_string()}")
      // Test passed - we expected an error
    }
  }
}

///|
/// Test TCP port wait strategy
async test "wait strategy tcp port" {
  // Start Redis with TCP port wait
  let container = ContainerImage::new("redis", "7.2.4")
    .with_exposed_port(6379)
    .with_wait_for(WaitStrategy::TcpPort(6379))
    .with_wait_timeout(30)
    .start()

  match container {
    Ok(c) => {
      println("Redis started with TCP port wait strategy")
      println("Container ID: \{c.get_id()}")

      // Verify port is accessible
      match c.get_host_port(6379) {
        Some(port) => {
          println("Redis accessible on port: \{port}")
        }
        None => abort("Port not mapped")
      }

      // Cleanup
      let _ = c.cleanup()
    }
    Err(e) => {
      println("Failed: \{e.to_string()}")
      abort("TCP port wait strategy failed")
    }
  }
}

///|
/// Test simple delay wait strategy
async test "wait strategy seconds" {
  // Start Alpine with simple delay
  let container = ContainerImage::new("alpine", "3.19")
    .with_cmd(["sleep", "10"])
    .with_wait_for(WaitStrategy::Seconds(2))
    .start()

  match container {
    Ok(c) => {
      println("Alpine started with delay wait strategy")
      println("Container ID: \{c.get_id()}")

      // Cleanup
      let _ = c.cleanup()
    }
    Err(e) => {
      println("Failed: \{e.to_string()}")
      abort("Delay wait strategy failed")
    }
  }
}

///|
/// Test HTTP endpoint wait strategy with nginx
async test "wait strategy http get" {
  // Start nginx with HTTP wait strategy
  let container = ContainerImage::new("nginx", "1.25-alpine")
    .with_exposed_port(80)
    .with_wait_for(WaitStrategy::HttpGet("/", 200))
    .with_wait_timeout(30)
    .start()

  match container {
    Ok(c) => {
      println("Nginx started with HTTP wait strategy")
      println("Container ID: \{c.get_id()}")

      // Verify port is accessible
      match c.get_host_port(80) {
        Some(port) => {
          println("Nginx accessible on port: \{port}")
        }
        None => abort("Port not mapped")
      }

      // Cleanup
      match c.cleanup() {
        Ok(_) => println("Nginx container cleaned up successfully")
        Err(e) => {
          println("Cleanup failed: \{e.to_string()}")
          abort("Cleanup failed")
        }
      }
    }
    Err(e) => {
      println("Failed: \{e.to_string()}")
      abort("HTTP wait strategy failed")
    }
  }
}

///|
/// Test HTTP endpoint wait strategy with custom path
async test "wait strategy http get custom path" {
  // Start nginx and wait for a specific path
  // Note: nginx default config serves "/" but may return 404 for other paths
  // We'll test with "/" and expect 200
  let container = ContainerImage::new("nginx", "1.25-alpine")
    .with_exposed_port(80)
    .with_wait_for(WaitStrategy::HttpGet("/index.html", 200))
    .with_wait_timeout(30)
    .start()

  match container {
    Ok(c) => {
      println("Nginx started with HTTP wait strategy (custom path)")
      println("Container ID: \{c.get_id()}")

      // Cleanup
      let _ = c.cleanup()
    }
    Err(e) => {
      println("Failed: \{e.to_string()}")
      abort("HTTP wait strategy with custom path failed")
    }
  }
}

///|
/// Test HTTP endpoint error when no ports exposed
async test "wait strategy http get no ports" {
  // Try to use HTTP wait without exposing ports
  let container = ContainerImage::new("alpine", "3.19")
    .with_cmd(["sleep", "10"])
    .with_wait_for(WaitStrategy::HttpGet("/", 200))
    .with_wait_timeout(5)
    .start()

  match container {
    Ok(_) => abort("Expected error but got success")
    Err(e) => {
      println("Got expected error: \{e.to_string()}")
      // Test passed - we expected a configuration error
    }
  }
}
