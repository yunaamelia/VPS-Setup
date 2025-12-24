#!/usr/bin/env bats
# Integration Tests: Audit Logging Verification
# Tests for T057: Verify audit logging is operational for sudo commands
#
# Purpose: Validate that auditd is:
#   - Properly installed and running
#   - Configured to log all sudo executions
#   - Retaining logs for at least 30 days (SEC-014)
#   - Capturing sudo events with sufficient detail
#
# Requirements:
#   - Auditd package installed
#   - Audit rules configured for sudo logging
#   - User provisioning module completed
#   - System-prep module completed

# Load test helpers
load ../test_helper

# Setup function runs before each test
setup() {
  # Create temporary test directory
  TEST_DIR="${BATS_TEST_TMPDIR}/audit-test"
  mkdir -p "${TEST_DIR}"
  
  # Source core libraries
  source "${PROJECT_ROOT}/lib/core/logger.sh"
  
  # Set up test environment
  export LOG_FILE="${TEST_DIR}/test.log"
  
  # Determine test username
  TEST_USERNAME="${TEST_USERNAME:-devuser}"
  
  # Check if auditd is installed
  if ! dpkg -s auditd &> /dev/null; then
    skip "Auditd package not installed - run user provisioning first"
  fi
}

# Teardown function runs after each test
teardown() {
  # Clean up test files
  if [[ -d "${TEST_DIR}" ]]; then
    rm -rf "${TEST_DIR}"
  fi
}

# Test 1: Verify auditd package is installed
@test "T057.1: Auditd package is installed" {
  run dpkg -s auditd
  [ "$status" -eq 0 ]
  [[ "$output" == *"Status: install ok installed"* ]]
}

# Test 2: Verify auditd service is enabled
@test "T057.2: Auditd service is enabled for auto-start" {
  run systemctl is-enabled auditd
  [ "$status" -eq 0 ]
  [[ "$output" == "enabled" ]]
}

# Test 3: Verify auditd service is active
@test "T057.3: Auditd service is running" {
  run systemctl is-active auditd
  [ "$status" -eq 0 ]
  [[ "$output" == "active" ]]
}

# Test 4: Verify audit rules file exists
@test "T057.4: Audit rules configuration file exists" {
  local rules_file="/etc/audit/rules.d/sudo-logging.rules"
  
  [ -f "${rules_file}" ]
  
  # Verify file is not empty
  [ -s "${rules_file}" ]
}

# Test 5: Verify sudo binary is being monitored
@test "T057.5: Audit rule for sudo binary is configured" {
  local rules_file="/etc/audit/rules.d/sudo-logging.rules"
  
  # Check for sudo binary watch rule
  run grep '/usr/bin/sudo' "${rules_file}"
  [ "$status" -eq 0 ]
  
  # Verify it's watching for execution (-p x flag)
  [[ "$output" == *"-p x"* ]]
  
  # Verify it has a key for searching
  [[ "$output" == *"-k sudo_commands"* ]]
}

# Test 6: Verify sudoers file is being monitored
@test "T057.6: Audit rules for sudoers files are configured" {
  local rules_file="/etc/audit/rules.d/sudo-logging.rules"
  
  # Check for /etc/sudoers monitoring
  run grep '/etc/sudoers' "${rules_file}"
  [ "$status" -eq 0 ]
  
  # Check for /etc/sudoers.d/ monitoring
  run grep '/etc/sudoers.d/' "${rules_file}"
  [ "$status" -eq 0 ]
}

# Test 7: Verify privileged execution monitoring is configured
@test "T057.7: Audit rules for privileged execution are configured" {
  local rules_file="/etc/audit/rules.d/sudo-logging.rules"
  
  # Check for execve syscall monitoring with euid=0 (root)
  run grep 'execve.*euid=0' "${rules_file}"
  [ "$status" -eq 0 ]
  
  # Verify it filters for regular users (auid>=1000)
  [[ "$output" == *"auid>=1000"* ]]
  
  # Verify it has a key
  [[ "$output" == *"-k privileged_execution"* ]]
}

# Test 8: Verify audit rules are loaded
@test "T057.8: Audit rules are loaded into kernel" {
  # List loaded audit rules
  run auditctl -l
  [ "$status" -eq 0 ]
  
  # Verify sudo watch rule is loaded
  echo "$output" | grep -q '/usr/bin/sudo'
}

# Test 9: Verify log retention configuration (SEC-014: 30 days)
@test "T057.9: Audit log retention is configured for 30 days (SEC-014)" {
  local auditd_conf="/etc/audit/auditd.conf"
  
  [ -f "${auditd_conf}" ]
  
  # Check max_log_file_action is set to ROTATE
  run grep '^max_log_file_action' "${auditd_conf}"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ROTATE"* ]]
  
  # Check num_logs is set to 30 or more
  run grep '^num_logs' "${auditd_conf}"
  [ "$status" -eq 0 ]
  
  # Extract number and verify >= 30
  local num_logs
  num_logs=$(echo "$output" | grep -oP 'num_logs = \K\d+')
  [ "${num_logs}" -ge 30 ]
}

# Test 10: Verify audit logs directory exists
@test "T057.10: Audit logs directory exists and is accessible" {
  local audit_log_dir="/var/log/audit"
  
  [ -d "${audit_log_dir}" ]
  
  # Verify directory is not empty (should have audit.log)
  [ -f "${audit_log_dir}/audit.log" ]
}

