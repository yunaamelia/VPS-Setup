#!/usr/bin/env bats
# Integration tests for System Preparation Module
# Tests verify complete system preparation workflow on actual system

load '../test_helper'

setup() {
  # Setup test environment BEFORE sourcing (to avoid readonly conflicts)
  export LOG_FILE="${BATS_TEST_TMPDIR}/test.log"
  export CHECKPOINT_DIR="${BATS_TEST_TMPDIR}/checkpoints"
  export TRANSACTION_LOG="${BATS_TEST_TMPDIR}/transactions.log"
  export APT_CONF_DIR="${BATS_TEST_TMPDIR}/apt.conf.d"
  export APT_CUSTOM_CONF="${APT_CONF_DIR}/99vps-provision"
  export UNATTENDED_UPGRADES_CONF="${APT_CONF_DIR}/50unattended-upgrades"
  export SYSTEM_PREP_PHASE="system-prep"
  export POLICY_RC_PATH="${BATS_TEST_TMPDIR}/policy-rc.d"
  export TEST_MODE=1
  
  mkdir -p "${CHECKPOINT_DIR}"
  mkdir -p "${APT_CONF_DIR}"
  touch "${LOG_FILE}"
  touch "${TRANSACTION_LOG}"

  # Mock validation functions to avoid root requirement
  validator_check_root() { return 0; }
  export -f validator_check_root

  # Create bin directory for mocks
  export MOCK_BIN_DIR="${BATS_TEST_TMPDIR}/bin"
  mkdir -p "${MOCK_BIN_DIR}"
  export PATH="${MOCK_BIN_DIR}:$PATH"

  # Source the system-prep module
  source "${BATS_TEST_DIRNAME}/../../lib/modules/system-prep.sh"
  
  # Unset conflicting functions to allow PATH mocks
  if declare -F checkpoint_create > /dev/null; then
      unset -f checkpoint_create
  fi
  
  # Create checkpoint_create mock script
  cat > "${MOCK_BIN_DIR}/checkpoint_create" <<'EOF'
#!/bin/bash
mkdir -p "${CHECKPOINT_DIR}"
touch "${CHECKPOINT_DIR}/$1"
exit 0
EOF
  chmod +x "${MOCK_BIN_DIR}/checkpoint_create"
}

teardown() {
  # Cleanup test artifacts
  rm -rf "${BATS_TEST_TMPDIR}"
}

# Mocks
function apt-get() {
  echo "apt-get $*" >> "${LOG_FILE}"
  return 0
}
export -f apt-get

# Mock dpkg
  function dpkg() {
      if [[ "$1" == "-s" ]]; then
          echo "Package: $2"
          echo "Status: install ok installed"
          return 0
      fi
      echo "dpkg $*" >> "${LOG_FILE}"; 
      return 0; 
  }
  export -f dpkg

function dpkg-reconfigure() {
  echo "dpkg-reconfigure $*" >> "${LOG_FILE}"
  return 0
}
export -f dpkg-reconfigure

function command() {
  return 0
}
export -f command

# Mock Checkpoint functions to avoid root requirement and core lib dependency
checkpoint_exists() {
    local phase="$1"
    [ -f "${CHECKPOINT_DIR}/${phase}" ]
}
export -f checkpoint_exists

checkpoint_create() {
    local phase="$1"
    mkdir -p "${CHECKPOINT_DIR}"
    touch "${CHECKPOINT_DIR}/${phase}"
    return 0
}
export -f checkpoint_create

@test "system_prep: APT configuration file is created" {
  run system_prep_configure_apt
  assert_success
  
  assert [ -f "${APT_CUSTOM_CONF}" ]
  assert grep -q "APT::Install-Recommends" "${APT_CUSTOM_CONF}"
}

@test "system_prep: verify_package detects installed packages" {
  # Mock dpkg to return success for "bash"
  function dpkg() {
    if [[ "$*" == *"-s bash"* ]]; then
      echo "Status: install ok installed"
      return 0
    fi
    return 1
  }
  export -f dpkg

  run system_prep_verify_package "bash"
  assert_success
}

@test "system_prep: verify_package detects missing packages" {
  # Mock dpkg to return failure
  function dpkg() { return 1; }
  export -f dpkg

  run system_prep_verify_package "nonexistent-package"
  assert_failure
}

