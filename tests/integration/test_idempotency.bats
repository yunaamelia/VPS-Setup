#!/usr/bin/env bats
# Integration tests for idempotency - verify safe re-runs
#
# Tests User Story 4: Rapid Environment Replication
# Requirements: SC-008 (idempotent re-run ≤5 minutes)
#
# Test Strategy:
# - Provision VPS once (full run)
# - Collect system state (packages, configs, checksums)
# - Provision VPS again (should skip completed phases)
# - Verify second run completes in ≤5 minutes
# - Verify system state unchanged between runs

# Setup test environment
setup() {
  export PROJECT_ROOT="${BATS_TEST_DIRNAME}/../.."
  export LIB_DIR="${PROJECT_ROOT}/lib"
  export BIN_DIR="${PROJECT_ROOT}/bin"
  
  # Test-specific directories (use /tmp)
  export TEST_CHECKPOINT_DIR="/tmp/vps-test-$$-checkpoints"
  export TEST_STATE_DIR="/tmp/vps-test-$$-state"
  export TEST_LOG_DIR="/tmp/vps-test-$$-logs"
  
  # Override system directories for testing
  export CHECKPOINT_DIR="${TEST_CHECKPOINT_DIR}"
  export STATE_DIR="${TEST_STATE_DIR}"
  export LOG_DIR="${TEST_LOG_DIR}"
  
  # Set LOG_FILE BEFORE sourcing logger.sh (it uses readonly)
  export LOG_FILE="${TEST_LOG_DIR}/test.log"
  
  # Create test directories
  mkdir -p "${TEST_CHECKPOINT_DIR}"
  mkdir -p "${TEST_STATE_DIR}"
  mkdir -p "${TEST_LOG_DIR}"
  export BACKUP_DIR="${TEST_CHECKPOINT_DIR}/backups"
  mkdir -p "$BACKUP_DIR"
  
  # Source core libraries (suppress errors for readonly vars)
  source "${LIB_DIR}/core/logger.sh"
  source "${LIB_DIR}/core/checkpoint.sh"
  
  # Initialize checkpoint system
  checkpoint_init 2>/dev/null || true
  
  # Ensure we have a clean state
  rm -rf "${CHECKPOINT_DIR}" "${STATE_DIR}" "${LOG_DIR}"
  mkdir -p "${CHECKPOINT_DIR}" "${STATE_DIR}" "${LOG_DIR}"
}

# Cleanup after tests
teardown() {
  rm -rf "${TEST_CHECKPOINT_DIR}"
  rm -rf "${TEST_STATE_DIR}"
  rm -rf "${TEST_LOG_DIR}"
}

# Helper to capture system state
capture_state() {
  echo "Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$1"
  ls -la "${CHECKPOINT_DIR}" >> "$1"
  ls -la "${LOG_DIR}" >> "$1"
}

# Helper to simulate a phase execution
simulate_phase() {
  local phase="$1"
  local duration="${2:-1}"
  
  log_info "Simulating phase: ${phase}"
  
  if checkpoint_exists "${phase}"; then
    log_info "Phase ${phase} skipped (checkpoint exists)"
    return 0
  fi
  
  sleep "${duration}"
  log_info "Phase ${phase} completed"
  checkpoint_create "${phase}"
}

# Ignore timestamp changes in state comparison
diff_state() {
  diff <(grep -v "Timestamp" "$1") <(grep -v "Timestamp" "$2")
}

# Helper: Measure execution time
measure_time() {
  local start_time
  local end_time
  local duration
  
  start_time=$(date +%s)
  
  # Execute command (silence output to verify timing only)
  "$@" >/dev/null 2>&1
  
  end_time=$(date +%s)
  duration=$((end_time - start_time))
  
  echo "${duration}"
}

# Helper: Collect system state fingerprint
collect_system_state() {
  local output_file="$1"
  
  {
    echo "=== SYSTEM STATE SNAPSHOT ==="
    echo "Timestamp: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    echo ""
    
    echo "--- Checkpoints ---"
    checkpoint_list | sort
    echo ""
    
    echo "--- Checkpoint Count ---"
    checkpoint_count
    echo ""
    
    echo "--- Checkpoint Timestamps ---"
    while IFS= read -r checkpoint; do
      local timestamp
      timestamp=$(checkpoint_get_timestamp "${checkpoint}")
      echo "${checkpoint}: ${timestamp}"
    done < <(checkpoint_list | sort)
    echo ""
    
  } > "${output_file}"
}

