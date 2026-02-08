# Testcontainers for MoonBit

A MoonBit implementation of Testcontainers, a library for creating and managing Docker containers for integration testing.

## Features

- **Simple Container Management**: Start, stop, and remove Docker containers programmatically
- **Port Mapping**: Automatically map container ports to random host ports
- **Environment Variables**: Configure containers with custom environment variables
- **Volume Mounting**: Mount host files and directories into containers
- **Fluent API**: Builder pattern for intuitive container configuration
- **Async Support**: Built on MoonBit's async primitives for efficient I/O
- **Wait Strategies**: TCP port, HTTP endpoint, and simple delay strategies
- **Container Logs**: Retrieve and stream container logs in real-time

## Requirements

- **MoonBit**: Latest version with native/LLVM backend support
- **Docker**: Docker must be installed and running on your system
- **Platform**: Linux or macOS (the `moonbitlang/async/process` package currently supports native backends only)

## Installation

Add to your `moon.mod.json`:

```json
{
  "deps": {
    "username/moonbit_test_containers": "0.1.0",
    "moonbitlang/async": "0.16.5"
  }
}
```

And in your `moon.pkg.json`:

```json
{
  "import": [
    "moonbitlang/async",
    "moonbitlang/async/process",
    "moonbitlang/async/http"
  ]
}
```

## Usage

### Basic Example

```moonbit
// Create and start a Redis container
let container = ContainerImage::new("redis", "7.2.4")
  .with_exposed_port(6379)
  .with_env_var("REDIS_PORT", "6379")
  .start()

match container {
  Ok(c) => {
    // Get the host port
    match c.get_host_port(6379) {
      Some(port) => println("Redis running on port: \{port}")
      None => println("Port not mapped")
    }

    // Cleanup when done
    let _ = c.cleanup()
  }
  Err(e) => println("Error: \{e.to_string()}")
}
```

### Advanced Configuration

```moonbit
let container = ContainerImage::new("postgres", "16")
  .with_exposed_port(5432)
  .with_env_var("POSTGRES_USER", "testuser")
  .with_env_var("POSTGRES_PASSWORD", "testpass")
  .with_env_var("POSTGRES_DB", "testdb")
  .start()

match container {
  Ok(c) => {
    println("PostgreSQL container: \{c.get_id()}")

    // Use the container in your tests
    // ...

    // Stop and remove separately
    let _ = c.stop()
    let _ = c.remove()
  }
  Err(e) => println("Failed to start: \{e.to_string()}")
}
```

### Volume Mounting

Mount host files and directories into containers for configuration, initialization scripts, or data sharing.

#### Basic File Mount

```moonbit
///|
let container = ContainerImage::new("nginx", "1.25-alpine")
  .with_exposed_port(80)
  .with_volume("./nginx.conf", "/etc/nginx/nginx.conf")
  .start()
```

#### Read-Only Mount

```moonbit
///|
let container = ContainerImage::new("myapp", "latest")
  .with_volume_ro("./config", "/app/config")
  .start()
```

#### Multiple Volumes

```moonbit
///|
let container = ContainerImage::new("myapp", "latest")
  .with_volume_ro("./config", "/app/config")
  .with_volume("./data", "/app/data")
  .with_volume("./logs", "/app/logs")
  .start()
```

#### PostgreSQL Initialization Script

Mount SQL scripts to initialize your database:

```moonbit
let container = ContainerImage::new("postgres", "16")
  .with_exposed_port(5432)
  .with_env_var("POSTGRES_USER", "test")
  .with_env_var("POSTGRES_PASSWORD", "test")
  .with_env_var("POSTGRES_DB", "testdb")
  .with_volume("./init.sql", "/docker-entrypoint-initdb.d/init.sql")
  .with_wait_for(WaitStrategy::TcpPort(5432))
  .with_wait_timeout(60)
  .start()

match container {
  Ok(c) => {
    // PostgreSQL is now ready with your schema initialized
    match c.get_host_port(5432) {
      Some(port) => println("PostgreSQL ready on port: \{port}")
      None => println("Port not mapped")
    }
    let _ = c.cleanup()
  }
  Err(e) => println("Failed: \{e.to_string()}")
}
```

### Wait Strategies

Wait strategies ensure that containers are fully ready before your tests begin. This is essential for services that take time to initialize (like databases, web servers, and APIs).

#### TCP Port Wait

