// Integration tests for basic log retrieval
// Note: These tests require Docker to be installed and running

///|
/// Phase 1: Test basic log retrieval
async test "logsbasic" {
  println("Starting basic log retrieval test")
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

// ///|
// /// Phase 1: Test multiple lines log retrieval
// async test "get_logs - multiple lines" {
//   // Create a container that outputs multiple lines
//   let container = ContainerImage::new("alpine", "3.19")
//     .with_cmd(["sh", "-c", "echo 'line 1'; echo 'line 2'; echo 'line 3'"])
//     .start()
//   match container {
//     Ok(c) => {
//       println("Container started: \{c.get_id()}")

//       // Wait for the command to complete
//       @async.sleep(1000000000)

//       // Get logs
//       match c.get_logs() {
//         Ok(logs) => {
//           println("Logs retrieved (multiple lines)")
//           if !logs.contains("line 1") ||
//             !logs.contains("line 2") ||
//             !logs.contains("line 3") {
//             abort("Logs do not contain all expected lines")
//           }
//         }
//         Err(e) => {
//           println("Failed to get logs: \{e.to_string()}")
//           abort("get_logs failed")
//         }
//       }

//       // Cleanup
//       let _ = c.cleanup()

//     }
//     Err(e) => {
//       println("Failed to start container: \{e.to_string()}")
//       abort("Container start failed")
//     }
//   }
// }

// ///|
// /// Phase 1: Test empty logs
// async test "get_logs - empty log" {
//   // Create a container that produces no output
//   let container = ContainerImage::new("alpine", "3.19")
//     .with_cmd(["sh", "-c", "exit 0"])
//     .start()
//   match container {
//     Ok(c) => {
//       println("Container started: \{c.get_id()}")

//       // Wait for the command to complete
//       @async.sleep(1000000000)

//       // Get logs
//       match c.get_logs() {
//         Ok(logs) => println("Empty logs retrieved successfully: '\{logs}'")
//         // Empty or very short output is expected
//         Err(e) => {
//           println("Failed to get logs: \{e.to_string()}")
//           abort("get_logs failed")
//         }
//       }

//       // Cleanup
//       let _ = c.cleanup()

//     }
//     Err(e) => {
//       println("Failed to start container: \{e.to_string()}")
//       abort("Container start failed")
//     }
//   }
// }

// ///|
// /// Phase 1: Test Unicode characters in logs
// async test "get_logs - unicode characters" {
//   // Create a container that outputs Unicode characters
//   let container = ContainerImage::new("alpine", "3.19")
//     .with_cmd(["sh", "-c", "echo 'こんにちは世界 🌍'"])
//     .start()
//   match container {
//     Ok(c) => {
//       println("Container started: \{c.get_id()}")

//       // Wait for the command to complete
//       @async.sleep(1000000000)

//       // Get logs
//       match c.get_logs() {
//         Ok(logs) => {
//           println("Unicode logs retrieved: \{logs}")
//           if !logs.contains("こんにちは") || !logs.contains("🌍") {
//             abort("Logs do not contain Unicode characters")
//           }
//         }
//         Err(e) => {
//           println("Failed to get logs: \{e.to_string()}")
//           abort("get_logs failed")
//         }
//       }

//       // Cleanup
//       let _ = c.cleanup()

//     }
//     Err(e) => {
//       println("Failed to start container: \{e.to_string()}")
//       abort("Container start failed")
//     }
//   }
// }
