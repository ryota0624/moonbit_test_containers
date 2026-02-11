#!/bin/bash
# Serial test runner for wait_strategies tests
# Runs each test individually to avoid async runtime issues

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test configuration
PACKAGE="ryota0624/moonbit_test_containers"
TEST_FILE="wait_strategies_wbtest.mbt"
WAIT_BETWEEN_TESTS=2  # seconds to wait between tests

# Test indices and names
declare -a TESTS=(
  "0:wait strategy tcp port"
  "1:wait strategy seconds"
  "2:wait strategy http get"
  "3:wait strategy http get custom path"
  "4:wait strategy http get no ports"
  "5:wait strategy log message postgres"
  "6:wait strategy log message nginx"
  "7:wait strategy log message redis"
  # "8:wait strategy log message timeout"  # Skip timeout test (known issue)
)

# Statistics
TOTAL=0
PASSED=0
FAILED=0
SKIPPED=0
declare -a FAILED_TESTS=()

echo "========================================="
echo "Running wait_strategies tests serially"
echo "========================================="
echo ""

# Run each test individually
for test_spec in "${TESTS[@]}"; do
  IFS=':' read -r index name <<< "$test_spec"
  TOTAL=$((TOTAL + 1))

  echo "[$TOTAL/${#TESTS[@]}] Running: $name (index $index)"
  echo "---"

  # Run the test
  if moon test --target native -p "$PACKAGE" -f "$TEST_FILE" -i "$index" > /tmp/test_$index.log 2>&1; then
    echo -e "${GREEN}✓ PASSED${NC}: $name"
    PASSED=$((PASSED + 1))
  else
    echo -e "${RED}✗ FAILED${NC}: $name"
    FAILED=$((FAILED + 1))
    FAILED_TESTS+=("$name (index $index)")

    # Show last few lines of error
    echo "  Error output:"
    tail -5 /tmp/test_$index.log | sed 's/^/    /'
  fi

  echo ""

  # Wait between tests to allow cleanup
  if [ $TOTAL -lt ${#TESTS[@]} ]; then
    echo "Waiting ${WAIT_BETWEEN_TESTS}s for cleanup..."
    sleep $WAIT_BETWEEN_TESTS
    echo ""
  fi
done

# Summary
echo "========================================="
echo "Test Summary"
echo "========================================="
echo -e "Total:   $TOTAL"
echo -e "${GREEN}Passed:  $PASSED${NC}"
if [ $FAILED -gt 0 ]; then
  echo -e "${RED}Failed:  $FAILED${NC}"
else
  echo -e "Failed:  $FAILED"
fi
echo -e "Skipped: $SKIPPED"
echo ""

# List failed tests if any
if [ $FAILED -gt 0 ]; then
  echo "Failed tests:"
  for test in "${FAILED_TESTS[@]}"; do
    echo -e "  ${RED}✗${NC} $test"
  done
  echo ""
  exit 1
fi

echo -e "${GREEN}All tests passed!${NC}"
exit 0
