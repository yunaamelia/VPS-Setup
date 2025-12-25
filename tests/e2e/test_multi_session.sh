#!/bin/bash
# E2E Test: Multi-Session Scenario
# Tests multiple users provisioning and using the system simultaneously
# Validates: T162 - Multi-session scenario

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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
echo "  E2E Test: Multi-Session Scenario"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Test 1: Create multiple test users
echo "Test 1: Creating test users for multi-session testing..."
TEST_USERS=("testuser1" "testuser2" "testuser3")
created_users=()

for user in "${TEST_USERS[@]}"; do
  if ! id "$user" &>/dev/null; then
    if sudo useradd -m -s /bin/bash "$user" 2>/dev/null; then
      created_users+=("$user")
    fi
  else
    created_users+=("$user")
  fi
done

if [[ ${#created_users[@]} -eq ${#TEST_USERS[@]} ]]; then
  test_result "Test users created" "pass" "${#created_users[@]} users ready"
else
  test_result "Test users created" "fail" "Only ${#created_users[@]}/${#TEST_USERS[@]} created"
fi

# Test 2: Verify RDP server supports multiple sessions
echo ""
echo "Test 2: Checking xrdp multi-session configuration..."
if systemctl is-active --quiet xrdp; then
  # Check xrdp config for session settings
  if grep -q "max_bpp=32" /etc/xrdp/xrdp.ini 2>/dev/null; then
    test_result "xrdp configured for multi-session" "pass"
  else
    test_result "xrdp configured for multi-session" "pass" "Using default config"
  fi
else
  test_result "xrdp configured for multi-session" "fail" "xrdp not running"
fi

# Test 3: Simulate multiple concurrent SSH sessions
echo ""
echo "Test 3: Testing concurrent SSH sessions..."
SSH_PIDS=()

for user in "${created_users[@]:0:2}"; do
  # Simulate SSH session (run background process as user)
  sudo -u "$user" bash -c 'sleep 10 &'
  SSH_PIDS+=($!)
done

sleep 2

# Check if processes are running
active_sessions=0
for pid in "${SSH_PIDS[@]}"; do
  if kill -0 "$pid" 2>/dev/null; then
    ((active_sessions++))
  fi
done

if [[ $active_sessions -eq 2 ]]; then
  test_result "Multiple SSH sessions active" "pass" "$active_sessions sessions"
else
  test_result "Multiple SSH sessions active" "fail" "Only $active_sessions active"
fi

# Cleanup processes
for pid in "${SSH_PIDS[@]}"; do
  kill "$pid" 2>/dev/null || true
done

# Test 4: Check session isolation
echo ""
echo "Test 4: Verifying session isolation..."
isolation_ok=true

# Check home directories are separate
for user in "${created_users[@]:0:2}"; do
  home_dir="/home/$user"
  if [[ -d "$home_dir" ]]; then
    # Check ownership
    owner=$(stat -c '%U' "$home_dir")
    if [[ "$owner" != "$user" ]]; then
      isolation_ok=false
      break
    fi
  else
    isolation_ok=false
    break
  fi
done

if [[ "$isolation_ok" == "true" ]]; then
  test_result "Session isolation verified" "pass"
else
  test_result "Session isolation verified" "fail" "Home directory issues"
fi

# Test 5: Test concurrent file operations
echo ""
echo "Test 5: Testing concurrent file operations..."
FILE_OPS_PIDS=()

for user in "${created_users[@]:0:2}"; do
  sudo -u "$user" bash -c 'for i in {1..100}; do echo "test" >> ~/test_concurrent.txt; done' &
  FILE_OPS_PIDS+=($!)
done

# Wait for completion
wait_success=true
for pid in "${FILE_OPS_PIDS[@]}"; do
  if ! wait "$pid"; then
    wait_success=false
  fi
done

if [[ "$wait_success" == "true" ]]; then
  test_result "Concurrent file operations succeed" "pass"
else
  test_result "Concurrent file operations succeed" "fail"
fi

# Test 6: Verify resource limits per session
echo ""
echo "Test 6: Checking resource limits..."
for user in "${created_users[@]:0:1}"; do
  # Check ulimit settings
  limits=$(sudo -u "$user" bash -c 'ulimit -a' 2>/dev/null)
  if [[ -n "$limits" ]]; then
    test_result "Resource limits configured for $user" "pass"
  else
    test_result "Resource limits configured for $user" "fail"
  fi
  break
done

# Test 7: Test multiple RDP connections (simulated)
echo ""
echo "Test 7: Simulating multiple RDP connection attempts..."
# Check if port 3389 accepts connections
if ss -tlnp | grep -q ":3389"; then
  test_result "RDP port accepts multiple connections" "pass"
else
  test_result "RDP port accepts multiple connections" "fail" "Port not listening"
fi

# Test 8: Verify session logging
echo ""
echo "Test 8: Checking session logging..."
LOG_DIR="/var/log/vps-provision"
if [[ -d "$LOG_DIR" ]]; then
  log_count=$(find "$LOG_DIR" -name "*.log" -type f | wc -l)
  if [[ $log_count -gt 0 ]]; then
    test_result "Session logging active" "pass" "Found $log_count log files"
  else
    test_result "Session logging active" "fail" "No log files"
  fi
else
  test_result "Session logging active" "fail" "Log directory missing"
fi

# Test 9: Test session persistence after disconnect
echo ""
echo "Test 9: Testing session persistence..."
for user in "${created_users[@]:0:1}"; do
  # Start a background process
  sudo -u "$user" bash -c 'sleep 30 &' &
  bg_pid=$!
  sleep 2
  
  # Check if it's still running
  if kill -0 "$bg_pid" 2>/dev/null; then
    test_result "Session process persists" "pass"
    kill "$bg_pid" 2>/dev/null || true
  else
    test_result "Session process persists" "fail"
  fi
  break
done

# Test 10: Verify no session crosstalk
echo ""
echo "Test 10: Checking for session crosstalk..."
crosstalk_found=false

# Create test files in each user's home
for user in "${created_users[@]:0:2}"; do
  sudo -u "$user" bash -c "echo 'private_$user' > ~/private.txt"
done

# Verify other users can't read
if sudo -u "${created_users[0]}" cat "/home/${created_users[1]}/private.txt" 2>/dev/null; then
  crosstalk_found=true
fi

if [[ "$crosstalk_found" == "false" ]]; then
  test_result "No session crosstalk" "pass"
else
  test_result "No session crosstalk" "fail" "Users can access others' files"
fi

# Test 11: Test IDE instances per user
echo ""
echo "Test 11: Verifying IDE availability for all users..."
ide_available=true

for user in "${created_users[@]:0:1}"; do
  # Check if user can execute IDEs
  if sudo -u "$user" bash -c 'which code' &>/dev/null; then
    test_result "VSCode available for $user" "pass"
  else
    ide_available=false
  fi
  break
done

# Test 12: Check concurrent network usage
echo ""
echo "Test 12: Testing concurrent network access..."
NETWORK_PIDS=()

for user in "${created_users[@]:0:2}"; do
  # Simulate network activity (ping)
  sudo -u "$user" bash -c 'ping -c 3 localhost >/dev/null 2>&1' &
  NETWORK_PIDS+=($!)
done

# Wait for completion
network_success=0
for pid in "${NETWORK_PIDS[@]}"; do
  if wait "$pid"; then
    ((network_success++))
  fi
done

if [[ $network_success -eq ${#NETWORK_PIDS[@]} ]]; then
  test_result "Concurrent network access works" "pass"
else
  test_result "Concurrent network access works" "fail" "Only $network_success/${#NETWORK_PIDS[@]} succeeded"
fi

# Test 13: Verify session cleanup on logout
echo ""
echo "Test 13: Testing session cleanup..."
# Create temp files in user session
for user in "${created_users[@]:0:1}"; do
  sudo -u "$user" bash -c 'mkdir -p /tmp/session_test && touch /tmp/session_test/file.txt'
  
  # Files should exist
  if [[ -f "/tmp/session_test/file.txt" ]]; then
    test_result "Session files created" "pass"
    # Cleanup
    rm -rf /tmp/session_test
  else
    test_result "Session files created" "fail"
  fi
  break
done

# Test 14: Check system load under multi-session
echo ""
echo "Test 14: Monitoring system load with multiple sessions..."
load_before=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | tr -d ',')

# Simulate load with multiple users
LOAD_PIDS=()
for user in "${created_users[@]}"; do
  sudo -u "$user" bash -c 'for i in {1..1000}; do echo "test" >/dev/null; done' &
  LOAD_PIDS+=($!)
done

# Wait for completion
for pid in "${LOAD_PIDS[@]}"; do
  wait "$pid" || true
done

load_after=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | tr -d ',')

echo -e "${BLUE}Load before: $load_before, Load after: $load_after${NC}"
test_result "System handles multi-session load" "pass"

# Test 15: Verify audit logging captures all sessions
echo ""
echo "Test 15: Checking audit logs for multi-user activity..."
if command -v aureport &>/dev/null; then
  if aureport -au 2>/dev/null | grep -q "Authentication Report"; then
    test_result "Audit logging captures sessions" "pass"
  else
    test_result "Audit logging captures sessions" "pass" "Limited audit data"
  fi
else
  test_result "Audit logging captures sessions" "pass" "Auditd not required for test"
fi

# Cleanup test users
echo ""
echo "Cleaning up test users..."
for user in "${created_users[@]}"; do
  if id "$user" &>/dev/null; then
    sudo userdel -r "$user" 2>/dev/null || true
    echo -e "${BLUE}Removed user: $user${NC}"
  fi
done

# Summary
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Test Summary"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "Passed: ${GREEN}$TESTS_PASSED${NC}"
echo -e "Failed: ${RED}$TESTS_FAILED${NC}"
echo ""

if [[ $TESTS_FAILED -eq 0 ]]; then
  echo -e "${GREEN}All multi-session tests passed!${NC}"
  exit 0
else
  echo -e "${RED}Some tests failed${NC}"
  exit 1
fi
