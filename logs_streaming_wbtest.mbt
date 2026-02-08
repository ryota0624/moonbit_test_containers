// Integration tests for log streaming
// Note: These tests require Docker to be installed and running

///|
/// Phase 3: Test basic log streaming
async test "stream_logs - basic" {
  // Create a container that outputs messages over time
  let container = ContainerImage::new("alpine", "3.19")
    .with_cmd([
      "sh", "-c", "echo 'stream line 1'; echo 'stream line 2'; echo 'stream line 3'",
    ])
    .start()
  match container {
    Ok(c) => {
      println("Container started for streaming: \{c.get_id()}")

      // Wait for container to start
      @async.sleep(500) // 0.5 seconds

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
          let mut all_text = ""
          for i = 0; i < lines.length(); i = i + 1 {
            all_text = all_text + lines[i]
          }
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
      @async.sleep(500) // 0.5 seconds

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
      match c.stream_logs(callback, options~) {
        Ok(_) => {
          println("Redis logs streamed: \{lines.length()} lines")
          if lines.length() == 0 {
            abort("No logs received from Redis")
          }
          // Redis logs typically contain "Ready to accept connections"
          let mut all_text = ""
          for i = 0; i < lines.length(); i = i + 1 {
            all_text = all_text + lines[i]
          }
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
