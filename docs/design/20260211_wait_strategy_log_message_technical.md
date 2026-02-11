# Technical Design: Wait Strategy - Log Message

## Document Information

- **Date**: 2026-02-11
- **Feature**: LogMessage Wait Strategy
- **Related Steering**: `docs/steering/20260211_wait_strategy_log_message.md`
- **Status**: Design Phase

## Overview

This document provides the technical design for implementing the LogMessage wait strategy, which monitors container logs for specific messages to determine when a container is ready.

## Architecture

### 1. Type Definitions

#### 1.1 Extend WaitStrategy Enum

**File**: `types.mbt`

Add new variant to the existing `WaitStrategy` enum:

```moonbit
pub enum WaitStrategy {
  TcpPort(Int)
  Seconds(Int)
  HttpGet(String, Int)
  LogMessage(String)  // NEW: Message to wait for in logs
} derive(Show, Eq)
```

**Design Decision**: Use simple string matching (contains) rather than regex for initial implementation. This keeps the API simple and covers most use cases.

### 2. Core Implementation

#### 2.1 Log Message Waiting Function

**File**: `wait_strategy.mbt`

```moonbit
///|
/// Wait for log message to appear in container logs
async fn wait_for_log_message(
  container : Container,
  message : String,
  timeout_seconds : Int,
) -> Result[Unit, TestContainerError] noraise
```

**Algorithm**:
1. Poll every 500ms (consistent with other wait strategies)
2. Use `--tail 100` option to limit memory usage
3. Check if message appears in logs using `contains()`
4. Return success immediately when message is found
5. Return timeout error after max attempts exceeded

**Polling Strategy**:
- Interval: 500ms (same as TcpPort and HttpGet)
- Max attempts: `timeout_seconds * 1000 / 500`
- Early exit on success

**Log Retrieval Optimization**:
- Use `LogOptions::default().with_tail(100)` to get last 100 lines
- This prevents memory issues with long-running containers
- Trade-off: May miss messages if they appear and are pushed out of the tail window quickly
  - Acceptable for typical startup messages that remain visible

#### 2.2 Integration with wait_for_container

**File**: `wait_strategy.mbt`

Add new match case to `wait_for_container` function:

```moonbit
async fn wait_for_container(
  container : Container,
  strategy : WaitStrategy,
  timeout : Int,
) -> Result[Unit, TestContainerError] noraise {
  match strategy {
    // ... existing cases ...
    LogMessage(message) =>
      wait_for_log_message(container, message, timeout)
  }
}
```

### 3. Error Handling

**Error Cases**:

1. **Timeout**: Message not found within timeout period
   - Error: `WaitStrategyTimeout("Log message '\{message}' not found after \{timeout} seconds")`

2. **Docker logs command failure**: Transient errors during log retrieval
   - Behavior: Treat as "not ready yet", continue polling
   - Rationale: Container may not have started logging yet

3. **Container not running**: Container stopped before message appears
   - Error: `DockerCommandFailed("Container stopped before log message appeared")`
   - Note: This will be caught naturally by docker logs command failure

**Error Handling Pattern** (from existing code):
- Use simplified catch blocks to avoid C code generation issues
- Ignore transient errors and treat as "not ready"
- Return explicit errors only for timeout cases

### 4. Backend Compatibility

#### 4.1 Native Backend

Uses existing infrastructure:
- `exec_docker()` in `docker_native.mbt`
- `@process.collect_output_merged` under the hood
- No additional native-specific code needed

#### 4.2 JavaScript Backend

Uses existing infrastructure:
- `exec_docker()` in `docker_js.mbt`
- Node.js child_process under the hood
- No additional JS-specific code needed

**Design Decision**: No backend-specific implementation needed because log retrieval is handled uniformly through `exec_docker()`.

### 5. Performance Considerations

#### 5.1 Memory Usage

**Strategy**: Use `--tail N` to limit log size
- Default: tail 100 lines
- Sufficient for typical startup messages
- Prevents unbounded memory growth

**Trade-off Analysis**:
- ✅ Pros: Predictable memory usage, fast parsing
- ⚠️ Cons: May miss messages if output is very verbose
- 📊 Mitigation: 100 lines is sufficient for 99% of startup scenarios

#### 5.2 CPU Usage

**Polling Overhead**:
- 500ms interval = 2 checks per second
- Minimal CPU impact
- Consistent with existing wait strategies

#### 5.3 Network/Docker Overhead

**Docker Command Frequency**:
- Same as existing strategies (2 commands/second)
- Docker daemon handles this efficiently
- No special throttling needed

### 6. API Design

#### 6.1 Public API

```moonbit
// Usage example
let container = ContainerImage::new("postgres", "15-alpine")
  .with_exposed_port(5432)
  .with_wait_for(WaitStrategy::LogMessage("database system is ready to accept connections"))
  .with_wait_timeout(60)
  .start()
```

**Design Principles**:
- Consistent with existing wait strategies
- Simple string matching (no regex required)
- Fluent builder pattern

#### 6.2 Message Matching Behavior

**Match Type**: Substring match (`contains()`)

**Case Sensitivity**: Case-sensitive (exact match)

