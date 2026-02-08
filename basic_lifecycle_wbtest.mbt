// Integration tests for basic container lifecycle
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
  let container = ContainerImage::new("nonexistent-image-xyz", "999.999.999").start()
  match container {
    Ok(_) => abort("Expected error but got success")
    Err(e) => println("Got expected error: \{e.to_string()}")
    // Test passed - we expected an error
  }
}
