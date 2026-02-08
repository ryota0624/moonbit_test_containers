// Wait strategy implementation for native backend
// Uses @process.collect_output_merged for TCP port check

///|
/// Check if a TCP port is open using netcat (native backend)
#cfg(target="native")
async fn check_tcp_port(host : String, port : Int) -> Bool {
  // Use nc (netcat) to check if port is open
  // nc -z returns 0 if connection succeeds
  let command = "nc"
  let args = ["-z", "-w", "1", host, port.to_string()]
  let (status, _) = @process.collect_output_merged(command, args) catch {
    _ => return false
  }
  status == 0
}

///|
/// Check if an HTTP endpoint returns the expected status code (native backend)
#cfg(target="native")
async fn check_http_endpoint(
  host : String,
  port : Int,
  path : String,
  expected_status : Int,
) -> Bool {
  // Construct URL
  let url = "http://\{host}:\{port}\{path}"
  // Send GET request and get response
  let (response, body) = @http.get_stream(url) catch {
    // Any error (connection refused, timeout, etc.) means not ready
    _ => return false
  }
  defer body.close()

  // Check if status code matches
  response.code == expected_status
}
