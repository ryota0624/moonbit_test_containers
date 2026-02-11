# Test Design: Wait Strategy - Log Message

## Document Information

- **Date**: 2026-02-11
- **Feature**: LogMessage Wait Strategy Test Strategy
- **Related Documents**:
  - Technical Design: `docs/design/20260211_wait_strategy_log_message_technical.md`
  - Steering: `docs/steering/20260211_wait_strategy_log_message.md`
- **Status**: Test Design Phase

## Test Strategy Overview

This document defines the comprehensive test strategy for the LogMessage wait strategy implementation. The strategy follows MoonBit testing conventions and ensures reliability across both native and JavaScript backends.

## Test Categories

### 1. Functional Tests

#### 1.1 Happy Path Tests

**Test: PostgreSQL Ready Message**
- **File**: `wait_strategies_wbtest.mbt`
- **Test Name**: `"wait strategy log message postgres"`
- **Container**: `postgres:15-alpine`
- **Configuration**:
  - Exposed port: 5432
  - Environment: `POSTGRES_PASSWORD=test_password`
  - Wait message: `"database system is ready to accept connections"`
  - Timeout: 60 seconds
- **Expected Behavior**:
  - Container starts successfully
  - Message is found in logs
  - Wait completes within 30 seconds (typically ~10-15 seconds)
  - Port is accessible after wait completes
- **Verification Steps**:
  1. Start container with LogMessage wait strategy
  2. Verify no errors during startup
  3. Verify container ID is returned
  4. Verify host port is mapped
  5. Clean up container

**Test: Nginx Ready Message**
- **File**: `wait_strategies_wbtest.mbt`
- **Test Name**: `"wait strategy log message nginx"`
- **Container**: `nginx:1.25-alpine`
- **Configuration**:
  - Exposed port: 80
  - Wait message: `"start worker processes"`
  - Timeout: 30 seconds
- **Expected Behavior**:
  - Container starts successfully
  - Nginx worker processes start
  - Message is detected quickly (< 5 seconds)
- **Verification Steps**:
  1. Start container with LogMessage wait strategy
  2. Verify startup completes
  3. Verify HTTP endpoint is accessible
  4. Clean up container

**Test: Redis Ready Message**
- **File**: `wait_strategies_wbtest.mbt`
- **Test Name**: `"wait strategy log message redis"`
- **Container**: `redis:7.2.4`
- **Configuration**:
  - Exposed port: 6379
  - Wait message: `"Ready to accept connections"`
  - Timeout: 30 seconds
- **Expected Behavior**:
  - Very fast startup (< 3 seconds typically)
  - Message appears in logs
  - Container is ready for connections

#### 1.2 Edge Case Tests

**Test: Message Already in Logs**
- **Scenario**: Message appeared before first poll
- **Expected**: Should detect message on first check
- **Implementation**: Use Redis (very fast startup)

**Test: Message with Special Characters**
- **Scenario**: Wait for message containing special characters
- **Container**: Custom container with known log output
- **Message**: `"Server started on port 8080: ready!"`
- **Expected**: String matching handles special characters correctly

**Test: Partial Message Match**
- **Scenario**: Verify substring matching works
- **Container**: PostgreSQL
- **Message**: `"ready to accept"`
- **Expected**: Should match full message `"database system is ready to accept connections"`

### 2. Error Handling Tests

#### 2.1 Timeout Tests

**Test: Message Never Appears - Timeout**
- **File**: `wait_strategies_wbtest.mbt`
- **Test Name**: `"wait strategy log message timeout"`
- **Container**: `alpine:3.19`
- **Configuration**:
  - Command: `["sh", "-c", "echo 'Starting...'; sleep 20; echo 'Done'"]`
  - Wait message: `"NonexistentMessage"`
  - Timeout: 5 seconds
- **Expected Behavior**:
  - Container starts but message is never found
  - Error: `WaitStrategyTimeout` with descriptive message
  - Error message includes: searched message and timeout duration
