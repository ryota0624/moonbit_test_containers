// Integration tests for advanced log options
// Note: These tests require Docker to be installed and running

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
        Err(e) => println("Got expected error: \{e.to_string()}")
        // Test passed - we expected an error
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
