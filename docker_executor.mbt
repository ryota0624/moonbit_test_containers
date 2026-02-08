// Docker command executor - common utilities
// Backend-specific implementations:
// - Native backend: docker_native.mbt
// - JavaScript backend: docker_js.mbt

///|
/// Parse port mapping output from docker port command
/// Expected format: "0.0.0.0:32768" or "[::]:32768"
pub fn parse_port_mapping(output : String) -> Int? {
  // Find the last colon and extract the port number after it
  let chars = output.to_array()
  let mut last_colon_idx = -1
  for i = 0; i < chars.length(); i = i + 1 {
    if chars[i] == ':' {
      last_colon_idx = i
    }
  }
  if last_colon_idx == -1 || last_colon_idx == chars.length() - 1 {
    return None
  }

  // Extract port number string
  let port_start = last_colon_idx + 1
  let port_chars : Array[Char] = []
  for i = port_start; i < chars.length(); i = i + 1 {
    port_chars.push(chars[i])
  }
  let port_str = String::from_array(port_chars)
  Some(
    // Parse to integer
    @strconv.parse_int(port_str),
  ) catch {
    _ => None
  }
}