Wait for a TCP port to become available:

```moonbit
///|
let container = ContainerImage::new("redis", "7.2.4")
  .with_exposed_port(6379)
  .with_wait_for(WaitStrategy::TcpPort(6379))
  .with_wait_timeout(30) // optional, defaults to 60 seconds
  .start()
```

#### HTTP Endpoint Wait

Wait for an HTTP endpoint to return a specific status code:

```moonbit
let container = ContainerImage::new("nginx", "1.25-alpine")
  .with_exposed_port(80)
  .with_wait_for(WaitStrategy::HttpGet("/", 200))
  .with_wait_timeout(30)
  .start()

match container {
  Ok(c) => {
    // Nginx is now ready and responding to HTTP requests
    match c.get_host_port(80) {
      Some(port) => println("Nginx ready on port: \{port}")
      None => println("Port not mapped")
    }
    let _ = c.cleanup()
  }
  Err(e) => println("Failed: \{e.to_string()}")
}
```

You can also wait for custom paths and status codes:

```moonbit
// Wait for a health check endpoint to return 200

///|
let container = ContainerImage::new("myapp", "latest")
  .with_exposed_port(8080)
  .with_wait_for(WaitStrategy::HttpGet("/health", 200))
  .with_wait_timeout(60)
  .start()
```

#### Simple Delay

Wait for a fixed number of seconds:

```moonbit
///|
let container = ContainerImage::new("alpine", "3.19")
  .with_cmd(["sleep", "10"])
  .with_wait_for(WaitStrategy::Seconds(5))
  .start()
```

#### PostgreSQL Example

PostgreSQL takes several seconds to start. Use TCP port wait to ensure it's ready:

```moonbit
let container = ContainerImage::new("postgres", "16")
  .with_exposed_port(5432)
  .with_env_var("POSTGRES_USER", "test")
  .with_env_var("POSTGRES_PASSWORD", "test")
  .with_env_var("POSTGRES_DB", "test")
  .with_wait_for(WaitStrategy::TcpPort(5432))
  .with_wait_timeout(60)
  .start()

match container {
  Ok(c) => {
    // PostgreSQL is now ready to accept connections
    match c.get_host_port(5432) {
      Some(port) => println("PostgreSQL ready on port: \{port}")
      None => println("Port not mapped")
    }
    let _ = c.cleanup()
  }
  Err(e) => println("Failed: \{e.to_string()}")
}
```

### Container Logs

Retrieve and stream container logs for debugging and monitoring.

#### Basic Log Retrieval

Get all logs from a container:

```moonbit
match container.get_logs() {
  Ok(logs) => println("Container logs:\n\{logs}")
  Err(e) => println("Failed to get logs: \{e.to_string()}")
}
```

#### Log Options

Customize log retrieval with options:

```moonbit
// Get last 100 lines with timestamps
let options = LogOptions::default()
  .with_tail(100)
  .with_timestamps(true)

match container.get_logs_with_options(options) {
  Ok(logs) => println("Recent logs:\n\{logs}")
  Err(e) => println("Failed to get logs: \{e.to_string()}")
}
```

Available options:
- `.with_tail(lines: Int)`: Get only the last N lines
- `.with_timestamps(enabled: Bool)`: Include timestamps
- `.with_since(timestamp: String)`: Get logs since a specific time
- `.with_until(timestamp: String)`: Get logs until a specific time

#### Log Streaming

Stream logs in real-time with a callback:

```moonbit
// Stream logs line by line
let callback = fn(line: String) {
  println("Log: \{line}")
}

match container.stream_logs(callback) {
  Ok(_) => println("Streaming complete")
  Err(e) => println("Failed to stream: \{e.to_string()}")
}
```

Stream with options:

```moonbit
// Stream only recent logs
let options = LogOptions::default().with_tail(50)

match container.stream_logs(callback, options=options) {
  Ok(_) => println("Streaming complete")
  Err(e) => println("Failed to stream: \{e.to_string()}")
}
```

#### Debugging Failed Containers

```moonbit
let container = ContainerImage::new("myapp", "latest")
  .with_exposed_port(8080)
  .start()

match container {
  Ok(c) => {
    // If something goes wrong, check the logs
    match c.get_logs() {
      Ok(logs) => {
        if logs.contains("ERROR") {
          println("Container error detected:\n\{logs}")
        }
      }
      Err(e) => println("Failed to get logs: \{e.to_string()}")
    }
    let _ = c.cleanup()
  }
  Err(e) => println("Failed to start: \{e.to_string()}")
}
```

