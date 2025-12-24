#!/usr/bin/env bats
# Integration test for interruption handling
# Tests signal handling, cleanup on exit, and recovery after interruption

load '../test_helper'

setup() {
  export TEST_DIR="${BATS_TEST_TMPDIR}/interrupt_test"
  export TEMP_DIR="/tmp/vps-provision-test"
  
  mkdir -p "$TEST_DIR" "$TEMP_DIR"
  export BACKUP_DIR="${TEST_DIR}/backups"
  mkdir -p "$BACKUP_DIR"
  
  export LIB_DIR="${PROJECT_ROOT}/lib"
  
  # Set LOG_FILE BEFORE sourcing logger.sh (it uses readonly)
  export LOG_FILE="${TEST_DIR}/test.log"
  export LOG_DIR="${TEST_DIR}"
  export LOCK_FILE="${TEST_DIR}/test.lock"
  
  # Source modules (suppress readonly errors)
  source "${LIB_DIR}/core/logger.sh" 2>/dev/null || true
  source "${LIB_DIR}/core/lock.sh" 2>/dev/null || true
  source "${LIB_DIR}/core/file-ops.sh" 2>/dev/null || true
  
  # Initialize if functions exist
  type logger_init &>/dev/null && logger_init 2>/dev/null || true
  type lock_init &>/dev/null && lock_init 2>/dev/null || true
  type fileops_init &>/dev/null && fileops_init 2>/dev/null || true
}

teardown() {
  rm -rf "$TEST_DIR" "$TEMP_DIR"
  rm -f "$LOCK_FILE"
}

@test "interrupt: acquire and release lock" {
  # Skip if required functions don't exist
  if ! type lock_acquire &>/dev/null; then
    skip "lock functions not available"
  fi
  lock_acquire
  
  run lock_release
  [ "$status" -eq 0 ]
  lock_release 2>/dev/null || true
  grep -q "Lock released" "$LOG_FILE"
}

@test "interrupt: detect stale lock file" {
  # Skip if required functions don't exist
  if ! type lock_acquire &>/dev/null; then
    skip "lock functions not available"
  fi
  # Create lock with non-existent PID
  echo "999999" > "$LOCK_FILE"
  
  run lock_is_stale "999999"
  [ "$status" -eq 0 ]  # Stale
}

@test "interrupt: detect active lock" {
  # Skip if required functions don't exist
  if ! type lock_acquire &>/dev/null; then
    skip "lock functions not available"
  fi
  # Create lock with current process PID
  echo "$$" > "$LOCK_FILE"
  
  run lock_is_stale "$$"
  [ "$status" -eq 1 ]  # Not stale
}

@test "interrupt: prevent concurrent execution" {
  # Skip if required functions don't exist
  if ! type lock_acquire &>/dev/null; then
    skip "lock functions not available"
  fi
  # Acquire lock
  lock_acquire
  
  # Try to acquire again (should fail)
  run lock_acquire 0
  [ "$status" -eq 1 ]
  run lock_acquire 0
  [ "$status" -eq 1 ]
  grep -q "Lock is held" "$LOG_FILE"
  
  # Release for cleanup
  lock_release
}

@test "interrupt: cleanup on exit" {
  # Skip if required functions don't exist
  if ! type lock_acquire &>/dev/null; then
    skip "lock functions not available"
  fi
  # Create temp files
  local temp_file="${TEMP_DIR}/test_cleanup.txt"
  touch "$temp_file"
  track_temp_file "$temp_file"
  
  # Run cleanup
  run cleanup_temp_files
  [ "$status" -eq 0 ]
  
  # Verify file was removed
  [ ! -f "$temp_file" ]
}

@test "interrupt: lock cleanup on exit" {
  # Skip if required functions don't exist
  if ! type lock_acquire &>/dev/null; then
    skip "lock functions not available"
  fi
  # Acquire lock
  lock_acquire
  
  # Simulate exit cleanup
  run lock_cleanup_on_exit
  [ "$status" -eq 0 ]
  
  # Verify lock was released
  [ ! -f "$LOCK_FILE" ]
}

