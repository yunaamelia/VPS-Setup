#!/usr/bin/env bats
# Integration Tests: User Permissions
# Tests for T055: Verify developer user can perform privileged operations
#
# Purpose: Validate that devuser can:
#   - Install packages via apt-get without password prompts
#   - Edit system files in /etc/
#   - Restart systemd services
#   - Execute privileged commands without password prompts
#
# Requirements:
#   - User provisioning module completed (checkpoint: user-creation)
#   - System-prep module completed
#   - Desktop environment installed
#   - User must be logged in or sudo context available

# Load test helpers
load ../test_helper

# Setup function runs before each test
setup() {
  # Create temporary test directory
  TEST_DIR="${BATS_TEST_TMPDIR}/user-permissions-test"
  mkdir -p "${TEST_DIR}"
  
  # Source core libraries
  source "${PROJECT_ROOT}/lib/core/logger.sh"
  source "${PROJECT_ROOT}/lib/core/checkpoint.sh"
  
  # Set up test environment
  export LOG_FILE="${TEST_DIR}/test.log"
  export CHECKPOINT_DIR="${TEST_DIR}/checkpoints"
  mkdir -p "${CHECKPOINT_DIR}"
  
  # Determine test username
  TEST_USERNAME="${TEST_USERNAME:-devuser}"
  
  # Check if user exists
  if ! id "${TEST_USERNAME}" &> /dev/null; then
    skip "Test user ${TEST_USERNAME} does not exist - run user provisioning first"
  fi
}

# Teardown function runs after each test
teardown() {
  # Clean up test files
  if [[ -d "${TEST_DIR}" ]]; then
    rm -rf "${TEST_DIR}"
  fi
}

# Test 1: Verify user can execute sudo without password
@test "T055.1: Developer user can execute sudo commands without password prompt" {
  # Run sudo command as test user
  run sudo -u "${TEST_USERNAME}" sudo -n whoami
  
  [ "$status" -eq 0 ]
  [[ "$output" == "root" ]]
}

# Test 2: Verify user can install packages via apt-get
@test "T055.2: Developer user can install packages via apt-get" {
  # Test with a small, harmless package (tree is typically not installed)
  local test_package="tree"
  
  # Remove package if already installed (cleanup)
  if dpkg -s "${test_package}" &> /dev/null; then
    sudo apt-get remove -y "${test_package}" &> /dev/null
  fi
  
  # Attempt to install as test user without password
  run sudo -u "${TEST_USERNAME}" sudo -n apt-get install -y "${test_package}"
  
  [ "$status" -eq 0 ]
  
  # Verify package is installed
  run dpkg -s "${test_package}"
  [ "$status" -eq 0 ]
  
  # Cleanup: remove test package
  sudo apt-get remove -y "${test_package}" &> /dev/null
}

# Test 3: Verify user can edit files in /etc/
@test "T055.3: Developer user can edit system files in /etc/" {
  local test_file="/etc/vps-provision-test.conf"
  local test_content="# VPS Provisioning Test File"
  
  # Create test file as regular user with sudo
  run sudo -u "${TEST_USERNAME}" sudo -n bash -c "echo '${test_content}' > ${test_file}"
  
  [ "$status" -eq 0 ]
  
  # Verify file was created
  [ -f "${test_file}" ]
  
  # Verify content
  run cat "${test_file}"
  [[ "$output" == *"${test_content}"* ]]
  
  # Cleanup: remove test file
  sudo rm -f "${test_file}"
}

# Test 4: Verify user can restart systemd services
@test "T055.4: Developer user can restart systemd services" {
  # Use a safe service for testing (cron is always present and safe to restart)
  local test_service="cron"
  
  # Verify service exists
  if ! systemctl list-units --type=service --all | grep -q "${test_service}"; then
    skip "Test service ${test_service} not available"
  fi
  
  # Get current service status
  local initial_status
  initial_status=$(systemctl is-active "${test_service}")
  
  # Restart service as test user
  run sudo -u "${TEST_USERNAME}" sudo -n systemctl restart "${test_service}"
  
  [ "$status" -eq 0 ]
  
  # Verify service is still running after restart
  run systemctl is-active "${test_service}"
  [ "$status" -eq 0 ]
  [[ "$output" == "active" ]]
}

# Test 5: Verify user can execute other privileged commands
@test "T055.5: Developer user can execute miscellaneous privileged commands" {
  # Test multiple privileged operations
  
  # Test 1: Check system logs
  run sudo -u "${TEST_USERNAME}" sudo -n dmesg -T
  [ "$status" -eq 0 ]
  
  # Test 2: Check network configuration
  run sudo -u "${TEST_USERNAME}" sudo -n ip addr show
  [ "$status" -eq 0 ]
  
  # Test 3: Check loaded kernel modules
  run sudo -u "${TEST_USERNAME}" sudo -n lsmod
  [ "$status" -eq 0 ]
}

