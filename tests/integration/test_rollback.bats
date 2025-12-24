#!/usr/bin/env bats
# Integration test for rollback mechanism
# Tests rollback execution, verification, and system state restoration

load '../test_helper'

setup() {
  export TEST_DIR="${BATS_TEST_TMPDIR}/rollback_test"
  export LOG_FILE="${TEST_DIR}/test.log"
  export TRANSACTION_LOG="${TEST_DIR}/transactions.log"
  export CHECKPOINT_DIR="${TEST_DIR}/checkpoints"
  
  mkdir -p "$TEST_DIR" "$CHECKPOINT_DIR"
  
  # Source modules
  source "${LIB_DIR}/core/logger.sh"
  source "${LIB_DIR}/core/transaction.sh"
  source "${LIB_DIR}/core/rollback.sh"
  
  # Initialize
  logger_init
  transaction_init
  rollback_init
}

teardown() {
  rm -rf "$TEST_DIR"
}

@test "rollback: execute rollback for recorded transactions" {
  # Record some test transactions
  transaction_record "Create test file" "rm -f ${TEST_DIR}/testfile.txt"
  touch "${TEST_DIR}/testfile.txt"
  
  transaction_record "Create test dir" "rmdir ${TEST_DIR}/testdir"
  mkdir "${TEST_DIR}/testdir"
  
  # Verify files exist before rollback
  [ -f "${TEST_DIR}/testfile.txt" ]
  [ -d "${TEST_DIR}/testdir" ]
  
  # Execute rollback
  run rollback_execute
  [ "$status" -eq 0 ]
  
  # Verify files were removed
  [ ! -f "${TEST_DIR}/testfile.txt" ]
  [ ! -d "${TEST_DIR}/testdir" ]
}

@test "rollback: handle empty transaction log" {
  # Clear transaction log
  > "$TRANSACTION_LOG"
  
  run rollback_execute
  [ "$status" -eq 0 ]
  [[ "$output" == *"No transactions to rollback"* ]]
}

@test "rollback: continue on non-critical rollback failure" {
  # Record transactions - one will fail
  transaction_record "Remove existing file" "rm -f ${TEST_DIR}/exists.txt"
  transaction_record "Remove nonexistent file" "rm -f ${TEST_DIR}/nonexistent.txt"
  
  # Create only one file
  touch "${TEST_DIR}/exists.txt"
  
  # Execute rollback - should complete despite one failure
  run rollback_execute
  [ "$status" -eq 1 ]  # Returns 1 due to errors, but continues
  [[ "$output" == *"Rollback completed with"*"error"* ]]
}

@test "rollback: verify system state after rollback" {
  # Record transaction to create test directory
  transaction_record "Create directory" "rmdir ${TEST_DIR}/verification_test"
  mkdir "${TEST_DIR}/verification_test"
  
  # Execute rollback
  rollback_execute
  
  # Verify clean state
  run rollback_verify
  [ "$status" -eq 0 ]
  [[ "$output" == *"system state is clean"* ]]
}

@test "rollback: backup transaction log before rollback" {
  # Record a transaction
  transaction_record "Test action" "echo rollback"
  
  # Execute rollback
  rollback_execute
  
  # Verify backup was created
  [ -f "${TRANSACTION_LOG}.pre-rollback" ]
}

@test "rollback: LIFO order (last in, first out)" {
  # Create test file to track order
  local order_file="${TEST_DIR}/rollback_order.txt"
  
  # Record transactions in specific order
  transaction_record "Action 1" "echo 'Rollback 1' >> ${order_file}"
  transaction_record "Action 2" "echo 'Rollback 2' >> ${order_file}"
  transaction_record "Action 3" "echo 'Rollback 3' >> ${order_file}"
  
  # Execute rollback
  rollback_execute
  
  # Verify LIFO order (3, 2, 1)
  [ -f "$order_file" ]
  local first_line=$(head -1 "$order_file")
  [[ "$first_line" == "Rollback 3" ]]
}

@test "rollback: dry-run shows commands without executing" {
  # Record test transactions
  transaction_record "Test 1" "echo test1"
  transaction_record "Test 2" "echo test2"
  
  # Run dry-run
  run rollback_dry_run
  [ "$status" -eq 0 ]
  [[ "$output" == *"echo test2"* ]]
  [[ "$output" == *"echo test1"* ]]
  
  # Verify transactions still exist (not executed)
  local count
  count=$(transaction_count)
  [ "$count" -eq 2 ]
}

@test "rollback: complete rollback with verification" {
  # Record and execute transactions
  transaction_record "Create test" "rm -f ${TEST_DIR}/complete_test.txt"
  touch "${TEST_DIR}/complete_test.txt"
  
  # Run complete rollback
  run rollback_complete
  [ "$status" -eq 0 ]
  
  # Verify file removed
  [ ! -f "${TEST_DIR}/complete_test.txt" ]
  
  # Verify transaction log cleared
  local count
  count=$(transaction_count)
  [ "$count" -eq 0 ]
}

@test "rollback: interactive mode (simulated yes)" {
  # Record test transaction
  transaction_record "Test" "echo rollback"
  
  # Simulate user input "yes"
  run bash -c "echo 'yes' | rollback_interactive"
  [ "$status" -eq 0 ]
}

@test "rollback: force release stale lock" {
  skip "Requires implementation of lock integration"
}
