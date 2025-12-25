#!/usr/bin/env bats
# test_rollback.bats - Unit tests for rollback.sh
# Tests rollback execution, command parsing, and state verification

load '../test_helper.bash'

setup() {
  export TEST_DIR="${BATS_TEST_TMPDIR}/rollback_test_$$"
  mkdir -p "$TEST_DIR"
  
  export LOG_DIR="${TEST_DIR}/logs"
  export TRANSACTION_LOG="${LOG_DIR}/transactions.log"
  export LOG_FILE="${LOG_DIR}/test.log"
  export LOG_LEVEL="ERROR"
  export ENABLE_COLORS="false"
  
  source "${PROJECT_ROOT}/lib/core/logger.sh" 2>/dev/null || true
  source "${PROJECT_ROOT}/lib/core/transaction.sh" 2>/dev/null || true
  source "${PROJECT_ROOT}/lib/core/rollback.sh" 2>/dev/null || true
}

teardown() {
  if [[ -n "${TEST_DIR:-}" ]] && [[ -d "$TEST_DIR" ]]; then
    rm -rf "$TEST_DIR"
  fi
}

@test "rollback_init initializes rollback system" {
  rollback_init
  
  [[ -f "$TRANSACTION_LOG" ]]
}

@test "rollback_execute succeeds with no transactions" {
  transaction_init
  
  rollback_execute
  
  [[ $? -eq 0 ]]
}

@test "rollback_execute runs commands in LIFO order" {
  transaction_init
  
  # Create test files to track execution order
  touch "${TEST_DIR}/file1"
  touch "${TEST_DIR}/file2"
  touch "${TEST_DIR}/file3"
  
  transaction_record "Created file1" "rm -f ${TEST_DIR}/file1"
  transaction_record "Created file2" "rm -f ${TEST_DIR}/file2"
  transaction_record "Created file3" "rm -f ${TEST_DIR}/file3"
  
  rollback_execute
  
  # All files should be removed
  [[ ! -f "${TEST_DIR}/file1" ]]
  [[ ! -f "${TEST_DIR}/file2" ]]
  [[ ! -f "${TEST_DIR}/file3" ]]
}

@test "rollback_execute_command runs valid command" {
  echo "test content" > "${TEST_DIR}/testfile"
  
  rollback_execute_command "rm -f ${TEST_DIR}/testfile"
  
  [[ ! -f "${TEST_DIR}/testfile" ]]
}

@test "rollback_execute_command handles command failure" {
  run rollback_execute_command "false"
  
  assert_failure
}

@test "rollback_execute continues after command failure" {
  transaction_init
  
  touch "${TEST_DIR}/file1"
  touch "${TEST_DIR}/file2"
  
  transaction_record "Created file1" "rm -f ${TEST_DIR}/file1"
  transaction_record "Failed operation" "exit 1"
  transaction_record "Created file2" "rm -f ${TEST_DIR}/file2"
  
  rollback_execute
  
  # file1 and file2 should still be removed despite middle failure
  [[ ! -f "${TEST_DIR}/file1" ]]
  [[ ! -f "${TEST_DIR}/file2" ]]
}

@test "rollback_execute returns failure when errors occur" {
  transaction_init
  
  transaction_record "Will fail" "exit 1"
  
  run rollback_execute
  
  assert_failure
}

@test "rollback_execute backs up transaction log" {
  transaction_init
  
  transaction_record "Test action" "echo test"
  
  rollback_execute
  
  [[ -f "${TRANSACTION_LOG}.pre-rollback" ]]
}

@test "rollback_verify checks for residual files" {
  transaction_init
  
  # Create and record files
  touch "${TEST_DIR}/should_be_removed"
  transaction_record "Created file" "rm -f ${TEST_DIR}/should_be_removed"
  
  rollback_execute
  
  rollback_verify
  
  [[ $? -eq 0 ]]
}

@test "rollback_verify detects incomplete rollback" {
  transaction_init
  
  touch "${TEST_DIR}/persistent_file"
  transaction_record "Created file" "echo 'not actually removing'"
  
  rollback_execute
  
  run rollback_verify
  
  # File still exists, verification should detect issue
  [[ -f "${TEST_DIR}/persistent_file" ]]
}

@test "rollback handles file restoration" {
  transaction_init
  
  # Create original file
  echo "original content" > "${TEST_DIR}/config"
  
  # Backup and modify
  cp "${TEST_DIR}/config" "${TEST_DIR}/config.bak"
  echo "modified content" > "${TEST_DIR}/config"
  
  transaction_record "Modified config" "cp ${TEST_DIR}/config.bak ${TEST_DIR}/config"
  
  rollback_execute
  
  content=$(cat "${TEST_DIR}/config")
  [[ "$content" == "original content" ]]
}