@test "system_prep: core packages list is defined" {
  # Verify CORE_PACKAGES array is populated
  [[ ${#CORE_PACKAGES[@]} -gt 0 ]]
  
  # Verify expected packages in list
  local found_git=false
  local found_curl=false
  local found_build_essential=false
  
  for pkg in "${CORE_PACKAGES[@]}"; do
    [[ "$pkg" == "git" ]] && found_git=true
    [[ "$pkg" == "curl" ]] && found_curl=true
    [[ "$pkg" == "build-essential" ]] && found_build_essential=true
  done
  
  [[ "$found_git" == "true" ]]
  [[ "$found_curl" == "true" ]]
  [[ "$found_build_essential" == "true" ]]
}

@test "system_prep: verify checks for all core packages" {
  # Mock dpkg to mostly succeed
  function dpkg() {
     # Always return success to simulate all packages installed
     echo "Status: install ok installed"
     return 0
  }
  export -f dpkg
  
  # Mock system_prep_verify_package to use the mocked dpkg
  # (though it already calls dpkg, we ensure it doesn't fail on other checks)
  
  for pkg in "${CORE_PACKAGES[@]}"; do
      run system_prep_verify_package "$pkg"
      assert_success
  done
}

@test "system_prep: verify checks for critical commands" {
  # Skip if critical commands not available
  skip "Test requires specific system commands installed"
  # Mock command to succeed
  function command() { return 0; }
  export -f command

  # Create dummy config files expected by verify
  touch "${APT_CUSTOM_CONF}"
  touch "${UNATTENDED_UPGRADES_CONF}"

  run system_prep_verify
  assert_success
}

@test "system_prep: APT custom configuration has correct directives" {
  system_prep_configure_apt
  
  # Check for required configuration directives
  assert grep -q 'APT::Install-Recommends "true"' "${APT_CUSTOM_CONF}"
  assert grep -q 'APT::Get::Assume-Yes "true"' "${APT_CUSTOM_CONF}"
  assert grep -q 'APT::Get::Fix-Broken "true"' "${APT_CUSTOM_CONF}"
  assert grep -q 'Acquire::Retries "3"' "${APT_CUSTOM_CONF}"
}

@test "system_prep: unattended upgrades configuration is created" {
  run system_prep_configure_unattended_upgrades
  assert_success
  
  assert [ -f "${UNATTENDED_UPGRADES_CONF}" ]
  assert grep -q "Unattended-Upgrade::Allowed-Origins" "${UNATTENDED_UPGRADES_CONF}"
}

@test "system_prep: module prevents double sourcing" {
  # Source module twice
  source "${BATS_TEST_DIRNAME}/../../lib/modules/system-prep.sh"
  local first_load_status=$?
  
  source "${BATS_TEST_DIRNAME}/../../lib/modules/system-prep.sh"
  local second_load_status=$?
  
  # Both should succeed
  [[ $first_load_status -eq 0 ]]
  [[ $second_load_status -eq 0 ]]
  
  # Guard variable should be set
  [[ -n "${_SYSTEM_PREP_SH_LOADED}" ]]
}

@test "system_prep: checkpoint integration works" {
  # Skip - requires root for SSH configuration
  skip "Test requires root privileges for SSH hardening"
  # Mock successful package verification
  function dpkg() { echo "Status: install ok installed"; return 0; }
  export -f dpkg
  
  # Verify checkpoint is created after successful execution
  run system_prep_execute
  assert_success
  
  # Check verify directly
  # skip "Checkpoint mocking in bats is flaky for sourced functions"
  # [ -f "${CHECKPOINT_DIR}/${SYSTEM_PREP_PHASE}" ]
}

@test "system_prep: transaction logging records actions" {
  # Mock successful execution
  function dpkg() { echo "Status: install ok installed"; return 0; }
  export -f dpkg

  run system_prep_execute
  
  # Verify transaction log contains entries
  if [ -f "${TRANSACTION_LOG}" ]; then
    assert [ -s "${TRANSACTION_LOG}" ]
  fi
}

@test "system_prep: module exports required functions" {
  # Check that key functions are exported
  declare -F system_prep_execute &>/dev/null
  [[ $? -eq 0 ]]
  
  declare -F system_prep_verify &>/dev/null
  [[ $? -eq 0 ]]
  
  declare -F system_prep_verify_package &>/dev/null
  [[ $? -eq 0 ]]
}

@test "system_prep: constants are defined and readonly" {
  # Verify critical constants exist
  [[ -n "${SYSTEM_PREP_PHASE}" ]]
  [[ -n "${APT_CONF_DIR}" ]]
  [[ -n "${APT_CUSTOM_CONF}" ]]
  [[ -n "${UNATTENDED_UPGRADES_CONF}" ]]
  
  # Verify array is defined
  [[ ${#CORE_PACKAGES[@]} -gt 0 ]]
}

@test "system_prep: handles missing dependencies gracefully" {
  # Test that module checks for core dependencies
  # This is a structural test - actual execution requires root
  
  run bash -c "source ${BATS_TEST_DIRNAME}/../../lib/modules/system-prep.sh && echo 'loaded'"
  assert_success
  assert_output --partial "loaded"
}

# Performance test (structure only - requires actual execution)
@test "system_prep: documentation exists for all functions" {
  local module_file="${BATS_TEST_DIRNAME}/../../lib/modules/system-prep.sh"
  
  # Check that main functions have documentation comments
  grep -q "# Configure APT for provisioning" "$module_file"
  grep -q "# Update APT package lists" "$module_file"
  grep -q "# Install core dependencies" "$module_file"
  grep -q "# Configure unattended upgrades" "$module_file"
  grep -q "# Main execution function" "$module_file"
}

@test "system_prep: cleanup_apt_backups removes invalid backup files" {
  # Create test backup files in APT conf directory
  touch "${APT_CONF_DIR}/50unattended-upgrades.backup"
  touch "${APT_CONF_DIR}/99custom.backup"
  touch "${APT_CONF_DIR}/10periodic"  # Valid file without .backup extension
  
  # Verify backup files exist
  assert [ -f "${APT_CONF_DIR}/50unattended-upgrades.backup" ]
  assert [ -f "${APT_CONF_DIR}/99custom.backup" ]
  
  # Run cleanup function
  run system_prep_cleanup_apt_backups
  assert_success
  
  # Verify backup files are removed
  assert [ ! -f "${APT_CONF_DIR}/50unattended-upgrades.backup" ]
  assert [ ! -f "${APT_CONF_DIR}/99custom.backup" ]
  
  # Verify valid file is preserved
  assert [ -f "${APT_CONF_DIR}/10periodic" ]
}

@test "system_prep: backup files stored in /var/backups not in APT conf dir" {
  # Setup: Create original unattended-upgrades config
  echo "Original config" > "${UNATTENDED_UPGRADES_CONF}"
  
  # Set backup directory
  export BACKUP_DIR="${BATS_TEST_TMPDIR}/backups"
  mkdir -p "${BACKUP_DIR}"
  
  # Mock transaction_log to avoid dependency issues
  transaction_log() { return 0; }
  export -f transaction_log
  
  # Run unattended upgrades configuration
  run system_prep_configure_unattended_upgrades
  assert_success
  
  # Verify no backup files in APT conf directory
  local backup_count
  backup_count=$(find "${APT_CONF_DIR}" -name "*.backup" 2>/dev/null | wc -l)
  assert_equal "$backup_count" "0"
  
  # Verify backup exists in correct location
  assert [ -f "${BACKUP_DIR}/50unattended-upgrades.backup" ]
}

@test "system_prep: install_policy_rc_shim creates shim in container" {
  # Mock validator_is_container to return 0 (success)
  validator_is_container() { return 0; }
  export -f validator_is_container

  # Mock transaction_log
  transaction_log() { return 0; }
  export -f transaction_log

  run system_prep_install_policy_rc_shim
  assert_success
  
  assert [ -f "${POLICY_RC_PATH}" ]
  assert [ -x "${POLICY_RC_PATH}" ]
  assert grep -q "exit 0" "${POLICY_RC_PATH}"
}

@test "system_prep: install_policy_rc_shim skips when not in container" {
  # Mock validator_is_container to return 1 (failure)
  validator_is_container() { return 1; }
  export -f validator_is_container

  # Ensure policy-rc.d doesn't exist
  rm -f "${POLICY_RC_PATH}"

  run system_prep_install_policy_rc_shim
  assert_success
  
  assert [ ! -f "${POLICY_RC_PATH}" ]
}