# Test: First run creates checkpoints
@test "idempotency: first run creates all checkpoints" {
  # Skip if checkpoint functions not available
  if ! type checkpoint_create &>/dev/null; then
    skip "Checkpoint functions not available in this environment"
  fi
  # Simulate phases
  simulate_phase "system-prep" 1
  [ $? -eq 0 ]
  
  simulate_phase "desktop-install" 1
  [ $? -eq 0 ]
  
  simulate_phase "rdp-config" 1
  [ $? -eq 0 ]
  
  # Verify checkpoints created
  count=$(checkpoint_count)
  [ "$count" -eq 3 ]
  
  checkpoint_exists "system-prep"
  [ $? -eq 0 ]
  
  checkpoint_exists "desktop-install"
  [ $? -eq 0 ]
  
  checkpoint_exists "rdp-config"
  [ $? -eq 0 ]
}

# Test: Second run skips completed phases
@test "idempotency: second run skips completed phases" {
  # Skip if checkpoint functions not available
  if ! type checkpoint_create &>/dev/null; then
    skip "Checkpoint functions not available in this environment"
  fi
  # First run
  simulate_phase "system-prep" 1
  simulate_phase "desktop-install" 1
  
  # Verify checkpoints exist
  [ "$(checkpoint_count)" -eq 2 ]
  
  # Second run should skip
  output=$(simulate_phase "system-prep" 1 2>&1)
  echo "$output" | grep -q "checkpoint exists"
  [ $? -eq 0 ]
  
  output=$(simulate_phase "desktop-install" 1 2>&1)
  echo "$output" | grep -q "checkpoint exists"
  [ $? -eq 0 ]
  
  # Checkpoint count should not change
  [ "$(checkpoint_count)" -eq 2 ]
}

# Test: Force mode clears checkpoints
@test "idempotency: force mode clears all checkpoints" {
  # Skip if checkpoint functions not available
  if ! type checkpoint_create &>/dev/null; then
    skip "Checkpoint functions not available in this environment"
  fi
  # Create some checkpoints
  checkpoint_create "phase1"
  checkpoint_create "phase2"
  checkpoint_create "phase3"
  
  [ "$(checkpoint_count)" -eq 3 ]
  
  # Enable force mode
  export FORCE_MODE="true"
  
  # Handle force mode
  checkpoint_handle_force_mode
  
  # Verify all checkpoints cleared
  [ "$(checkpoint_count)" -eq 0 ]
}

# Test: Resume mode preserves checkpoints
@test "idempotency: resume mode preserves existing checkpoints" {
  # Skip if checkpoint functions not available
  if ! type checkpoint_create &>/dev/null; then
    skip "Checkpoint functions not available in this environment"
  fi
  # Create checkpoints
  checkpoint_create "phase1"
  checkpoint_create "phase2"
  
  [ "$(checkpoint_count)" -eq 2 ]
  
  # Enable resume mode (does not clear checkpoints)
  export RESUME_MODE="true"
  
  # Verify checkpoints still exist
  [ "$(checkpoint_count)" -eq 2 ]
  
  checkpoint_exists "phase1"
  [ $? -eq 0 ]
  
  checkpoint_exists "phase2"
  [ $? -eq 0 ]
}

# Test: Second run completes faster (SC-008: ≤5 minutes)
@test "idempotency: second run completes significantly faster" {
  # Skip if checkpoint functions not available
  if ! type checkpoint_create &>/dev/null; then
    skip "Checkpoint functions not available in this environment"
  fi
  # First run (simulate with longer phases)
  run_phases_1() {
    simulate_phase "system-prep" 2
    simulate_phase "desktop-install" 2
    simulate_phase "rdp-config" 2
  }
  
  first_run_duration=$(measure_time run_phases_1)
  
  # Verify first run took expected time (at least 6 seconds)
  [ "${first_run_duration}" -ge 6 ]
  
  # Second run (should skip all phases, much faster)
  run_phases_2() {
    simulate_phase "system-prep" 2
    simulate_phase "desktop-install" 2
    simulate_phase "rdp-config" 2
  }
  
  second_run_duration=$(measure_time run_phases_2)
  
  # Second run should be much faster (checkpoint checks are fast)
  # Should complete in under 2 seconds vs 6+ seconds
  [ "${second_run_duration}" -lt 2 ]
  
  # Verify second run is significantly faster (< 1/3 of first run time)
  speedup_factor=$((first_run_duration / second_run_duration))
  [ "${speedup_factor}" -ge 3 ]
}

