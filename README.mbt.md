# Testcontainers for MoonBit

A MoonBit implementation of Testcontainers, a library for creating and managing Docker containers for integration testing.

## Features

- **Simple Container Management**: Start, stop, and remove Docker containers programmatically
- **Port Mapping**: Automatically map container ports to random host ports
- **Environment Variables**: Configure containers with custom environment variables
- **Fluent API**: Builder pattern for intuitive container configuration
- **Async Support**: Built on MoonBit's async primitives for efficient I/O

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
    "moonbitlang/async/process"
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

## API Reference

### `ContainerImage`

Create and configure a container image:

- `ContainerImage::new(name: String, tag: String) -> ContainerImage`
- `.with_exposed_port(port: Int) -> ContainerImage`
- `.with_env_var(key: String, value: String) -> ContainerImage`
- `.with_cmd(cmd: Array[String]) -> ContainerImage`
- `.start() -> Result[Container, TestContainerError]` (async)

### `Container`

Manage running containers:

- `.get_id() -> String`
- `.get_host_port(container_port: Int) -> Option[Int]`
- `.stop() -> Result[Unit, TestContainerError]` (async)
- `.remove() -> Result[Unit, TestContainerError]` (async)
- `.cleanup() -> Result[Unit, TestContainerError]` (async) - stops and removes the container

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
- **Wait Strategies**: Not yet implemented - containers start immediately without waiting for readiness
- **Network Management**: Custom networks are not supported yet
- **Volume Management**: Volume mounting is not yet supported
- **Platform**: Linux and macOS only (Windows support requires investigation)

## Future Enhancements

- [ ] Wait strategies (log message, TCP port, HTTP endpoint)
- [ ] Custom network support
- [ ] Volume mounting
- [ ] Specialized modules for popular services (PostgreSQL, Redis, MongoDB)
- [ ] Container logs streaming
- [ ] Windows support

## License

Apache-2.0

## Contributing

Contributions are welcome! Please feel free to submit issues and pull requests.

## Acknowledgments

This project is inspired by the [Testcontainers](https://testcontainers.com/) project, with implementations in multiple languages including [testcontainers-rs](https://github.com/testcontainers/testcontainers-rs) (Rust) and [testcontainers-go](https://github.com/testcontainers/testcontainers-go) (Go).
