#!/bin/bash
# E2E Test: Idempotent Re-run
# Tests that re-running provisioning on already-provisioned system is safe and fast
# Validates: T160 - Idempotent re-run

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

TESTS_PASSED=0
TESTS_FAILED=0

# Test result logging
test_result() {
  local name="$1"
  local result="$2"
  local message="${3:-}"
  
  if [[ "$result" == "pass" ]]; then
    echo -e "${GREEN}✓${NC} $name"
    ((TESTS_PASSED++))
  else
    echo -e "${RED}✗${NC} $name${message:+: $message}"
    ((TESTS_FAILED++))
  fi
}

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  E2E Test: Idempotent Re-run"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

CHECKPOINT_DIR="/var/vps-provision/checkpoints"
LOG_DIR="/var/log/vps-provision"
CLI_COMMAND="./bin/vps-provision"

# Verify CLI exists
if [[ ! -x "$CLI_COMMAND" ]]; then
  test_result "CLI command exists" "fail" "bin/vps-provision not found"
  exit 1
fi

# Test 1: Checkpoints exist from initial run
echo "Test 1: Verifying checkpoints from initial provisioning..."
if [[ -d "$CHECKPOINT_DIR" ]]; then
  checkpoint_count=$(find "$CHECKPOINT_DIR" -name "*.checkpoint" 2>/dev/null | wc -l)
  if [[ $checkpoint_count -gt 0 ]]; then
    test_result "Checkpoints exist from initial run" "pass" "Found $checkpoint_count checkpoints"
  else
    test_result "Checkpoints exist from initial run" "fail" "No checkpoints found"
  fi
else
  test_result "Checkpoints exist from initial run" "fail" "Checkpoint directory missing"
fi

# Test 2: Record initial state
echo ""
echo "Test 2: Recording initial system state..."
INITIAL_STATE_FILE="/tmp/vps-state-initial.txt"

# Capture current state
{
  echo "=== Services ==="
  systemctl list-units --type=service --state=running | grep -E "(xrdp|ssh)" || true
  echo "=== Users ==="
  getent passwd | grep -E "^(devuser|developer)" || true
  echo "=== IDEs ==="
  command -v code || echo "VSCode: not found"
  command -v cursor || echo "Cursor: not found"
  ls -la /opt/ | grep -i antigravity || echo "Antigravity: not found"
  echo "=== Checkpoints ==="
  ls -la "$CHECKPOINT_DIR" 2>/dev/null || echo "No checkpoints"
} > "$INITIAL_STATE_FILE"

test_result "Initial state recorded" "pass"

# Test 3: Run provisioning again (dry-run first)
echo ""
echo "Test 3: Testing dry-run mode..."
if [[ -f "$CLI_COMMAND" ]]; then
  start_time=$(date +%s)
  
  # Dry-run should be very fast
  if timeout 60 "$CLI_COMMAND" --dry-run 2>&1 | tee /tmp/dryrun.log; then
    end_time=$(date +%s)
    duration=$((end_time - start_time))
    
    if [[ $duration -lt 60 ]]; then
      test_result "Dry-run completed quickly" "pass" "Took ${duration}s"
    else
      test_result "Dry-run completed quickly" "fail" "Took ${duration}s (expected <60s)"
    fi
  else
    test_result "Dry-run execution" "fail" "Dry-run failed"
  fi
else
  test_result "Dry-run execution" "fail" "CLI not available"
fi

# Test 4: Check dry-run didn't modify state
echo ""
echo "Test 4: Verifying dry-run didn't modify system..."
DRYRUN_STATE_FILE="/tmp/vps-state-dryrun.txt"

{
  echo "=== Services ==="
  systemctl list-units --type=service --state=running | grep -E "(xrdp|ssh)" || true
  echo "=== Users ==="
  getent passwd | grep -E "^(devuser|developer)" || true
  echo "=== IDEs ==="
  command -v code || echo "VSCode: not found"
  command -v cursor || echo "Cursor: not found"
  ls -la /opt/ | grep -i antigravity || echo "Antigravity: not found"
  echo "=== Checkpoints ==="
  ls -la "$CHECKPOINT_DIR" 2>/dev/null || echo "No checkpoints"
} > "$DRYRUN_STATE_FILE"

if diff -q "$INITIAL_STATE_FILE" "$DRYRUN_STATE_FILE" >/dev/null; then
  test_result "Dry-run didn't modify state" "pass"
else
  test_result "Dry-run didn't modify state" "fail" "State changed"
fi

# Test 5: Run full re-provision (should be fast due to checkpoints)
echo ""
echo "Test 5: Running full re-provisioning..."
echo -e "${YELLOW}Note: This should complete quickly due to existing checkpoints${NC}"

start_time=$(date +%s)
RERUN_LOG="/tmp/vps-rerun.log"

# Run with --yes to skip prompts
if sudo "$CLI_COMMAND" --yes 2>&1 | tee "$RERUN_LOG"; then
  end_time=$(date +%s)
  duration=$((end_time - start_time))
  
  # Re-run should complete in ≤5 minutes (300s) per spec
  if [[ $duration -le 300 ]]; then
    test_result "Re-run completed within time limit" "pass" "Took ${duration}s (target: ≤300s)"
  else
    test_result "Re-run completed within time limit" "fail" "Took ${duration}s (target: ≤300s)"
  fi