## API Reference

### `ContainerImage`

Create and configure a container image:

- `ContainerImage::new(name: String, tag: String) -> ContainerImage`
- `.with_exposed_port(port: Int) -> ContainerImage`
- `.with_env_var(key: String, value: String) -> ContainerImage`
- `.with_cmd(cmd: Array[String]) -> ContainerImage`
- `.with_volume(host_path: String, container_path: String) -> ContainerImage` - Mount a volume (read-write)
- `.with_volume_ro(host_path: String, container_path: String) -> ContainerImage` - Mount a volume as read-only
- `.with_wait_for(strategy: WaitStrategy) -> ContainerImage`
- `.with_wait_timeout(timeout: Int) -> ContainerImage` - timeout in seconds (default: 60)
- `.start() -> Result[Container, TestContainerError]` (async)

### `WaitStrategy`

Strategies for waiting until a container is ready:

- `WaitStrategy::TcpPort(port: Int)` - Wait for TCP port to be open
- `WaitStrategy::HttpGet(path: String, expected_status: Int)` - Wait for HTTP endpoint to return expected status code
- `WaitStrategy::Seconds(seconds: Int)` - Wait for a fixed duration

### `Container`

Manage running containers:

- `.get_id() -> String`
- `.get_host_port(container_port: Int) -> Option[Int]`
- `.stop() -> Result[Unit, TestContainerError]` (async)
- `.remove() -> Result[Unit, TestContainerError]` (async)
- `.cleanup() -> Result[Unit, TestContainerError]` (async) - stops and removes the container
- `.get_logs() -> Result[String, TestContainerError]` (async)
- `.get_logs_with_options(options: LogOptions) -> Result[String, TestContainerError]` (async)
- `.stream_logs(callback: (String) -> Unit, options?: LogOptions) -> Result[Unit, TestContainerError]` (async)

### `LogOptions`

Configure log retrieval:

- `LogOptions::default() -> LogOptions`
- `.with_tail(lines: Int) -> LogOptions` - Get last N lines
- `.with_timestamps(enabled: Bool) -> LogOptions` - Include timestamps
- `.with_since(timestamp: String) -> LogOptions` - Get logs since timestamp
- `.with_until(timestamp: String) -> LogOptions` - Get logs until timestamp
- `.with_follow(enabled: Bool) -> LogOptions` - Follow log output (only for `stream_logs`)

Note: The `.with_follow()` option cannot be used with `get_logs_with_options()`. Use `stream_logs()` for following logs.

## Building and Testing

Build the project (native target required):

```bash
moon check --target native
```

Run tests (requires Docker):

```bash
moon test --target native
```

## Current Limitations

- **Backend Support**: Only native/LLVM backend is supported (wasm-gc and js backends are not supported due to process execution requirements)
- **Wait Strategies**: HTTP endpoint wait uses the first exposed port; log message waiting is planned
- **HTTP Support**: Only HTTP (not HTTPS), GET method only, status code checking only
- **Network Management**: Custom networks are not supported yet
- **Volume Mounting**: Only bind mounts are supported; named volumes and tmpfs are not yet supported
- **Platform**: Linux and macOS only (Windows support requires investigation)

## Future Enhancements

- [x] Wait strategies - TCP port and delay (implemented)
- [x] Wait strategies - HTTP endpoint (implemented)
- [x] Container logs streaming (implemented)
- [x] Volume mounting - bind mounts (implemented)
- [ ] Wait strategies - log message
- [ ] HTTPS support for HTTP wait strategy
- [ ] Custom HTTP headers and methods
- [ ] Response body validation for HTTP wait strategy
- [ ] Custom network support
- [ ] Named volumes and tmpfs support
- [ ] Specialized modules for popular services (PostgreSQL, Redis, MongoDB)
- [ ] Windows support

## License

Apache-2.0

## Contributing

Contributions are welcome! Please feel free to submit issues and pull requests.

## Acknowledgments

This project is inspired by the [Testcontainers](https://testcontainers.com/) project, with implementations in multiple languages including [testcontainers-rs](https://github.com/testcontainers/testcontainers-rs) (Rust) and [testcontainers-go](https://github.com/testcontainers/testcontainers-go) (Go).
