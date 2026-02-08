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
extern "js" fn exec_docker_sync(
  command : String,
  args : Array[String],
) -> Array[AnyValue] =
  #| (command, args) => {
  #|   // Import Node.js child_process module
  #|   const { execSync } = require('child_process');
  #|
  #|   try {
  #|     // Join arguments and execute command
  #|     const argsStr = args.join(' ');
  #|     const fullCommand = command + ' ' + argsStr;
  #|
  #|     // Execute with options
  #|     const output = execSync(fullCommand, {
  #|       encoding: 'utf8',
  #|       stdio: ['pipe', 'pipe', 'pipe'],
  #|       maxBuffer: 10 * 1024 * 1024  // 10MB buffer
  #|     });
  #|
  #|     // Success: return array [status, output]
  #|     return [0, output || ""];
  #|   } catch (error) {
  #|     // Error: return array [status, error message]
  #|     const status = error.status || 1;
  #|     const output = error.stderr ? error.stderr.toString() : (error.message || "");
  #|     return [status, output || ""];
  #|   }
  #| }

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
  } else {
    // Failed: return error with details
    Err(DockerCommandFailed(output_str))
  }
}
