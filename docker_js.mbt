// Docker command executor for JavaScript backend
// Uses Node.js child_process via FFI

///|
/// AnyValue type for JavaScript FFI
/// Used to receive JavaScript values that will be converted to MoonBit types
priv type AnyValue

///|
/// Convert AnyValue to Int
extern "js" fn AnyValue::as_int(self : AnyValue) -> Int =
  #| (self) => { return self; }

///|
/// Convert AnyValue to String
extern "js" fn AnyValue::as_string(self : AnyValue) -> String =
  #| (self) => { return self; }

///|
/// Convert AnyValue to Bool
extern "js" fn AnyValue::as_bool(self : AnyValue) -> Bool =
  #| (self) => { return self; }

///|
/// Execute docker command synchronously using Node.js child_process.execSync
///
/// Returns: Array[AnyValue] where [exit_status, output]
extern "js" fn exec_docker_sync_ffi(
  command : String,
  args : FixedArray[String],
) -> FixedArray[AnyValue] =
  #| (command, args) => {
  #|   // Import Node.js child_process module
  #|   const { spawnSync } = require('child_process');
  #|
  #|   // Use spawnSync to capture both stdout and stderr
  #|   const result = spawnSync(command, args, {
  #|     encoding: 'utf8',
  #|     maxBuffer: 10 * 1024 * 1024  // 10MB buffer
  #|   });
  #|
  #|   // Combine stdout and stderr
  #|   const stdout = result.stdout || "";
  #|   const stderr = result.stderr || "";
  #|   const output = stdout + stderr;
  #|
  #|   // Check exit status
  #|   if (result.status === 0 || result.status === null) {
  #|     // Success: return array [status, combined output]
  #|     return [0, output];
  #|   } else if (result.error) {
  #|     // Error launching process (e.g., command not found)
  #|     const status = result.status || 1;
  #|     return [status, result.error.message || output];
  #|   } else {
  #|     // Non-zero exit status
  #|     return [result.status, output];
  #|   }
  #| }

fn exec_docker_sync(
  command : String,
  args : Array[String],
) -> Array[AnyValue] {
  Array::from_fixed_array(exec_docker_sync_ffi(command, FixedArray::from_array(args)))
}

///|
/// Execute docker command using JavaScript FFI
#cfg(target="js")
pub async fn exec_docker(
  args : Array[String],
) -> Result[String, TestContainerError] noraise {
  let command = "docker"

  // Call FFI function - returns Array[AnyValue]
  let result = exec_docker_sync(command, args)

  // Extract values from array
  let status = result[0].as_int()
  let output = result[1].as_string()

  // Trim output (remove trailing whitespace) and convert to String
  let output_view = output.trim_end()
  let output_str = "\{output_view}"
  if status == 0 {
    // Success: return trimmed output
    Ok(output_str)
    // Check if error indicates Docker CLI is not installed
  } else if output_str.contains("ENOENT") ||
    output_str.contains("not found") ||
    output_str.contains("command not found") {
    Err(
      DockerCommandFailed(
        "Docker CLI is not installed or not available in PATH.\n\nPlease install Docker to use this library:\n- macOS: https://docs.docker.com/desktop/install/mac-install/\n- Windows: https://docs.docker.com/desktop/install/windows-install/\n- Linux: https://docs.docker.com/desktop/install/linux-install/\n\nAfter installation, make sure 'docker' command is available in your PATH.",
      ),
    )
  } else {
    // Failed: return error with details
    Err(DockerCommandFailed(output_str))
  }
}
