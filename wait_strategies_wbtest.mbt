// Integration tests for wait strategies
// Note: These tests require Docker to be installed and running

///|
/// Test TCP port wait strategy
async test "wait strategy tcp port" {
  // Start Redis with TCP port wait
  let container = ContainerImage::new("redis", "7.2.4")
    .with_exposed_port(6379)
    .with_wait_for(WaitStrategy::TcpPort(6379))
    .with_wait_timeout(30)
    .start()
  match container {
    Ok(c) => {
      println("Redis started with TCP port wait strategy")
      println("Container ID: \{c.get_id()}")

      // Verify port is accessible
      match c.get_host_port(6379) {
        Some(port) => println("Redis accessible on port: \{port}")
        None => abort("Port not mapped")
      }

      // Cleanup
      let _ = c.cleanup()
    }
    Err(e) => {
      println("Failed: \{e.to_string()}")
      abort("TCP port wait strategy failed")
    }
  }
}

///|
/// Test simple delay wait strategy
async test "wait strategy seconds" {
  // Start Alpine with simple delay
  let container = ContainerImage::new("alpine", "3.19")
    .with_cmd(["sleep", "10"])
    .with_wait_for(WaitStrategy::Seconds(2))
    .start()
  match container {
    Ok(c) => {
      println("Alpine started with delay wait strategy")
      println("Container ID: \{c.get_id()}")

      // Cleanup
      let _ = c.cleanup()
    }
    Err(e) => {
      println("Failed: \{e.to_string()}")
      abort("Delay wait strategy failed")
    }
  }
}

///|
/// Test HTTP endpoint wait strategy with nginx
async test "wait strategy http get" {
  // Start nginx with HTTP wait strategy
  let container = ContainerImage::new("nginx", "1.25-alpine")
    .with_exposed_port(80)
    .with_wait_for(WaitStrategy::HttpGet("/", 200))
    .with_wait_timeout(30)
    .start()
  match container {
    Ok(c) => {
      println("Nginx started with HTTP wait strategy")
      println("Container ID: \{c.get_id()}")

      // Verify port is accessible
      match c.get_host_port(80) {
        Some(port) => println("Nginx accessible on port: \{port}")
        None => abort("Port not mapped")
      }

      // Cleanup
      match c.cleanup() {
        Ok(_) => println("Nginx container cleaned up successfully")
        Err(e) => {
          println("Cleanup failed: \{e.to_string()}")
          abort("Cleanup failed")
        }
      }
    }
    Err(e) => {
      println("Failed: \{e.to_string()}")
      abort("HTTP wait strategy failed")
    }
  }
}

///|
/// Test HTTP endpoint wait strategy with custom path
async test "wait strategy http get custom path" {
  // Start nginx and wait for a specific path
  // Note: nginx default config serves "/" but may return 404 for other paths
  // We'll test with "/" and expect 200
  let container = ContainerImage::new("nginx", "1.25-alpine")
    .with_exposed_port(80)
    .with_wait_for(WaitStrategy::HttpGet("/index.html", 200))
    .with_wait_timeout(30)
    .start()
  match container {
    Ok(c) => {
      println("Nginx started with HTTP wait strategy (custom path)")
      println("Container ID: \{c.get_id()}")

      // Cleanup
      let _ = c.cleanup()
    }
    Err(e) => {
      println("Failed: \{e.to_string()}")
      abort("HTTP wait strategy with custom path failed")
    }
  }
}

///|
/// Test HTTP endpoint error when no ports exposed
async test "wait strategy http get no ports" {
  // Try to use HTTP wait without exposing ports
  let container = ContainerImage::new("alpine", "3.19")
    .with_cmd(["sleep", "10"])
    .with_wait_for(WaitStrategy::HttpGet("/", 200))
    .with_wait_timeout(5)
    .start()
  match container {
    Ok(_) => abort("Expected error but got success")
    Err(e) => println("Got expected error: \{e.to_string()}")
    // Test passed - we expected a configuration error
  }
}

