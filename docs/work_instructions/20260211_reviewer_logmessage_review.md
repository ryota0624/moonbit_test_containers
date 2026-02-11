# Review Instructions: LogMessage Wait Strategy

## Role: @reviewer

## Task Overview

Review the implementation of LogMessage wait strategy and verify all quality criteria are met.

## Implementation Summary

The following files have been modified to add LogMessage wait strategy support:

1. **types.mbt**: Added `LogMessage(String)` variant to `WaitStrategy` enum
2. **wait_strategy.mbt**: Implemented `wait_for_log_message()` function and integrated with `wait_for_container()`
3. **wait_strategies_wbtest.mbt**: Added 4 new test cases

## Design Documents

- **Technical Design**: `/Users/ryota.suzuki/git/moonbit_test_containers/docs/design/20260211_wait_strategy_log_message_technical.md`
- **Test Design**: `/Users/ryota.suzuki/git/moonbit_test_containers/docs/design/20260211_wait_strategy_log_message_test.md`
- **Steering Document**: `/Users/ryota.suzuki/git/moonbit_test_containers/docs/steering/20260211_wait_strategy_log_message.md`

## Review Checklist

### 1. Code Quality

- [ ] **Code follows MoonBit conventions**
  - Block-style with `///|` separators
  - Proper doc comments for functions
  - Consistent naming conventions

- [ ] **Error handling is correct**
  - Simplified catch blocks (avoiding C code generation issues)
  - Transient errors treated as "not ready yet"
  - Timeout errors are descriptive

- [ ] **Implementation matches technical design**
  - 500ms polling interval
  - Uses `LogOptions::default().with_tail(100)`
  - Substring matching with `contains()`
  - Returns immediately when message is found

### 2. Type Definitions (types.mbt)

Review `/Users/ryota.suzuki/git/moonbit_test_containers/types.mbt`:

- [ ] `WaitStrategy::LogMessage(String)` is correctly added
- [ ] Maintains `derive(Show, Eq)` traits
- [ ] Documentation comment is clear
- [ ] No breaking changes to existing types

**Expected Change**:
```moonbit
pub enum WaitStrategy {
  TcpPort(Int)
  Seconds(Int)
  HttpGet(String, Int)
  LogMessage(String)  // NEW
} derive(Show, Eq)
```

### 3. Wait Strategy Implementation (wait_strategy.mbt)

Review `/Users/ryota.suzuki/git/moonbit_test_containers/wait_strategy.mbt`:

#### 3.1 wait_for_log_message Function

- [ ] Function signature is correct
  - Parameters: `container: Container`, `message: String`, `timeout_seconds: Int`
  - Return type: `Result[Unit, TestContainerError] noraise`
  - Marked as `async`

- [ ] Polling logic is correct
  - Poll interval: 500ms
  - Max attempts calculation: `timeout_seconds * 1000 / 500`
  - Uses for loop with `nobreak` pattern

- [ ] Log retrieval
  - Uses `LogOptions::default().with_tail(100)`
  - Calls `container.get_logs_with_options(log_options)`
  - Errors are caught and ignored (container may not be ready)

- [ ] Message detection
  - Uses `logs.contains(message)` for substring matching
  - Returns `Ok(())` immediately when found
  - Continues polling if not found

- [ ] Timeout handling
  - Returns `WaitStrategyTimeout` error in nobreak block
  - Error message includes searched message and timeout duration

- [ ] Sleep between attempts
  - Uses `@async.sleep(poll_interval_ms)`
  - Errors are caught and ignored

#### 3.2 wait_for_container Integration

- [ ] `LogMessage(message)` case is added
- [ ] Calls `wait_for_log_message(container, message, timeout)`
- [ ] No changes to existing cases (Seconds, TcpPort, HttpGet)

**Expected Addition**:
```moonbit
LogMessage(message) =>
  wait_for_log_message(container, message, timeout)
```

### 4. Test Cases (wait_strategies_wbtest.mbt)

Review `/Users/ryota.suzuki/git/moonbit_test_containers/wait_strategies_wbtest.mbt`:

#### 4.1 Test: PostgreSQL

- [ ] Test name: `"wait strategy log message postgres"`
- [ ] Uses `postgres:15-alpine` image
- [ ] Environment variable: `POSTGRES_PASSWORD=test_password`
- [ ] Wait message: `"database system is ready to accept connections"`
- [ ] Timeout: 60 seconds
- [ ] Port 5432 is exposed and verified
- [ ] Cleanup is performed in all code paths

#### 4.2 Test: Nginx

- [ ] Test name: `"wait strategy log message nginx"`
- [ ] Uses `nginx:1.25-alpine` image
- [ ] Wait message: `"start worker processes"`
- [ ] Timeout: 30 seconds
- [ ] Port 80 is exposed and verified
- [ ] Cleanup is performed

#### 4.3 Test: Redis