# Test 6: Verify sudo lecture configuration (SEC-010)
@test "T055.6: Sudo lecture is configured for security awareness (SEC-010)" {
  local sudoers_file="/etc/sudoers.d/80-${TEST_USERNAME}"
  
  # Verify sudoers file exists
  [ -f "${sudoers_file}" ]
  
  # Verify lecture configuration is present
  run grep 'lecture="always"' "${sudoers_file}"
  [ "$status" -eq 0 ]
}

# Test 7: Verify sudo timeout configuration (T054)
@test "T055.7: Sudo timeout is configured appropriately (T054)" {
  local sudoers_file="/etc/sudoers.d/80-${TEST_USERNAME}"
  
  # Verify sudoers file exists
  [ -f "${sudoers_file}" ]
  
  # Verify timeout configuration is present
  run grep 'timestamp_timeout=' "${sudoers_file}"
  [ "$status" -eq 0 ]
  
  # Extract timeout value and verify it's reasonable (should be 15 minutes)
  local timeout_value
  timeout_value=$(grep -oP 'timestamp_timeout=\K\d+' "${sudoers_file}")
  
  # Verify timeout is set to a reasonable value (10-30 minutes)
  [ "${timeout_value}" -ge 10 ]
  [ "${timeout_value}" -le 30 ]
}

# Test 8: Verify audit logging configuration (T054)
@test "T055.8: Sudo audit logging is configured (T054)" {
  local sudoers_file="/etc/sudoers.d/80-${TEST_USERNAME}"
  
  # Verify sudoers file exists
  [ -f "${sudoers_file}" ]
  
  # Verify audit logging configuration is present
  run grep 'logfile="/var/log/sudo/sudo.log"' "${sudoers_file}"
  [ "$status" -eq 0 ]
  
  # Verify log_input and log_output are enabled
  run grep 'log_input, log_output' "${sudoers_file}"
  [ "$status" -eq 0 ]
  
  # Verify log directory exists
  [ -d "/var/log/sudo" ]
}

# Test 9: Verify user is in all required groups
@test "T055.9: Developer user is member of all required groups" {
  local required_groups=("sudo" "audio" "video" "dialout" "plugdev")
  
  # Get user's groups
  local user_groups
  user_groups=$(id -Gn "${TEST_USERNAME}")
  
  # Check each required group
  for group in "${required_groups[@]}"; do
    echo "# Checking group: ${group}" >&3
    echo "${user_groups}" | grep -qw "${group}"
  done
}

# Test 10: Verify passwordless sudo doesn't require password for any command
@test "T055.10: Passwordless sudo works for all command types" {
  # Test various command types that typically require different sudo permissions
  
  # File operations
  run sudo -u "${TEST_USERNAME}" sudo -n touch /tmp/sudo-test-file
  [ "$status" -eq 0 ]
  sudo rm -f /tmp/sudo-test-file
  
  # Process management
  run sudo -u "${TEST_USERNAME}" sudo -n ps aux
  [ "$status" -eq 0 ]
  
  # System administration
  run sudo -u "${TEST_USERNAME}" sudo -n systemctl list-units
  [ "$status" -eq 0 ]
  
  # Network operations
  run sudo -u "${TEST_USERNAME}" sudo -n iptables -L -n
  [ "$status" -eq 0 ]
}

# Test 11: Verify sudo log directory has correct permissions
@test "T055.11: Sudo log directory has secure permissions" {
  local log_dir="/var/log/sudo"
  
  # Verify directory exists
  [ -d "${log_dir}" ]
  
  # Get directory permissions (should be 0750)
  local perms
  perms=$(stat -c '%a' "${log_dir}")
  
  # Verify permissions are 750 or more restrictive
  [[ "${perms}" == "750" ]] || [[ "${perms}" == "700" ]]
}

# Test 12: Stress test - Multiple concurrent sudo operations
@test "T055.12: Developer user can execute multiple concurrent sudo operations" {
  # Execute multiple sudo commands in parallel
  local pids=()
  
  for i in {1..5}; do
    sudo -u "${TEST_USERNAME}" sudo -n whoami &> /dev/null &
    pids+=($!)
  done
  
  # Wait for all background processes
  local failed=0
  for pid in "${pids[@]}"; do
    if ! wait "${pid}"; then
      failed=$((failed + 1))
    fi
  done
  
  # All should succeed
  [ "${failed}" -eq 0 ]
}