///|
/// Test log message wait strategy with PostgreSQL
async test "wait strategy log message postgres" {
  // Start PostgreSQL with log message wait
  let container = ContainerImage::new("postgres", "15-alpine")
    .with_exposed_port(5432)
    .with_env_var("POSTGRES_PASSWORD", "test_password")
    .with_wait_for(
      WaitStrategy::LogMessage("database system is ready to accept connections"),
    )
    .with_wait_timeout(60)
    .start()

  match container {
    Ok(c) => {
      println("PostgreSQL started with log message wait strategy")
      println("Container ID: \{c.get_id()}")

      // Verify port is accessible
      match c.get_host_port(5432) {
        Some(port) => println("PostgreSQL accessible on port: \{port}")
        None => abort("Port not mapped")
      }

      // Cleanup
      match c.cleanup() {
        Ok(_) => println("PostgreSQL container cleaned up successfully")
        Err(e) => {
          println("Cleanup failed: \{e.to_string()}")
          abort("Cleanup failed")
        }
      }
    }
    Err(e) => {
      println("Failed: \{e.to_string()}")
      abort("Log message wait strategy failed for PostgreSQL")
    }
  }
}

///|
/// Test log message wait strategy with Nginx
async test "wait strategy log message nginx" {
  // Start Nginx with log message wait
  let container = ContainerImage::new("nginx", "1.25-alpine")
    .with_exposed_port(80)
    .with_wait_for(WaitStrategy::LogMessage("start worker processes"))
    .with_wait_timeout(30)
    .start()

  match container {
    Ok(c) => {
      println("Nginx started with log message wait strategy")
      println("Container ID: \{c.get_id()}")

      // Verify port is accessible
      match c.get_host_port(80) {
        Some(port) => println("Nginx accessible on port: \{port}")
        None => abort("Port not mapped")
      }

      // Cleanup
      match c.cleanup() {
        Ok(_) => println("Nginx container cleaned up successfully")
        Err(e) => {
          println("Cleanup failed: \{e.to_string()}")
          abort("Cleanup failed")
        }
      }
    }
    Err(e) => {
      println("Failed: \{e.to_string()}")
      abort("Log message wait strategy failed for Nginx")
    }
  }
}

///|
/// Test log message wait strategy with Redis (fast startup)
async test "wait strategy log message redis" {
  // Start Redis with log message wait
  let container = ContainerImage::new("redis", "7.2.4")
    .with_exposed_port(6379)
    .with_wait_for(WaitStrategy::LogMessage("Ready to accept connections"))
    .with_wait_timeout(30)
    .start()

  match container {
    Ok(c) => {
      println("Redis started with log message wait strategy")
      println("Container ID: \{c.get_id()}")

      // Verify port is accessible
      match c.get_host_port(6379) {
        Some(port) => println("Redis accessible on port: \{port}")
        None => abort("Port not mapped")
      }

      // Cleanup
      let _ = c.cleanup()
    }
    Err(e) => {
      println("Failed: \{e.to_string()}")
      abort("Log message wait strategy failed for Redis")
    }
  }
}

///|
/// Test log message wait strategy timeout
async test "wait strategy log message timeout" {
  // Try to wait for a message that never appears
  let container = ContainerImage::new("alpine", "3.19")
    .with_cmd(["sh", "-c", "echo 'Starting...'; sleep 20; echo 'Done'"])
    .with_wait_for(WaitStrategy::LogMessage("NonexistentMessage"))
    .with_wait_timeout(5)
    .start()

  match container {
    Ok(c) => {
      // Should not succeed
      let _ = c.cleanup()
      abort("Expected timeout error but got success")
    }
    Err(e) => {
      // Expected to fail with timeout
      println("Got expected timeout error: \{e.to_string()}")
      // Verify it's the right error type
      match e {
        WaitStrategyTimeout(_) =>
          println("Correct error type: WaitStrategyTimeout")
        _ => abort("Expected WaitStrategyTimeout but got different error")
      }
    }
  }
}