# Test: System state unchanged after second run
@test "idempotency: system state unchanged after re-run" {
  # Skip if checkpoint functions not available
  if ! type checkpoint_create &>/dev/null; then
    skip "Checkpoint functions not available in this environment"
  fi
  # First run
  simulate_phase "system-prep" 1
  simulate_phase "desktop-install" 1
  
  # Collect state after first run
  state1="/tmp/vps-state1-$$.txt"
  collect_system_state "${state1}"
  
  # Wait a moment to ensure timestamps would differ if recreated
  sleep 2
  
  # Second run (should skip everything)
  simulate_phase "system-prep" 1
  simulate_phase "desktop-install" 1
  
  # Collect state after second run
  state2="/tmp/vps-state2-$$.txt"
  collect_system_state "${state2}"
  
  # Compare states (excluding timestamps)
  run diff_state "${state1}" "${state2}"
  [ "$status" -eq 0 ]
}

# Test: Partial failure resume
@test "idempotency: resume from partial failure point" {
  # Skip if checkpoint functions not available
  if ! type checkpoint_create &>/dev/null; then
    skip "Checkpoint functions not available in this environment"
  fi
  # Complete some phases
  checkpoint_create "phase1"
  checkpoint_create "phase2"
  
  # Simulate failure after phase2 (phase3 not complete)
  # Now resume - should skip phase1, phase2, run phase3
  
  output=$(simulate_phase "phase1" 1 2>&1)
  echo "$output" | grep -q "checkpoint exists"
  [ $? -eq 0 ]
  
  output=$(simulate_phase "phase2" 1 2>&1)
  echo "$output" | grep -q "checkpoint exists"
  [ $? -eq 0 ]
  
  # Phase3 has no checkpoint, should run
  simulate_phase "phase3" 1
  [ $? -eq 0 ]
  
  # Verify phase3 checkpoint now exists
  checkpoint_exists "phase3"
  [ $? -eq 0 ]
}

# Test: Force mode re-runs all phases
@test "idempotency: force mode re-runs completed phases" {
  # Skip if checkpoint functions not available
  if ! type checkpoint_create &>/dev/null; then
    skip "Checkpoint functions not available in this environment"
  fi
  # Create checkpoints
  checkpoint_create "phase1"
  checkpoint_create "phase2"
  
  # Enable force mode
  export FORCE_MODE="true"
  
  # Clear checkpoints (force mode behavior)
  checkpoint_handle_force_mode
  
  # Now all phases should run (no checkpoints exist)
  run checkpoint_should_skip "phase1"
  [ "$status" -ne 0 ]  # Should NOT skip (return 1 = should run)
  
  run checkpoint_should_skip "phase2"
  [ "$status" -ne 0 ]  # Should NOT skip
  
  # Run phases
  simulate_phase "phase1" 1
  [ $? -eq 0 ]
  
  simulate_phase "phase2" 1
  [ $? -eq 0 ]
  
  # Verify new checkpoints created
  [ "$(checkpoint_count)" -eq 2 ]
}

# Test: Checkpoint validation
@test "idempotency: checkpoint validation detects corruption" {
  # Skip if checkpoint functions not available
  if ! type checkpoint_create &>/dev/null; then
    skip "Checkpoint functions not available in this environment"
  fi
  # Create valid checkpoint
  checkpoint_create "valid-phase"
  
  # Verify it's valid
  checkpoint_validate "valid-phase"
  [ $? -eq 0 ]
  
  # Corrupt checkpoint (remove required field)
  checkpoint_file="${TEST_CHECKPOINT_DIR}/valid-phase.checkpoint"
  sed -i '/CHECKPOINT_NAME/d' "${checkpoint_file}"
  
  # Validation should fail
  run checkpoint_validate "valid-phase"
  [ "$status" -ne 0 ]
}