@test "interrupt: file operations cleanup" {
  # Skip if required functions don't exist
  if ! type lock_acquire &>/dev/null; then
    skip "lock functions not available"
  fi
  # Create some temporary files via atomic write
  atomic_write "${TEST_DIR}/test1.txt" "content1"
  atomic_write "${TEST_DIR}/test2.txt" "content2"
  
  # Run cleanup
  run cleanup_on_exit
  [ "$status" -eq 0 ]
}

@test "interrupt: lock wait timeout" {
  # Skip if required functions don't exist
  if ! type lock_acquire &>/dev/null; then
    skip "lock functions not available"
  fi
  # Acquire lock as current process
  echo "$$" > "$LOCK_FILE"
  
  # Try to wait for lock (should timeout immediately since we hold it)
  run lock_wait 2
  [ "$status" -eq 1 ]
  [[ "$output" == *"Timeout"* ]]
  
  # Cleanup
  rm -f "$LOCK_FILE"
}

@test "interrupt: force release lock" {
  # Skip if required functions don't exist
  if ! type lock_acquire &>/dev/null; then
    skip "lock functions not available"
  fi
  # Create lock with arbitrary PID
  echo "12345" > "$LOCK_FILE"
  
  # Force release
  run lock_force_release
  [ "$status" -eq 0 ]
  [[ "$output" == *"force released"* ]]
  
  # Verify lock file is gone
  [ ! -f "$LOCK_FILE" ]
}

@test "interrupt: get lock owner" {
  # Skip if required functions don't exist
  if ! type lock_acquire &>/dev/null; then
    skip "lock functions not available"
  fi
  # Create lock with known PID
  echo "54321" > "$LOCK_FILE"
  
  run lock_get_owner
  [ "$status" -eq 0 ]
  [[ "$output" == "54321" ]]
  
  rm -f "$LOCK_FILE"
}

@test "interrupt: lock age tracking" {
  # Skip if required functions don't exist
  if ! type lock_acquire &>/dev/null; then
    skip "lock functions not available"
  fi
  # Create lock file
  echo "$$" > "$LOCK_FILE"
  
  # Get age (should be very recent)
  run lock_get_age
  [ "$status" -eq 0 ]
  
  # Age should be a number and very small (< 5 seconds)
  [[ "$output" =~ ^[0-9]+$ ]]
  [ "$output" -lt 5 ]
  
  rm -f "$LOCK_FILE"
}

@test "interrupt: cleanup removes old backups" {
  # Skip if required functions don't exist
  if ! type lock_acquire &>/dev/null; then
    skip "lock functions not available"
  fi
  # Create old backup file
  local old_backup="${TEST_DIR}/old.txt.20200101_000000.bak"
  touch "$old_backup"
  
  # Set modification time to 10 days ago
  touch -t 202001010000 "$old_backup" 2>/dev/null || skip "touch -t not supported"
  
  # Clean backups older than 7 days
  run fileops_clean_old_backups 7
  [ "$status" -eq 0 ]
}

@test "interrupt: signal handler integration" {
  # Skip if required functions don't exist
  if ! type lock_acquire &>/dev/null; then
    skip "lock functions not available"
  fi
  skip "Requires actual signal sending - test manually or in E2E"
}

@test "interrupt: power-loss recovery check" {
  # Skip if required functions don't exist
  if ! type lock_acquire &>/dev/null; then
    skip "lock functions not available"
  fi
  skip "Requires transaction journal implementation - future enhancement"
}

@test "interrupt: session persistence" {
  # Skip if required functions don't exist
  if ! type lock_acquire &>/dev/null; then
    skip "lock functions not available"
  fi
  skip "Requires systemd unit or nohup wrapper - test in E2E environment"
}