- **Verification Steps**:
  1. Start container with impossible message
  2. Verify `Err` result is returned
  3. Verify error type is `WaitStrategyTimeout`
  4. Verify error message is descriptive
  5. Clean up container

**Test: Container Stops Before Message**
- **Scenario**: Container exits before logging expected message
- **Container**: `alpine:3.19`
- **Command**: `["echo", "Starting"]` (exits immediately)
- **Wait message**: `"Ready"`
- **Expected**: Timeout or DockerCommandFailed error

#### 2.2 Invalid Configuration Tests

**Test: Empty Message String**
- **Scenario**: `LogMessage("")`
- **Expected**: Should still work (matches any log output)
- **Note**: Document this behavior as "not recommended"

### 3. Performance Tests

#### 3.1 Timing Tests

**Test: Fast Startup Detection**
- **Container**: Redis (very fast)
- **Expected**: Message detected within 3 seconds
- **Measure**: Time from start to ready

**Test: Medium Startup Detection**
- **Container**: Nginx
- **Expected**: Message detected within 5 seconds

**Test: Slow Startup Detection**
- **Container**: PostgreSQL
- **Expected**: Message detected within 15 seconds

#### 3.2 Resource Usage Tests

**Test: Memory Usage with Long-Running Container**
- **Scenario**: Container running for extended period
- **Implementation**: Start container, wait for message, keep container running
- **Verification**: No memory leaks (manual verification during development)
- **Note**: `--tail 100` should prevent unbounded memory growth

### 4. Integration Tests

#### 4.1 Combined Wait Strategies

**Test: TcpPort + LogMessage**
- **Scenario**: Use TcpPort first, verify with LogMessage
- **Container**: PostgreSQL
- **Strategy 1**: `TcpPort(5432)` - port is open
- **Strategy 2**: `LogMessage("ready to accept")` - service is truly ready
- **Expected**: LogMessage is more reliable indicator

**Note**: This is a conceptual test showing why LogMessage is valuable. Actual implementation only supports one wait strategy per container.

#### 4.2 Real-World Use Cases

**Test: PostgreSQL Full Workflow**
- **Steps**:
  1. Start PostgreSQL with LogMessage wait
  2. Connect to database (verify connection succeeds)
  3. Execute simple query
  4. Stop container
- **Expected**: Connection succeeds immediately without retry logic

### 5. Backend Compatibility Tests

#### 5.1 Native Backend Tests

**Execution**: `moon test --native`

**Validation**:
- All tests pass on native backend
- No C code generation issues
- Error handling works correctly

#### 5.2 JavaScript Backend Tests

**Execution**: `moon test --target js`

**Validation**:
- All tests pass on JavaScript backend
- Node.js child_process integration works
- Async behavior is consistent with native

### 6. Regression Tests

#### 6.1 Existing Wait Strategies

**Validation**:
- All existing wait strategy tests continue to pass
- No performance degradation
- No behavior changes

**Tests to Verify**:
- `"wait strategy tcp port"` - Still passes
- `"wait strategy seconds"` - Still passes
- `"wait strategy http get"` - Still passes
- `"wait strategy http get custom path"` - Still passes
- `"wait strategy http get no ports"` - Still passes

### 7. Test Implementation Details

#### 7.1 Test Structure (MoonBit Style)

```moonbit
///|
/// Test PostgreSQL log message wait strategy
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
        Ok(_) => println("PostgreSQL container cleaned up")
        Err(e) => {
          println("Cleanup failed: \{e.to_string()}")
          abort("Cleanup failed")
        }
      }
    }
    Err(e) => {
      println("Failed: \{e.to_string()}")
      abort("Log message wait strategy failed")
    }
  }
}
```

#### 7.2 Snapshot Testing

**When to Use**:
- For log output verification (use `inspect!`)
- For error message validation
- For structured data comparison

**Update Command**: `moon test --update`

#### 7.3 Assertion Style

**Prefer**: `inspect!` for most tests (snapshot testing)

**Use `abort()`**: For critical failures that should stop test execution

