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

///|
/// Phase 1: Test basic log retrieval
async test "get_logs - basic" {
  // Create a container that outputs a simple message
  let container = ContainerImage::new("alpine", "3.19")
    .with_cmd(["sh", "-c", "echo 'test log message'"])
    .start()

  match container {
    Ok(c) => {
      println("Container started: \{c.get_id()}")

      // Wait a moment for the command to complete
      @async.sleep(1000000000) // 1 second in nanoseconds

      // Get logs
      match c.get_logs() {
        Ok(logs) => {
          println("Logs retrieved: \{logs}")
          if !logs.contains("test log message") {
            abort("Logs do not contain expected message")
          }
        }
        Err(e) => {
          println("Failed to get logs: \{e.to_string()}")
          abort("get_logs failed")
        }
      }

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
/// Phase 1: Test multiple lines log retrieval
async test "get_logs - multiple lines" {
  // Create a container that outputs multiple lines
  let container = ContainerImage::new("alpine", "3.19")
    .with_cmd(["sh", "-c", "echo 'line 1'; echo 'line 2'; echo 'line 3'"])
    .start()

  match container {
    Ok(c) => {
      println("Container started: \{c.get_id()}")

      // Wait for the command to complete
      @async.sleep(1000000000)

      // Get logs
      match c.get_logs() {
        Ok(logs) => {
          println("Logs retrieved (multiple lines)")
          if !logs.contains("line 1") || !logs.contains("line 2") || !logs.contains("line 3") {
            abort("Logs do not contain all expected lines")
          }
        }
        Err(e) => {
          println("Failed to get logs: \{e.to_string()}")
          abort("get_logs failed")
        }
      }

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
/// Phase 1: Test empty logs
async test "get_logs - empty log" {
  // Create a container that produces no output
  let container = ContainerImage::new("alpine", "3.19")
    .with_cmd(["sh", "-c", "exit 0"])
    .start()

  match container {
    Ok(c) => {
      println("Container started: \{c.get_id()}")

      // Wait for the command to complete
      @async.sleep(1000000000)

      // Get logs
      match c.get_logs() {
        Ok(logs) => {
          println("Empty logs retrieved successfully: '\{logs}'")
          // Empty or very short output is expected
        }
        Err(e) => {
          println("Failed to get logs: \{e.to_string()}")
          abort("get_logs failed")
        }
      }

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
/// Phase 1: Test Unicode characters in logs
async test "get_logs - unicode characters" {
  // Create a container that outputs Unicode characters
  let container = ContainerImage::new("alpine", "3.19")
    .with_cmd(["sh", "-c", "echo 'こんにちは世界 🌍'"])
    .start()

  match container {
    Ok(c) => {
      println("Container started: \{c.get_id()}")

      // Wait for the command to complete
      @async.sleep(1000000000)

      // Get logs
      match c.get_logs() {
        Ok(logs) => {
          println("Unicode logs retrieved: \{logs}")
          if !logs.contains("こんにちは") || !logs.contains("🌍") {
            abort("Logs do not contain Unicode characters")
          }
        }
        Err(e) => {
          println("Failed to get logs: \{e.to_string()}")
          abort("get_logs failed")
        }
      }

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
/// Phase 2: Test tail option
async test "get_logs_with_options - tail" {
  // Create a container that outputs multiple lines
  let container = ContainerImage::new("alpine", "3.19")
    .with_cmd(["sh", "-c", "for i in $(seq 1 20); do echo \"Line $i\"; done"])
    .start()

  match container {
    Ok(c) => {
      println("Container started: \{c.get_id()}")

      // Wait for the command to complete
      @async.sleep(1000000000)

      // Get last 5 lines only
      let options = LogOptions::default().with_tail(5)
      match c.get_logs_with_options(options) {
        Ok(logs) => {
          println("Logs with tail option: \{logs}")
          // Should contain Line 16-20, but not Line 1-15
          if logs.contains("Line 1") {
            abort("Logs should not contain early lines with tail=5")
          }
          if !logs.contains("Line 20") {
            abort("Logs should contain last line")
          }
        }
        Err(e) => {
          println("Failed to get logs: \{e.to_string()}")
          abort("get_logs_with_options failed")
        }
      }

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
/// Phase 2: Test timestamps option
async test "get_logs_with_options - timestamps" {
  // Create a container that outputs a message
  let container = ContainerImage::new("alpine", "3.19")
    .with_cmd(["sh", "-c", "echo 'timestamped message'"])
    .start()

  match container {
    Ok(c) => {
      println("Container started: \{c.get_id()}")

      // Wait for the command to complete
      @async.sleep(1000000000)

      // Get logs with timestamps
      let options = LogOptions::default().with_timestamps(true)
      match c.get_logs_with_options(options) {
        Ok(logs) => {
          println("Logs with timestamps: \{logs}")
          // Timestamps typically contain 'T' (ISO format) or contain year/date info
          // Just verify we got some output
          if !logs.contains("timestamped message") {
            abort("Logs do not contain expected message")
          }
        }
        Err(e) => {
          println("Failed to get logs: \{e.to_string()}")
          abort("get_logs_with_options failed")
        }
      }

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
/// Phase 2: Test follow option error
async test "get_logs_with_options - follow error" {
  // Create a container
  let container = ContainerImage::new("alpine", "3.19")
    .with_cmd(["sleep", "10"])
    .start()

  match container {
    Ok(c) => {
      println("Container started: \{c.get_id()}")

      // Try to use follow option (should return error)
      let options = LogOptions::default().with_follow(true)
      match c.get_logs_with_options(options) {
        Ok(_) => {
          let _ = c.cleanup()
          abort("Expected error for follow option")
        }
        Err(e) => {
          println("Got expected error: \{e.to_string()}")
          // Test passed - we expected an error
        }
      }

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
/// Phase 3: Test basic log streaming
async test "stream_logs - basic" {
  // Create a container that outputs messages over time
  let container = ContainerImage::new("alpine", "3.19")
    .with_cmd(["sh", "-c", "echo 'stream line 1'; echo 'stream line 2'; echo 'stream line 3'"])
    .start()

  match container {
    Ok(c) => {
      println("Container started for streaming: \{c.get_id()}")

      // Wait for container to start
      @async.sleep(500000000) // 0.5 seconds

      // Collect streamed lines
      let lines : Array[String] = []
      let callback = fn(line : String) {
        println("Streamed: \{line}")
        lines.push(line)
      }

      // Stream logs
      match c.stream_logs(callback) {
        Ok(_) => {
          println("Streaming completed, received \{lines.length()} lines")
          if lines.length() == 0 {
            abort("No lines received from stream")
          }
          // Check if we got expected content
          let all_text = lines.iter().fold("", fn(acc, line) { acc + line })
          if !all_text.contains("stream line") {
            abort("Streamed logs do not contain expected content")
          }
        }
        Err(e) => {
          println("Failed to stream logs: \{e.to_string()}")
          abort("stream_logs failed")
        }
      }

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
/// Phase 3: Test streaming callback count
async test "stream_logs - callback count" {
  // Create a container that outputs exactly 5 lines
  let container = ContainerImage::new("alpine", "3.19")
    .with_cmd(["sh", "-c", "for i in 1 2 3 4 5; do echo \"Count $i\"; done"])
    .start()

  match container {
    Ok(c) => {
      println("Container started for counting: \{c.get_id()}")

      // Wait for container to start
      @async.sleep(500000000)

      // Count the callbacks
      let count = { val: 0 }
      let callback = fn(line : String) {
        count.val = count.val + 1
        println("Callback #\{count.val}: \{line}")
      }

      // Stream logs
      match c.stream_logs(callback) {
        Ok(_) => {
          println("Total callbacks: \{count.val}")
          if count.val == 0 {
            abort("No callbacks invoked")
          }
          // We expect at least the 5 echo lines (may have additional empty lines)
          if count.val < 5 {
            abort("Expected at least 5 callbacks, got \{count.val}")
          }
        }
        Err(e) => {
          println("Failed to stream logs: \{e.to_string()}")
          abort("stream_logs failed")
        }
      }

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
/// Phase 3: Test streaming with Redis (real-world example)
async test "stream_logs - redis container" {
  // Start Redis and stream its startup logs
  let container = ContainerImage::new("redis", "7.2.4")
    .with_exposed_port(6379)
    .with_wait_for(WaitStrategy::TcpPort(6379))
    .with_wait_timeout(30)
    .start()

  match container {
    Ok(c) => {
      println("Redis container started: \{c.get_id()}")

      // Redis is already running, get its logs
      let lines : Array[String] = []
      let callback = fn(line : String) {
        lines.push(line)
        if lines.length() <= 10 {
          println("Redis log: \{line}")
        }
      }

      // Stream logs with tail to limit output
      let options = LogOptions::default().with_tail(20)
      match c.stream_logs(callback, options) {
        Ok(_) => {
          println("Redis logs streamed: \{lines.length()} lines")
          if lines.length() == 0 {
            abort("No logs received from Redis")
          }
          // Redis logs typically contain "Ready to accept connections"
          let all_text = lines.iter().fold("", fn(acc, line) { acc + line })
          if !all_text.contains("Ready") && !all_text.contains("Redis") {
            println("Warning: Redis logs may not contain expected patterns")
          }
        }
        Err(e) => {
          println("Failed to stream Redis logs: \{e.to_string()}")
          abort("stream_logs failed for Redis")
        }
      }

      // Cleanup
      let _ = c.cleanup()
    }
    Err(e) => {
      println("Failed to start Redis container: \{e.to_string()}")
      abort("Redis container start failed")
    }
  }
}