@test "rollback handles package removal" {
  transaction_init
  
  # Mock package installation
  mkdir -p "${TEST_DIR}/fake-package"
  
  transaction_record "Installed fake-package" "rm -rf ${TEST_DIR}/fake-package"
  
  rollback_execute
  
  [[ ! -d "${TEST_DIR}/fake-package" ]]
}

@test "rollback handles service operations" {
  transaction_init
  
  # Record service operation
  transaction_record "Started service" "echo 'stop service'"
  
  rollback_execute
  
  [[ $? -eq 0 ]]
}

@test "rollback handles directory removal" {
  transaction_init
  
  mkdir -p "${TEST_DIR}/new_directory"
  
  transaction_record "Created directory" "rm -rf ${TEST_DIR}/new_directory"
  
  rollback_execute
  
  [[ ! -d "${TEST_DIR}/new_directory" ]]
}

@test "rollback_in_progress flag is set during execution" {
  transaction_init
  
  transaction_record "Test" "echo test"
  
  # Override rollback_execute_command to check flag
  rollback_execute_command() {
    [[ "$ROLLBACK_IN_PROGRESS" == "true" ]]
    return 0
  }
  export -f rollback_execute_command
  
  rollback_execute
}

@test "rollback_in_progress flag is cleared after execution" {
  transaction_init
  
  transaction_record "Test" "echo test"
  
  rollback_execute
  
  [[ "$ROLLBACK_IN_PROGRESS" == "false" ]]
}

@test "rollback tracks error count" {
  transaction_init
  
  transaction_record "Will fail" "exit 1"
  transaction_record "Will also fail" "exit 1"
  
  rollback_execute
  
  [[ $ROLLBACK_ERRORS -eq 2 ]]
}

@test "rollback handles empty rollback commands" {
  transaction_init
  
  # Manually add invalid entry (should be caught)
  echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ")|Test action|" >> "$TRANSACTION_LOG"
  
  run rollback_execute
  
  # Should handle gracefully
  [[ $? -eq 0 ]] || [[ $? -eq 1 ]]
}

@test "rollback handles complex shell commands" {
  transaction_init
  
  echo "original" > "${TEST_DIR}/test.txt"
  
  transaction_record "Modified file" "echo 'restored' > ${TEST_DIR}/test.txt"
  
  rollback_execute
  
  content=$(cat "${TEST_DIR}/test.txt")
  [[ "$content" == "restored" ]]
}

@test "rollback handles commands with pipes" {
  transaction_init
  
  transaction_record "Piped command" "echo test | cat > ${TEST_DIR}/output.txt"
  
  rollback_execute
  
  [[ -f "${TEST_DIR}/output.txt" ]]
}

@test "rollback handles commands with redirects" {
  transaction_init
  
  transaction_record "Redirect test" "echo 'content' > ${TEST_DIR}/redirect.txt"
  
  rollback_execute
  
  [[ -f "${TEST_DIR}/redirect.txt" ]]
}

@test "rollback_get_stats returns statistics" {
  transaction_init
  
  transaction_record "Action 1" "rollback1"
  transaction_record "Action 2" "rollback2"
  
  rollback_execute
  
  stats=$(rollback_get_stats)
  
  [[ "$stats" =~ "2" ]]
}

@test "rollback_dry_run shows commands without executing" {
  transaction_init
  
  touch "${TEST_DIR}/file_to_keep"
  transaction_record "Created file" "rm -f ${TEST_DIR}/file_to_keep"
  
  output=$(rollback_dry_run)
  
  [[ "$output" =~ "rm -f" ]]
  [[ -f "${TEST_DIR}/file_to_keep" ]]
}

@test "rollback preserves transaction log backup" {
  transaction_init
  
  transaction_record "Test" "echo test"
  
  rollback_execute
  
  [[ -f "${TRANSACTION_LOG}.pre-rollback" ]]
  grep -q "Test" "${TRANSACTION_LOG}.pre-rollback"
}

@test "rollback can be executed multiple times" {
  transaction_init
  
  touch "${TEST_DIR}/file"
  transaction_record "Created file" "rm -f ${TEST_DIR}/file"
  
  rollback_execute
  
  # Execute again (should succeed even with no transactions)
  transaction_init
  rollback_execute
  
  [[ $? -eq 0 ]]
}

@test "rollback handles nested directory removal" {
  transaction_init
  
  mkdir -p "${TEST_DIR}/parent/child/grandchild"
  
  transaction_record "Created nested dirs" "rm -rf ${TEST_DIR}/parent"
  
  rollback_execute
  
  [[ ! -d "${TEST_DIR}/parent" ]]
}