**Example**:
```moonbit
match result {
  Ok(_) => inspect!(true, content="success")
  Err(e) => abort("Unexpected error: \{e.to_string()}")
}
```

### 8. Test Data and Fixtures

#### 8.1 Container Images

**PostgreSQL**:
- Image: `postgres:15-alpine`
- Ready message: `"database system is ready to accept connections"`
- Typical startup: 10-15 seconds

**Nginx**:
- Image: `nginx:1.25-alpine`
- Ready message: `"start worker processes"`
- Typical startup: 2-3 seconds

**Redis**:
- Image: `redis:7.2.4`
- Ready message: `"Ready to accept connections"`
- Typical startup: 1-2 seconds

**Alpine** (for error cases):
- Image: `alpine:3.19`
- Used for timeout and error scenarios

#### 8.2 Test Messages

**Valid Messages** (should be found):
- `"database system is ready to accept connections"` - PostgreSQL
- `"ready to accept connections"` - PostgreSQL (substring)
- `"start worker processes"` - Nginx
- `"Ready to accept connections"` - Redis

**Invalid Messages** (should timeout):
- `"NonexistentMessage"`
- `"This Will Never Appear"`

### 9. Test Execution Plan

#### 9.1 Local Development

```bash
# Run all tests
moon test --native

# Run specific test
moon test --native --filter "wait strategy log message"

# Update snapshots
moon test --update

# Check coverage
moon coverage analyze > uncovered.log
```

#### 9.2 CI/CD Validation

**Native Backend**:
```bash
moon test --native
moon fmt --check
moon check
```

**JavaScript Backend**:
```bash
moon test --target js
```

### 10. Test Maintenance

#### 10.1 Container Image Updates

**Strategy**: Pin versions to ensure reproducibility
- PostgreSQL: `15-alpine` (not `latest`)
- Nginx: `1.25-alpine`
- Redis: `7.2.4`

**Update Process**: When updating images, verify log messages haven't changed

#### 10.2 Flaky Test Prevention

**Strategies**:
1. Use generous timeouts (60s for database containers)
2. Don't rely on exact timing
3. Use specific, unique log messages
4. Clean up containers in all code paths (use `match` properly)

### 11. Success Criteria

- [ ] All 4 new tests pass consistently
- [ ] All 5 existing tests continue to pass
- [ ] Tests pass on both native and JavaScript backends
- [ ] No flaky tests (run 10 times, all pass)
- [ ] Code coverage includes new code paths
- [ ] Error messages are descriptive and helpful
- [ ] Test execution time is reasonable (< 2 minutes total)

### 12. Test Documentation

#### 12.1 Inline Documentation

Each test includes:
```moonbit
///|
/// Test description
///
/// Verifies that [specific behavior]
///
/// Container: [image:tag]
/// Expected: [expected outcome]
async test "test name" {
  // Test implementation
}
```

#### 12.2 README Examples

Add practical examples showing real-world usage:

```markdown
### Testing with PostgreSQL

Wait for PostgreSQL to be ready before running tests:

\`\`\`moonbit
async test "postgres integration" {
  let db = ContainerImage::new("postgres", "15-alpine")
    .with_env_var("POSTGRES_PASSWORD", "test123")
    .with_exposed_port(5432)
    .with_wait_for(WaitStrategy::LogMessage("ready to accept connections"))
    .start()

  match db {
    Ok(container) => {
      // Database is ready, run your tests
      let _ = container.cleanup()
    }
    Err(e) => abort("Database failed to start")
  }
}
\`\`\`
```

## Test Execution Timeline

1. **Unit Tests**: Run during development (< 30 seconds)
2. **Integration Tests**: Run before commit (1-2 minutes)
3. **Full Test Suite**: Run in CI/CD (2-3 minutes)
4. **Regression Tests**: Run before release

## References

- MoonBit Testing Guide: https://docs.moonbitlang.com
- Technical Design: `docs/design/20260211_wait_strategy_log_message_technical.md`
- Existing Tests: `wait_strategies_wbtest.mbt`
- MoonBit Snapshot Testing: Use `inspect!` macro
