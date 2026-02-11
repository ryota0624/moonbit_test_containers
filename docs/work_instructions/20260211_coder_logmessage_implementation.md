# Implementation Instructions: LogMessage Wait Strategy

## Role: @coder

## Task Overview

Implement the LogMessage wait strategy based on the technical and test designs.

## Design Documents

- **Technical Design**: `/Users/ryota.suzuki/git/moonbit_test_containers/docs/design/20260211_wait_strategy_log_message_technical.md`
- **Test Design**: `/Users/ryota.suzuki/git/moonbit_test_containers/docs/design/20260211_wait_strategy_log_message_test.md`
- **Steering Document**: `/Users/ryota.suzuki/git/moonbit_test_containers/docs/steering/20260211_wait_strategy_log_message.md`

## Implementation Steps

### Step 1: Modify types.mbt

Add `LogMessage(String)` variant to `WaitStrategy` enum:

```moonbit
pub enum WaitStrategy {
  TcpPort(Int)
  Seconds(Int)
  HttpGet(String, Int)
  LogMessage(String)  // Add this line
} derive(Show, Eq)
```

**File**: `/Users/ryota.suzuki/git/moonbit_test_containers/types.mbt`

### Step 2: Implement wait_for_log_message in wait_strategy.mbt

Add the following function to `wait_strategy.mbt`:

```moonbit
///|
/// Wait for log message to appear in container logs with timeout
async fn wait_for_log_message(
  container : Container,
  message : String,
  timeout_seconds : Int,
) -> Result[Unit, TestContainerError] noraise {
  // Poll every 500ms (consistent with other wait strategies)
  let poll_interval_ms = 500
  let max_attempts = timeout_seconds * 1000 / poll_interval_ms

  for attempt = 0; attempt < max_attempts; attempt = attempt + 1 {
    // Get recent logs (last 100 lines to limit memory usage)
    let log_options = LogOptions::default().with_tail(100)
    let logs_result = container.get_logs_with_options(log_options) catch {
      // Ignore errors (container may not be ready yet)
      _ => Err(DockerCommandFailed("Log retrieval failed"))
    }

    // Check if message is in logs
    match logs_result {
      Ok(logs) => {
        if logs.contains(message) {
          return Ok(())
        }
      }
      Err(_) => ()  // Ignore and continue polling
    }

    // Sleep between attempts
    @async.sleep(poll_interval_ms) catch {
      _ => ()
    }
  } nobreak {
    Err(
      WaitStrategyTimeout(
        "Log message '\{message}' not found after \{timeout_seconds} seconds",
      ),
    )
  }
}
```

**File**: `/Users/ryota.suzuki/git/moonbit_test_containers/wait_strategy.mbt`

**Important Notes**:
- Use simplified error handling (catch blocks) to avoid C code generation issues
- Poll every 500ms for consistency with other strategies
- Use `--tail 100` to prevent memory issues
- Return immediately when message is found

### Step 3: Integrate with wait_for_container

Add the LogMessage case to the `wait_for_container` function:

```moonbit
async fn wait_for_container(
  container : Container,
  strategy : WaitStrategy,
  timeout : Int,
) -> Result[Unit, TestContainerError] noraise {
  match strategy {
    Seconds(seconds) => {
      // ... existing code ...
    }
    TcpPort(container_port) => {
      // ... existing code ...
    }
    HttpGet(path, expected_status) => {
      // ... existing code ...
    }
    LogMessage(message) =>
      // Add this case
      wait_for_log_message(container, message, timeout)
  }
}
```

**File**: `/Users/ryota.suzuki/git/moonbit_test_containers/wait_strategy.mbt`

### Step 4: Add Tests to wait_strategies_wbtest.mbt

Add the following test cases:

#### Test 1: PostgreSQL

```moonbit
///|
/// Test log message wait strategy with PostgreSQL
async test "wait strategy log message postgres" {
  // Start PostgreSQL with log message wait
  let container = ContainerImage::new("postgres", "15-alpine")
    .with_exposed_port(5432)
    .with_env_var("POSTGRES_PASSWORD", "test_password")
    .with_wait_for(WaitStrategy::LogMessage("database system is ready to accept connections"))
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
```

#### Test 2: Nginx

```moonbit
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
```

#### Test 3: Redis

```moonbit
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
```

#### Test 4: Timeout

```moonbit
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
        WaitStrategyTimeout(_) => println("Correct error type: WaitStrategyTimeout")
        _ => abort("Expected WaitStrategyTimeout but got different error")
      }
    }
  }
}
```

**File**: `/Users/ryota.suzuki/git/moonbit_test_containers/wait_strategies_wbtest.mbt`

### Step 5: Format and Check

Run the following commands:

```bash
# Format code
moon fmt

# Update interface
moon info

# Check for errors
moon check

# Run tests
moon test --native

# Update snapshots if needed
moon test --update
```

### Step 6: Verify Tests Pass

Ensure all tests pass:

```bash
# Run all tests
moon test --native

# Run specific tests
moon test --native --filter "wait strategy log message"
```

## Expected Results

After implementation:

1. **types.mbt**: `WaitStrategy` enum has 4 variants
2. **wait_strategy.mbt**:
   - New function `wait_for_log_message` (~30 lines)
   - Updated `wait_for_container` with LogMessage case
3. **wait_strategies_wbtest.mbt**: 4 new test cases (~150 lines)
4. **All tests pass** on native backend
5. **No regressions** in existing tests

## Quality Checklist

- [ ] Code follows MoonBit block style (`///|` separators)
- [ ] Functions have doc comments
- [ ] Error handling uses simplified catch blocks
- [ ] Poll interval is 500ms (consistent with other strategies)
- [ ] Uses `LogOptions::default().with_tail(100)` for memory efficiency
- [ ] Tests include cleanup in all code paths
- [ ] Tests use `match` for error handling
- [ ] All tests pass on native backend
- [ ] `moon fmt` produces no changes
- [ ] `moon check` reports no errors
- [ ] `.mbti` changes are as expected (new enum variant visible)

## Notes for Implementation

1. **Error Handling Pattern**: Follow existing pattern in `wait_strategy.mbt`
   - Use `catch { _ => ... }` to avoid C code generation issues
   - Treat transient errors as "not ready yet"

2. **Memory Efficiency**: Always use `with_tail(100)` to prevent unbounded log size

3. **Consistency**: Use same polling interval (500ms) as TcpPort and HttpGet

4. **Test Cleanup**: Always clean up containers, even on errors (use proper `match` blocks)

## Files to Modify

1. `/Users/ryota.suzuki/git/moonbit_test_containers/types.mbt`
2. `/Users/ryota.suzuki/git/moonbit_test_containers/wait_strategy.mbt`
3. `/Users/ryota.suzuki/git/moonbit_test_containers/wait_strategies_wbtest.mbt`

## Success Criteria

- All new tests pass consistently
- All existing tests continue to pass
- Code is properly formatted
- Interface file (.mbti) shows expected changes
- No compiler warnings or errors

## Next Steps

After implementation is complete, the code will be reviewed by @reviewer.