- [ ] Test name: `"wait strategy log message redis"`
- [ ] Uses `redis:7.2.4` image
- [ ] Wait message: `"Ready to accept connections"`
- [ ] Timeout: 30 seconds
- [ ] Port 6379 is exposed and verified
- [ ] Cleanup is performed

#### 4.4 Test: Timeout

- [ ] Test name: `"wait strategy log message timeout"`
- [ ] Uses `alpine:3.19` image
- [ ] Custom command that doesn't output expected message
- [ ] Wait message: `"NonexistentMessage"`
- [ ] Short timeout: 5 seconds
- [ ] Expects `Err` result
- [ ] Verifies error type is `WaitStrategyTimeout`

### 5. Consistency with Existing Code

- [ ] **Polling interval**: 500ms (same as TcpPort and HttpGet)
- [ ] **Error handling pattern**: Matches existing strategies
- [ ] **Function naming**: Follows `wait_for_*` convention
- [ ] **Code style**: Matches existing wait strategy implementations
- [ ] **Test structure**: Follows existing test patterns

### 6. No Regressions

- [ ] Existing test cases remain unchanged
  - `"wait strategy tcp port"`
  - `"wait strategy seconds"`
  - `"wait strategy http get"`
  - `"wait strategy http get custom path"`
  - `"wait strategy http get no ports"`

### 7. Commands to Run

Execute the following commands to verify the implementation:

```bash
# Format code
moon fmt

# Update interface
moon info

# Check for errors
moon check

# Run tests (native backend)
moon test --native

# Optional: Run tests on JavaScript backend
moon test --target js

# Optional: Update snapshots if needed
moon test --update
```

### 8. Expected Interface Changes

After running `moon info`, verify that `pkg.generated.mbti` shows:

```moonbit
pub enum WaitStrategy {
  TcpPort(Int)
  Seconds(Int)
  HttpGet(String, Int)
  LogMessage(String)  // NEW: This should appear
}
```

### 9. Code Review Points

#### 9.1 Correctness

- [ ] Logic correctly implements polling with timeout
- [ ] Message detection works with substring matching
- [ ] Memory is bounded (tail 100 lines)
- [ ] No infinite loops or resource leaks

#### 9.2 Readability

- [ ] Code is easy to understand
- [ ] Function names are descriptive
- [ ] Comments explain non-obvious behavior
- [ ] Test names clearly describe what they test

#### 9.3 Maintainability

- [ ] Code follows project conventions
- [ ] No code duplication
- [ ] Easy to add similar functionality in the future
- [ ] Error messages are helpful for debugging

#### 9.4 Performance

- [ ] Polling interval is reasonable (500ms)
- [ ] Log retrieval is efficient (tail 100)
- [ ] No unnecessary operations in tight loops
- [ ] Early exit when message is found

#### 9.5 Security

- [ ] No command injection vulnerabilities
- [ ] Message string is safely used (no shell escaping issues)
- [ ] Container ID is used safely

### 10. Test Execution Verification

When tests are run, verify:

- [ ] All 4 new tests pass consistently
- [ ] All 5 existing tests continue to pass
- [ ] No flaky tests (run multiple times if needed)
- [ ] No memory leaks or resource warnings
- [ ] Reasonable execution time (< 2 minutes for all tests)

### 11. Documentation Completeness

- [ ] Function has doc comment with `///|`
- [ ] Parameters are explained in design documents
- [ ] Test cases have descriptive comments
- [ ] Error messages are clear

### 12. Integration Testing

Verify the feature works in real scenarios:

- [ ] PostgreSQL container becomes ready when message appears
- [ ] Timeout occurs when message doesn't appear
- [ ] Works correctly with containers that start quickly (Redis)
- [ ] Works correctly with containers that start slowly (PostgreSQL)

### 13. Final Approval Criteria

All of the following must be true:

- [ ] All checklist items above are marked ✓
- [ ] `moon fmt` produces no changes
- [ ] `moon info` updates interface correctly
- [ ] `moon check` reports no errors
- [ ] `moon test --native` passes all tests
- [ ] Code follows MoonBit project conventions
- [ ] No regressions in existing functionality
- [ ] Implementation matches technical design

## Review Process

1. **Read the design documents** to understand the requirements
2. **Review each modified file** against the checklist
3. **Run all verification commands** to ensure quality
4. **Test manually if needed** (optional but recommended)
5. **Document any issues found** with specific line numbers and suggestions
6. **Approve or request changes** based on checklist completion

## Issues to Report

If any issues are found, document them clearly:

```markdown
### Issue: [Brief description]

**File**: [filename:line_number]
**Severity**: [Critical/Major/Minor]
**Description**: [Detailed explanation]
**Suggestion**: [How to fix]
```

## Success Criteria

The implementation is ready for merge when:

- All checklist items are complete
- All tests pass
- Code is properly formatted
- Interface is updated
- No issues remain unresolved

## Notes

- This is a new feature addition, not a refactoring
- Backward compatibility is maintained
- The implementation follows existing patterns
- Performance impact is minimal
- The feature is well-tested with real containers
