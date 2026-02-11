#!/bin/bash
# Test only log message wait strategies (indices 5, 6, 7)

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

PACKAGE="ryota0624/moonbit_test_containers"
TEST_FILE="wait_strategies_wbtest.mbt"
WAIT_TIME=3

declare -a TESTS=(
  "5:PostgreSQL log message"
  "6:Nginx log message"
  "7:Redis log message"
)

PASSED=0
FAILED=0

echo "Testing Log Message Wait Strategies"
echo "===================================="
echo ""

for test_spec in "${TESTS[@]}"; do
  IFS=':' read -r index name <<< "$test_spec"

  echo "Running: $name"
  if moon test --target native -p "$PACKAGE" -f "$TEST_FILE" -i "$index" > /tmp/test_$index.log 2>&1; then
    echo -e "${GREEN}✓ PASSED${NC}"
    PASSED=$((PASSED + 1))
  else
    echo -e "${RED}✗ FAILED${NC}"
    FAILED=$((FAILED + 1))
    tail -10 /tmp/test_$index.log
  fi

  echo "Waiting ${WAIT_TIME}s..."
  sleep $WAIT_TIME
  echo ""
done

echo "===================================="
echo "Results: $PASSED passed, $FAILED failed"
[ $FAILED -eq 0 ] && echo -e "${GREEN}Success!${NC}" || echo -e "${RED}Some tests failed${NC}"
exit $FAILED