else
  end_time=$(date +%s)
  duration=$((end_time - start_time))
  test_result "Re-run execution" "fail" "Provisioning failed after ${duration}s"
fi

# Test 6: Verify checkpoints were used (not recreated)
echo ""
echo "Test 6: Verifying checkpoints were reused..."
if grep -q "already completed" "$RERUN_LOG" || grep -q "checkpoint found" "$RERUN_LOG"; then
  test_result "Checkpoints were reused" "pass"
else
  test_result "Checkpoints were reused" "fail" "No evidence of checkpoint reuse"
fi

# Test 7: Verify no duplicate installations
echo ""
echo "Test 7: Checking for duplicate installations..."
duplicate_found=false

# Check for duplicate packages
if dpkg -l | grep -E "(xfce4|xrdp)" | grep "ii" | wc -l | grep -q "^1"; then
  test_result "No duplicate XFCE packages" "pass"
else
  duplicate_found=true
fi

if dpkg -l | grep "xrdp" | grep "ii" | wc -l | grep -q "^1"; then
  test_result "No duplicate xrdp packages" "pass"
else
  duplicate_found=true
fi

if [[ "$duplicate_found" == "true" ]]; then
  test_result "No duplicate installations" "fail" "Found duplicates"
else
  test_result "No duplicate installations" "pass"
fi

# Test 8: Verify system state unchanged
echo ""
echo "Test 8: Verifying system state after re-run..."
FINAL_STATE_FILE="/tmp/vps-state-final.txt"

{
  echo "=== Services ==="
  systemctl list-units --type=service --state=running | grep -E "(xrdp|ssh)" || true
  echo "=== Users ==="
  getent passwd | grep -E "^(devuser|developer)" || true
  echo "=== IDEs ==="
  command -v code || echo "VSCode: not found"
  command -v cursor || echo "Cursor: not found"
  ls -la /opt/ | grep -i antigravity || echo "Antigravity: not found"
  echo "=== Checkpoints ==="
  ls -la "$CHECKPOINT_DIR" 2>/dev/null || echo "No checkpoints"
} > "$FINAL_STATE_FILE"

# State should be essentially the same (allowing for timestamps)
if diff -I "checkpoint" -q "$INITIAL_STATE_FILE" "$FINAL_STATE_FILE" >/dev/null; then
  test_result "System state preserved" "pass"
else
  test_result "System state preserved" "fail" "State differs"
fi

# Test 9: Verify services still running
echo ""
echo "Test 9: Verifying services health after re-run..."
if systemctl is-active --quiet xrdp; then
  test_result "xrdp service still running" "pass"
else
  test_result "xrdp service still running" "fail"
fi

if systemctl is-active --quiet ssh; then
  test_result "ssh service still running" "pass"
else
  test_result "ssh service still running" "fail"
fi

# Test 10: Verify RDP connectivity
echo ""
echo "Test 10: Verifying RDP connectivity..."
if ss -tlnp | grep -q ":3389"; then
  test_result "RDP port listening" "pass"
else
  test_result "RDP port listening" "fail"
fi

# Test 11: Verify log doesn't show errors
echo ""
echo "Test 11: Checking logs for errors..."
if grep -i "error" "$RERUN_LOG" | grep -v "no error" | grep -v "0 errors"; then
  test_result "No errors in re-run" "fail" "Errors found in log"
else
  test_result "No errors in re-run" "pass"
fi

# Test 12: Verify transaction log wasn't corrupted
echo ""
echo "Test 12: Verifying transaction log integrity..."
TRANSACTION_LOG="$LOG_DIR/transactions.log"
if [[ -f "$TRANSACTION_LOG" ]]; then
  if grep -q "TRANSACTION" "$TRANSACTION_LOG"; then
    test_result "Transaction log intact" "pass"
  else
    test_result "Transaction log intact" "fail" "No transactions found"
  fi
else
  test_result "Transaction log intact" "fail" "Transaction log missing"
fi

# Test 13: Verify multiple re-runs possible
echo ""
echo "Test 13: Testing multiple consecutive re-runs..."
echo -e "${YELLOW}Running third provisioning attempt...${NC}"

start_time=$(date +%s)
if timeout 360 sudo "$CLI_COMMAND" --yes >/dev/null 2>&1; then
  end_time=$(date +%s)
  duration=$((end_time - start_time))
  
  if [[ $duration -le 300 ]]; then
    test_result "Multiple re-runs supported" "pass" "3rd run took ${duration}s"
  else
    test_result "Multiple re-runs supported" "fail" "3rd run took ${duration}s"
  fi
else
  test_result "Multiple re-runs supported" "fail" "3rd run failed"
fi

# Summary
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Test Summary"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "Passed: ${GREEN}$TESTS_PASSED${NC}"
echo -e "Failed: ${RED}$TESTS_FAILED${NC}"
echo ""

# Cleanup temp files
rm -f "$INITIAL_STATE_FILE" "$DRYRUN_STATE_FILE" "$FINAL_STATE_FILE" "$RERUN_LOG"

# Exit with appropriate code
if [[ $TESTS_FAILED -eq 0 ]]; then
  echo -e "${GREEN}All tests passed!${NC}"
  exit 0
else
  echo -e "${RED}Some tests failed${NC}"
  exit 1
fi
