// Wait strategy implementation for JavaScript backend
// Uses Node.js net module for TCP port check and http module for HTTP endpoint check

///|
/// Import AnyValue type from docker_js.mbt
/// (Assuming it's accessible, otherwise define it here too)

///|
/// Check if a TCP port is open using Node.js net module (JavaScript backend)
///
/// Returns: Promise that resolves to boolean
extern "js" fn check_tcp_port_sync(
  host : String,
  port : Int,
) -> @js_async.Promise[Bool] =
  #| (host, port) => {
  #|   const net = require('net');
  #|
  #|   return new Promise((resolve) => {
  #|     const socket = new net.Socket();
  #|     const timeout = 1000; // 1 second timeout
  #|
  #|     socket.setTimeout(timeout);
  #|
  #|     socket.on('connect', () => {
  #|       socket.destroy();
  #|       resolve(true);
  #|     });
  #|
  #|     socket.on('timeout', () => {
  #|       socket.destroy();
  #|       resolve(false);
  #|     });
  #|
  #|     socket.on('error', () => {
  #|       socket.destroy();
  #|       resolve(false);
  #|     });
  #|
  #|     socket.connect(port, host);
  #|   });
  #| }

///|
/// Check if a TCP port is open (JavaScript backend)
#cfg(target="js")
async fn check_tcp_port(host : String, port : Int) -> Bool {
  try {
    // Call FFI function that returns a Promise
    let promise = check_tcp_port_sync(host, port)
    // Wait for the promise to resolve
    @js_async.Promise::wait(promise)
  } catch {
    _ => false
  }
}

///|
/// Check if an HTTP endpoint returns the expected status code (JavaScript backend)
///
/// Returns: Promise that resolves to Array[AnyValue] where [success, status_code]
extern "js" fn check_http_endpoint_sync(
  host : String,
  port : Int,
  path : String,
) -> @js_async.Promise[Array[AnyValue]] =
  #| (host, port, path) => {
  #|   const http = require('http');
  #|
  #|   return new Promise((resolve) => {
  #|     const options = {
  #|       hostname: host,
  #|       port: port,
  #|       path: path,
  #|       method: 'GET',
  #|       timeout: 1000  // 1 second timeout
  #|     };
  #|
  #|     const req = http.request(options, (res) => {
  #|       // Consume response data to free up memory
  #|       res.on('data', () => {});
  #|       res.on('end', () => {
  #|         resolve([true, res.statusCode]);
  #|       });
  #|     });
  #|
  #|     req.on('timeout', () => {
  #|       req.destroy();
  #|       resolve([false, 0]);
  #|     });
  #|
  #|     req.on('error', () => {
  #|       resolve([false, 0]);
  #|     });
  #|
  #|     req.end();
  #|   });
  #| }

///|
/// Check if an HTTP endpoint returns the expected status code (JavaScript backend)
#cfg(target="js")
async fn check_http_endpoint(
  host : String,
  port : Int,
  path : String,
  expected_status : Int,
) -> Bool {
  try {
    // Call FFI function that returns a Promise
    let promise = check_http_endpoint_sync(host, port, path)
    // Wait for the promise to resolve and extract values from Array[AnyValue]
    let result = @js_async.Promise::wait(promise)
    let success = result[0].as_bool()
    let status_code = result[1].as_int()

    // Check if request succeeded and status code matches
    success && status_code == expected_status
  } catch {
    // Any error means not ready
    _ => false
  }
}