**Examples**:
- ✅ `"ready to accept connections"` matches `"database system is ready to accept connections"`
- ❌ `"Ready to accept connections"` does NOT match (different case)
- ✅ `"Started"` matches `"Started MyApplication in 2.3 seconds"`

**Rationale**:
- Substring matching is intuitive and covers most use cases
- Case-sensitive matching prevents false positives
- Users can provide specific enough strings to avoid ambiguity

### 7. Implementation Files

#### Files to Modify

1. **types.mbt**
   - Add `LogMessage(String)` to `WaitStrategy` enum
   - ~1 line change

2. **wait_strategy.mbt**
   - Add `wait_for_log_message()` function (~30 lines)
   - Add `LogMessage` case to `wait_for_container()` (~2 lines)
   - ~32 lines total

3. **wait_strategies_wbtest.mbt**
   - Add test cases (~100-150 lines)

4. **README.mbt.md** (if exists)
   - Add usage examples and documentation (~20-30 lines)

#### Files NOT Modified

- `docker_native.mbt` - Uses existing `exec_docker()`
- `docker_js.mbt` - Uses existing `exec_docker()`
- `logs.mbt` - Uses existing log functionality
- No new files needed

### 8. Testing Strategy

#### 8.1 Unit Tests

**Test Cases** (in `wait_strategies_wbtest.mbt`):

1. **PostgreSQL startup message**
   ```moonbit
   async test "wait strategy log message postgres"
   ```
   - Wait for: `"database system is ready to accept connections"`
   - Expected: Success within timeout

2. **Nginx startup message**
   ```moonbit
   async test "wait strategy log message nginx"
   ```
   - Wait for: `"start worker processes"`
   - Expected: Success within timeout

3. **Timeout scenario**
   ```moonbit
   async test "wait strategy log message timeout"
   ```
   - Wait for: Message that never appears
   - Expected: Timeout error with descriptive message

4. **Fast startup (Redis)**
   ```moonbit
   async test "wait strategy log message redis"
   ```
   - Wait for: `"Ready to accept connections"`
   - Expected: Success quickly (< 5 seconds)

#### 8.2 Integration Testing

**Real Container Tests**:
- PostgreSQL 15-alpine
- Nginx 1.25-alpine
- Redis 7.2.4

**Success Criteria**:
- All tests pass on both native and JavaScript backends
- No regression in existing wait strategy tests
- Memory usage remains bounded
- Timeout handling works correctly

### 9. Documentation

#### 9.1 Code Documentation

Each function includes:
- Purpose description
- Parameter descriptions
- Return value description
- Example usage (in tests)

#### 9.2 README Updates

Add section:
```markdown
### Wait for Log Message

Wait for a specific message to appear in container logs:

\`\`\`moonbit
let db = ContainerImage::new("postgres", "15-alpine")
  .with_exposed_port(5432)
  .with_env_var("POSTGRES_PASSWORD", "password")
  .with_wait_for(WaitStrategy::LogMessage("ready to accept connections"))
  .start()
\`\`\`

This is useful for databases and services that log when they're ready.
```

### 10. Migration Path

**Backward Compatibility**: ✅ Fully compatible
- Existing code continues to work unchanged
- New variant is additive only
- No breaking changes to existing APIs

**Adoption Path**:
1. Current users can continue using existing strategies
2. New users can adopt LogMessage for more reliable readiness detection
3. Existing tests remain valid

### 11. Future Enhancements (Out of Scope)

1. **Regex matching**: `LogMessageRegex(String)` variant
2. **Multiple message matching**: AND/OR conditions
3. **Log level filtering**: Only check ERROR or INFO logs
4. **Streaming optimization**: True streaming instead of polling
5. **Custom timeout per poll**: Different interval for different messages

### 12. Implementation Checklist

- [ ] Add `LogMessage(String)` to WaitStrategy enum
- [ ] Implement `wait_for_log_message()` function
- [ ] Integrate with `wait_for_container()`
- [ ] Write PostgreSQL test
- [ ] Write Nginx test
- [ ] Write timeout test
- [ ] Write Redis test
- [ ] Update README with examples
- [ ] Run `moon fmt` and `moon info`
- [ ] Verify all tests pass on native backend
- [ ] Verify all tests pass on JavaScript backend
- [ ] Review generated `.mbti` changes

### 13. Risk Mitigation

| Risk | Impact | Mitigation |
|------|--------|------------|
| Message appears before first check | Medium | Use small initial delay (500ms) |
| Very verbose container logs | Low | Use `--tail 100` to limit size |
| Ambiguous message matches | Low | Document best practices for specific messages |
| Performance degradation | Low | Use same polling interval as existing strategies |

### 14. Success Metrics

- ✅ All new tests pass (4 tests)
- ✅ All existing tests continue to pass
- ✅ Works on both native and JavaScript backends
- ✅ No memory leaks or unbounded growth
- ✅ Timeout handling works correctly
- ✅ Documentation is clear and complete

## References

- Steering Document: `docs/steering/20260211_wait_strategy_log_message.md`
- testcontainers-java: `WaitForLogMessageStrategy`
- testcontainers-go: `Wait.ForLog()`
- testcontainers-rs: `WaitFor::message_on_stdout()`
- Existing wait strategies: `wait_strategy.mbt`