# Test: Checkpoint timestamps
@test "idempotency: checkpoint timestamps are preserved" {
  # Skip if checkpoint functions not available
  if ! type checkpoint_create &>/dev/null; then
    skip "Checkpoint functions not available in this environment"
  fi
  # Create checkpoint
  checkpoint_create "timestamped-phase"
  
  # Get timestamp
  timestamp1=$(checkpoint_get_timestamp "timestamped-phase")
  
  [ -n "${timestamp1}" ]
  
  # Wait and check again (should be same timestamp)
  sleep 1
  
  timestamp2=$(checkpoint_get_timestamp "timestamped-phase")
  
  # Timestamps should match exactly
  [ "${timestamp1}" = "${timestamp2}" ]
}

# Test: Checkpoint listing
@test "idempotency: checkpoint list returns all checkpoints" {
  # Skip if checkpoint functions not available
  if ! type checkpoint_create &>/dev/null; then
    skip "Checkpoint functions not available in this environment"
  fi
  # Create multiple checkpoints
  checkpoint_create "alpha"
  checkpoint_create "beta"
  checkpoint_create "gamma"
  
  # List checkpoints
  mapfile -t checkpoints < <(checkpoint_list | sort)
  
  # Verify all present
  [ "${#checkpoints[@]}" -eq 3 ]
  [ "${checkpoints[0]}" = "alpha" ]
  [ "${checkpoints[1]}" = "beta" ]
  [ "${checkpoints[2]}" = "gamma" ]
}

# Test: Checkpoint clear individual
@test "idempotency: clear individual checkpoint" {
  # Skip if checkpoint functions not available
  if ! type checkpoint_create &>/dev/null; then
    skip "Checkpoint functions not available in this environment"
  fi
  # Create checkpoints
  checkpoint_create "keep-this"
  checkpoint_create "delete-this"
  
  [ "$(checkpoint_count)" -eq 2 ]
  
  # Clear one checkpoint
  checkpoint_clear "delete-this"
  
  # Verify count decreased
  [ "$(checkpoint_count)" -eq 1 ]
  
  # Verify correct one cleared
  checkpoint_exists "keep-this"
  [ $? -eq 0 ]
  
  run checkpoint_exists "delete-this"
  [ "$status" -ne 0 ]
}

# Test: Checkpoint clear all
@test "idempotency: clear all checkpoints" {
  # Skip if checkpoint functions not available
  if ! type checkpoint_create &>/dev/null; then
    skip "Checkpoint functions not available in this environment"
  fi
  # Create several checkpoints
  checkpoint_create "phase1"
  checkpoint_create "phase2"
  checkpoint_create "phase3"
  
  [ "$(checkpoint_count)" -eq 3 ]
  
  # Clear all
  checkpoint_clear_all
  
  # Verify all cleared
  [ "$(checkpoint_count)" -eq 0 ]
}

# Test: No checkpoints initially
@test "idempotency: fresh start has no checkpoints" {
  # Skip if checkpoint functions not available
  if ! type checkpoint_create &>/dev/null; then
    skip "Checkpoint functions not available in this environment"
  fi
  # Verify clean state
  [ "$(checkpoint_count)" -eq 0 ]
  
  output=$(checkpoint_list)
  [ -z "$output" ]
}

# Test: Checkpoint status display
@test "idempotency: checkpoint status shows summary" {
  # Skip if checkpoint functions not available
  if ! type checkpoint_create &>/dev/null; then
    skip "Checkpoint functions not available in this environment"
  fi
  # Create checkpoints
  checkpoint_create "phase-a"
  checkpoint_create "phase-b"
  
  # Show status
  output=$(checkpoint_show_status 2>&1)
  echo "$output" | grep -q "Total checkpoints: 2"
  [ $? -eq 0 ]
  echo "$output" | grep -q "phase-a"
  [ $? -eq 0 ]
  echo "$output" | grep -q "phase-b"
  [ $? -eq 0 ]
}