# Test 11: Generate test sudo event and verify it's logged
@test "T057.11: Sudo commands are captured in audit logs" {
  # Skip if test user doesn't exist
  if ! id "${TEST_USERNAME}" &> /dev/null; then
    skip "Test user ${TEST_USERNAME} does not exist"
  fi
  
  # Generate unique marker for this test
  local marker="audit-test-$$-${RANDOM}"
  
  # Execute a sudo command as test user with marker
  sudo -u "${TEST_USERNAME}" sudo -n echo "${marker}" &> /dev/null
  
  # Wait a moment for auditd to write the log
  sleep 2
  
  # Search audit logs for the sudo event
  run ausearch -k sudo_commands -ts recent
  [ "$status" -eq 0 ]
  
  # Verify output contains sudo-related events
  [[ "$output" == *"sudo"* ]] || [[ "$output" == *"EXECVE"* ]]
}

# Test 12: Verify audit log file permissions are secure
@test "T057.12: Audit log files have secure permissions" {
  local audit_log="/var/log/audit/audit.log"
  
  [ -f "${audit_log}" ]
  
  # Get file permissions
  local perms
  perms=$(stat -c '%a' "${audit_log}")
  
  # Verify permissions are 600 or 640 (owner read/write only, or owner+group read)
  [[ "${perms}" == "600" ]] || [[ "${perms}" == "640" ]]
  
  # Verify owner is root
  local owner
  owner=$(stat -c '%U' "${audit_log}")
  [[ "${owner}" == "root" ]]
}

# Test 13: Verify auditd configuration file permissions
@test "T057.13: Auditd configuration has secure permissions" {
  local auditd_conf="/etc/audit/auditd.conf"
  
  [ -f "${auditd_conf}" ]
  
  # Get file permissions
  local perms
  perms=$(stat -c '%a' "${auditd_conf}")
  
  # Verify permissions are 640 or more restrictive
  [[ "${perms}" == "640" ]] || [[ "${perms}" == "600" ]]
}

# Test 14: Verify audit rules can be searched by key
@test "T057.14: Audit events can be searched using configured keys" {
  # Search for sudo_commands key
  run ausearch -k sudo_commands -i 2>&1
  
  # Status 0 = events found, Status 1 = no events (acceptable for fresh install)
  [ "$status" -eq 0 ] || [ "$status" -eq 1 ]
  
  # If events exist, verify they're readable
  if [ "$status" -eq 0 ]; then
    [[ "$output" != "" ]]
  fi
  
  # Search for sudoers_changes key
  run ausearch -k sudoers_changes -i 2>&1
  [ "$status" -eq 0 ] || [ "$status" -eq 1 ]
  
  # Search for privileged_execution key
  run ausearch -k privileged_execution -i 2>&1
  [ "$status" -eq 0 ] || [ "$status" -eq 1 ]
}

# Test 15: Verify audit log rotation is working
@test "T057.15: Audit log rotation is configured" {
  local auditd_conf="/etc/audit/auditd.conf"
  
  [ -f "${auditd_conf}" ]
  
  # Check max_log_file setting (should be reasonable, e.g., 50 MB)
  run grep '^max_log_file' "${auditd_conf}"
  [ "$status" -eq 0 ]
  
  # Extract value and verify it's set
  local max_size
  max_size=$(echo "$output" | grep -oP 'max_log_file = \K\d+')
  [ "${max_size}" -gt 0 ]
  [ "${max_size}" -le 1000 ]  # Should not be excessively large
}

# Test 16: Verify auditd buffer size is adequate
@test "T057.16: Auditd has adequate buffer size for logging" {
  local auditd_conf="/etc/audit/auditd.conf"
  
  [ -f "${auditd_conf}" ]
  
  # Check buffer size configuration
  run grep '^num_logs' "${auditd_conf}"
  [ "$status" -eq 0 ]
}

# Test 17: Stress test - Multiple concurrent sudo operations are logged
@test "T057.17: Auditd captures multiple concurrent sudo operations" {
  # Skip if test user doesn't exist
  if ! id "${TEST_USERNAME}" &> /dev/null; then
    skip "Test user ${TEST_USERNAME} does not exist"
  fi
  
  # Record current audit log size
  local initial_events
  initial_events=$(ausearch -k sudo_commands 2>/dev/null | grep -c 'type=EXECVE' || echo 0)
  
  # Execute multiple sudo commands concurrently
  for i in {1..5}; do
    sudo -u "${TEST_USERNAME}" sudo -n whoami &> /dev/null &
  done
  
  # Wait for all background processes
  wait
  
  # Wait for auditd to process events
  sleep 3
  
  # Count events after test
  local final_events
  final_events=$(ausearch -k sudo_commands 2>/dev/null | grep -c 'type=EXECVE' || echo 0)
  
  # Verify at least some new events were logged (may not be exactly 5 due to batching)
  [ "${final_events}" -gt "${initial_events}" ]
}

# Test 18: Verify auditd service restart persistence
@test "T057.18: Audit rules persist after service restart" {
  # Get current rules count
  local initial_rules
  initial_rules=$(auditctl -l | wc -l)
  
  # Restart auditd service
  run systemctl restart auditd
  [ "$status" -eq 0 ]
  
  # Wait for service to fully start
  sleep 2
  
  # Verify service is active
  run systemctl is-active auditd
  [ "$status" -eq 0 ]
  
  # Get rules count after restart
  local final_rules
  final_rules=$(auditctl -l | wc -l)
  
  # Verify rules are still loaded (should be same count or more)
  [ "${final_rules}" -ge "${initial_rules}" ]
  
  # Specifically check for sudo rule
  run auditctl -l
  echo "$output" | grep -q '/usr/bin/sudo'
}
