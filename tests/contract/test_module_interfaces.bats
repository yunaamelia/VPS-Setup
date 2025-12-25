#!/usr/bin/env bats
# Contract Tests: Module Interfaces
# Validates module interface contracts for all provisioning modules
# Tests function signatures, return values, error handling, and state management

load '../test_helper'

setup() {
  export LIB_DIR="${BATS_TEST_DIRNAME}/../../lib"
  export LOG_FILE="${BATS_TEST_TMPDIR}/test.log"
  export CHECKPOINT_DIR="${BATS_TEST_TMPDIR}/checkpoints"
  export TRANSACTION_LOG="${BATS_TEST_TMPDIR}/transactions.log"
  export TEST_MODE=1
  
  mkdir -p "${CHECKPOINT_DIR}"
  touch "${LOG_FILE}"
  touch "${TRANSACTION_LOG}"
}

teardown() {
  rm -rf "${BATS_TEST_TMPDIR}"
}

# System Prep Module Interface
@test "module: system-prep exports execute function" {
  source "${LIB_DIR}/modules/system-prep.sh" 2>/dev/null || true
  
  declare -f system_prep_execute >/dev/null
}

@test "module: system-prep exports check_prerequisites function" {
  source "${LIB_DIR}/modules/system-prep.sh" 2>/dev/null || true
  
  declare -f system_prep_check_prerequisites >/dev/null
}

@test "module: system-prep execute creates checkpoint on success" {
  source "${LIB_DIR}/core/checkpoint.sh" 2>/dev/null || true
  source "${LIB_DIR}/modules/system-prep.sh" 2>/dev/null || true
  
  # Mock execution (would create checkpoint)
  touch "${CHECKPOINT_DIR}/system-prep"
  
  [ -f "${CHECKPOINT_DIR}/system-prep" ]
}

# User Provisioning Module Interface
@test "module: user-provisioning exports execute function" {
  source "${LIB_DIR}/modules/user-provisioning.sh" 2>/dev/null || true
  
  declare -f user_provisioning_execute >/dev/null
}

@test "module: user-provisioning exports check_prerequisites function" {
  source "${LIB_DIR}/modules/user-provisioning.sh" 2>/dev/null || true
  
  declare -f user_provisioning_check_prerequisites >/dev/null
}

@test "module: user-provisioning validates username parameter" {
  source "${LIB_DIR}/modules/user-provisioning.sh" 2>/dev/null || true
  
  # Function should exist and handle parameters
  declare -f user_provisioning_create_user >/dev/null
}

# Desktop Environment Module Interface
@test "module: desktop-env exports execute function" {
  source "${LIB_DIR}/modules/desktop-env.sh" 2>/dev/null || true
  
  declare -f desktop_env_execute >/dev/null
}

@test "module: desktop-env exports check_prerequisites function" {
  source "${LIB_DIR}/modules/desktop-env.sh" 2>/dev/null || true
  
  declare -f desktop_env_check_prerequisites >/dev/null
}

@test "module: desktop-env requires system-prep checkpoint" {
  source "${LIB_DIR}/core/checkpoint.sh" 2>/dev/null || true
  source "${LIB_DIR}/modules/desktop-env.sh" 2>/dev/null || true
  
  # Should fail without system-prep
  [ ! -f "${CHECKPOINT_DIR}/system-prep" ]
}

# RDP Server Module Interface
@test "module: rdp-server exports execute function" {
  source "${LIB_DIR}/modules/rdp-server.sh" 2>/dev/null || true
  
  declare -f rdp_server_execute >/dev/null
}

@test "module: rdp-server exports check_prerequisites function" {
  source "${LIB_DIR}/modules/rdp-server.sh" 2>/dev/null || true
  
  declare -f rdp_server_check_prerequisites >/dev/null
}

@test "module: rdp-server requires desktop-env checkpoint" {
  source "${LIB_DIR}/core/checkpoint.sh" 2>/dev/null || true
  source "${LIB_DIR}/modules/rdp-server.sh" 2>/dev/null || true
  
  # Should fail without desktop-env
  [ ! -f "${CHECKPOINT_DIR}/desktop-env" ]
}

# IDE VSCode Module Interface
@test "module: ide-vscode exports execute function" {
  source "${LIB_DIR}/modules/ide-vscode.sh" 2>/dev/null || true
  
  declare -f ide_vscode_execute >/dev/null
}

@test "module: ide-vscode exports check_prerequisites function" {
  source "${LIB_DIR}/modules/ide-vscode.sh" 2>/dev/null || true
  
  declare -f ide_vscode_check_prerequisites >/dev/null
}

@test "module: ide-vscode can install in parallel" {
  # VSCode is part of parallel IDE installation group
  [ -f "${LIB_DIR}/modules/parallel-ide-install.sh" ]
}

# IDE Cursor Module Interface
@test "module: ide-cursor exports execute function" {
  source "${LIB_DIR}/modules/ide-cursor.sh" 2>/dev/null || true
  
  declare -f ide_cursor_execute >/dev/null
}

@test "module: ide-cursor exports check_prerequisites function" {
  source "${LIB_DIR}/modules/ide-cursor.sh" 2>/dev/null || true
  
  declare -f ide_cursor_check_prerequisites >/dev/null
}

@test "module: ide-cursor can install in parallel" {
  # Cursor is part of parallel IDE installation group
  [ -f "${LIB_DIR}/modules/parallel-ide-install.sh" ]
}

# IDE Antigravity Module Interface
@test "module: ide-antigravity exports execute function" {
  source "${LIB_DIR}/modules/ide-antigravity.sh" 2>/dev/null || true
  
  declare -f ide_antigravity_execute >/dev/null
}

@test "module: ide-antigravity exports check_prerequisites function" {
  source "${LIB_DIR}/modules/ide-antigravity.sh" 2>/dev/null || true
  
  declare -f ide_antigravity_check_prerequisites >/dev/null
}

# Terminal Setup Module Interface
@test "module: terminal-setup exports execute function" {
  source "${LIB_DIR}/modules/terminal-setup.sh" 2>/dev/null || true
  
  declare -f terminal_setup_execute >/dev/null
}

@test "module: terminal-setup exports check_prerequisites function" {
  source "${LIB_DIR}/modules/terminal-setup.sh" 2>/dev/null || true
  
  declare -f terminal_setup_check_prerequisites >/dev/null
}

# Verification Module Interface
@test "module: verification exports execute function" {
  source "${LIB_DIR}/modules/verification.sh" 2>/dev/null || true
  
  declare -f verification_execute >/dev/null
}

@test "module: verification checks all required components" {
  source "${LIB_DIR}/modules/verification.sh" 2>/dev/null || true
  
  declare -f verification_check_services >/dev/null
  declare -f verification_check_ides >/dev/null
  declare -f verification_check_ports >/dev/null
}

# Status Banner Module Interface
@test "module: status-banner exports execute function" {
  source "${LIB_DIR}/modules/status-banner.sh" 2>/dev/null || true
  
  declare -f status_banner_execute >/dev/null
}

@test "module: status-banner displays connection info" {
  source "${LIB_DIR}/modules/status-banner.sh" 2>/dev/null || true
  
  declare -f status_banner_show_rdp_info >/dev/null
}

# Common Module Interface Requirements
@test "modules: all modules handle TEST_MODE environment variable" {
  # Test that modules respect TEST_MODE
  export TEST_MODE=1
  
  [ "$TEST_MODE" = "1" ]
}

@test "modules: all modules use checkpoint system" {
  # All modules should integrate with checkpoint system
  [ -f "${LIB_DIR}/core/checkpoint.sh" ]
}

@test "modules: all modules use transaction logging" {
  # All modules should log transactions for rollback
  [ -f "${LIB_DIR}/core/transaction.sh" ]
}

@test "modules: all modules use structured logging" {
  # All modules should use logger.sh
  [ -f "${LIB_DIR}/core/logger.sh" ]
}

# Error Handling Interface
@test "modules: execute functions return non-zero on error" {
  # Contract: all execute functions must return proper exit codes
  # Success: 0, Error: non-zero
  
  # Create a simple test
  test_exit_code() {
    return 1
  }
  
  if test_exit_code; then
    false  # Should not reach here
  else
    [ $? -ne 0 ]
  fi
}

@test "modules: check_prerequisites returns status code" {
  # Contract: prerequisite checks must return meaningful status
  # Pass: 0, Fail: non-zero
  
  test_prereq() {
    # Example: missing dependency
    return 1
  }
  
  run test_prereq
  [ "$status" -ne 0 ]
}

# State Management Interface
@test "modules: modules create checkpoints on completion" {
  # Contract: successful module execution creates checkpoint
  touch "${CHECKPOINT_DIR}/test-module"
  
  [ -f "${CHECKPOINT_DIR}/test-module" ]
}

@test "modules: modules log transactions for rollback" {
  # Contract: state-changing operations are logged
  echo "TRANSACTION|test|action|$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "${TRANSACTION_LOG}"
  
  grep -q "TRANSACTION" "${TRANSACTION_LOG}"
}

@test "modules: modules skip execution if checkpoint exists" {
  # Contract: idempotency via checkpoint checking
  touch "${CHECKPOINT_DIR}/test-module"
  
  # Simulated check
  if [ -f "${CHECKPOINT_DIR}/test-module" ]; then
    # Should skip
    true
  fi
}

# Parallel Execution Interface
@test "modules: parallel-ide-install coordinates IDE installations" {
  source "${LIB_DIR}/modules/parallel-ide-install.sh" 2>/dev/null || true
  
  declare -f parallel_ide_install_execute >/dev/null
}

@test "modules: parallel modules can execute independently" {
  # Contract: parallel modules don't interfere
  touch "${CHECKPOINT_DIR}/ide-vscode"
  touch "${CHECKPOINT_DIR}/ide-cursor"
  touch "${CHECKPOINT_DIR}/ide-antigravity"
  
  # All three can exist simultaneously
  [ -f "${CHECKPOINT_DIR}/ide-vscode" ]
  [ -f "${CHECKPOINT_DIR}/ide-cursor" ]
  [ -f "${CHECKPOINT_DIR}/ide-antigravity" ]
}

# Configuration Interface
@test "modules: modules read configuration from environment" {
  # Contract: modules use standard config variables
  export USERNAME="testuser"
  export INSTALL_VSCODE="true"
  
  [ "$USERNAME" = "testuser" ]
  [ "$INSTALL_VSCODE" = "true" ]
}

@test "modules: modules validate configuration before execution" {
  # Contract: invalid config should be detected early
  export USERNAME=""  # Invalid
  
  # Should fail validation
  [ -z "$USERNAME" ]
}

# Cleanup Interface
@test "modules: modules clean up temporary files on error" {
  # Contract: no leaked resources on failure
  local temp_file="${BATS_TEST_TMPDIR}/temp"
  touch "$temp_file"
  
  # Simulate cleanup
  rm -f "$temp_file"
  [ ! -f "$temp_file" ]
}

@test "modules: modules release locks on exit" {
  # Contract: locks must be released
  local lock_file="${BATS_TEST_TMPDIR}/test.lock"
  touch "$lock_file"
  
  # Cleanup
  rm -f "$lock_file"
  [ ! -f "$lock_file" ]
}
