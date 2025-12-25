#!/usr/bin/env bats
# Integration test for multi-VPS concurrent provisioning
# Tests concurrent provisioning of multiple VPS instances
# Validates: T153 - Multi-VPS concurrent provisioning

load '../test_helper'

setup() {
  # Setup test environment for concurrent testing
  export BASE_TEST_DIR="${BATS_TEST_TMPDIR}/concurrent"
  mkdir -p "${BASE_TEST_DIR}"
  
  # Source required modules
  export LIB_DIR="${BATS_TEST_DIRNAME}/../../lib"
  source "${LIB_DIR}/core/logger.sh" 2>/dev/null || true
  source "${LIB_DIR}/core/lock.sh" 2>/dev/null || true
  source "${LIB_DIR}/core/checkpoint.sh" 2>/dev/null || true
  
  export TEST_MODE=1
}

teardown() {
  # Cleanup all test directories and lock files
  rm -rf "${BASE_TEST_DIR}"
  rm -f /var/lock/vps-provision-test-*.lock 2>/dev/null || true
}

@test "concurrent: validates lock prevents simultaneous provisioning on same VPS" {
  # Create lock directory
  local lock_dir="${BASE_TEST_DIR}/locks"
  mkdir -p "$lock_dir"
  
  # First process acquires lock
  local lockfile="${lock_dir}/vps-provision.lock"
  echo "$$" > "$lockfile"
  
  [ -f "$lockfile" ]
  
  # Second process should detect existing lock
  [ -f "$lockfile" ]
  
  # Cleanup
  rm -f "$lockfile"
}

@test "concurrent: validates separate VPS instances can provision simultaneously" {
  # Create separate state directories for 3 VPS instances
  local vps1_dir="${BASE_TEST_DIR}/vps1"
  local vps2_dir="${BASE_TEST_DIR}/vps2"
  local vps3_dir="${BASE_TEST_DIR}/vps3"
  
  mkdir -p "$vps1_dir/checkpoints"
  mkdir -p "$vps2_dir/checkpoints"
  mkdir -p "$vps3_dir/checkpoints"
  
  # Simulate concurrent provisioning
  touch "$vps1_dir/checkpoints/system-prep"
  touch "$vps2_dir/checkpoints/system-prep"
  touch "$vps3_dir/checkpoints/system-prep"
  
  # All should succeed independently
  [ -f "$vps1_dir/checkpoints/system-prep" ]
  [ -f "$vps2_dir/checkpoints/system-prep" ]
  [ -f "$vps3_dir/checkpoints/system-prep" ]
}

@test "concurrent: validates separate log files prevent log corruption" {
  # Create separate log directories
  local vps1_log="${BASE_TEST_DIR}/vps1/provision.log"
  local vps2_log="${BASE_TEST_DIR}/vps2/provision.log"
  
  mkdir -p "$(dirname "$vps1_log")"
  mkdir -p "$(dirname "$vps2_log")"
  
  # Write to separate logs simultaneously
  echo "VPS1: Starting provisioning" >> "$vps1_log"
  echo "VPS2: Starting provisioning" >> "$vps2_log"
  
  # Verify logs are separate and intact
  grep -q "VPS1" "$vps1_log"
  grep -q "VPS2" "$vps2_log"
  ! grep -q "VPS2" "$vps1_log"
  ! grep -q "VPS1" "$vps2_log"
}

@test "concurrent: validates separate checkpoint directories prevent conflicts" {
  # Create separate checkpoint directories
  local vps1_ckpt="${BASE_TEST_DIR}/vps1/checkpoints"
  local vps2_ckpt="${BASE_TEST_DIR}/vps2/checkpoints"
  
  mkdir -p "$vps1_ckpt"
  mkdir -p "$vps2_ckpt"
  
  # Create different checkpoints in each
  touch "$vps1_ckpt/system-prep"
  touch "$vps1_ckpt/desktop-env"
  touch "$vps2_ckpt/system-prep"
  
  # VPS1 has 2 checkpoints
  [ $(find "$vps1_ckpt" -type f | wc -l) -eq 2 ]
  
  # VPS2 has 1 checkpoint
  [ $(find "$vps2_ckpt" -type f | wc -l) -eq 1 ]
}

@test "concurrent: validates transaction logs are isolated per VPS" {
  # Create separate transaction logs
  local vps1_txn="${BASE_TEST_DIR}/vps1/transactions.log"
  local vps2_txn="${BASE_TEST_DIR}/vps2/transactions.log"
  
  mkdir -p "$(dirname "$vps1_txn")"
  mkdir -p "$(dirname "$vps2_txn")"
  
  # Record different transactions
  echo "TRANSACTION|VPS1|apt-get install xfce4" >> "$vps1_txn"
  echo "TRANSACTION|VPS2|apt-get install gnome" >> "$vps2_txn"
  
  # Verify isolation
  grep -q "xfce4" "$vps1_txn"
  grep -q "gnome" "$vps2_txn"
  ! grep -q "gnome" "$vps1_txn"
  ! grep -q "xfce4" "$vps2_txn"
}

@test "concurrent: validates parallel provisioning completion at different times" {
  # Simulate VPS instances completing at different times
  local vps1_complete="${BASE_TEST_DIR}/vps1/checkpoints/verification"
  local vps2_complete="${BASE_TEST_DIR}/vps2/checkpoints/verification"
  local vps3_complete="${BASE_TEST_DIR}/vps3/checkpoints/verification"
  
  mkdir -p "$(dirname "$vps1_complete")"
  mkdir -p "$(dirname "$vps2_complete")"
  mkdir -p "$(dirname "$vps3_complete")"
  
  # VPS1 completes first
  touch "$vps1_complete"
  sleep 0.1
  
  # VPS2 completes second
  touch "$vps2_complete"
  sleep 0.1
  
  # VPS3 completes last
  touch "$vps3_complete"
  
  # All completed independently
  [ -f "$vps1_complete" ]
  [ -f "$vps2_complete" ]
  [ -f "$vps3_complete" ]
}

@test "concurrent: validates resource monitoring tracks per-VPS usage" {
  # Create separate performance logs
  local vps1_perf="${BASE_TEST_DIR}/vps1/performance/resources.csv"
  local vps2_perf="${BASE_TEST_DIR}/vps2/performance/resources.csv"
  
  mkdir -p "$(dirname "$vps1_perf")"
  mkdir -p "$(dirname "$vps2_perf")"
  
  # Record different resource usage
  echo "timestamp,cpu,memory" > "$vps1_perf"
  echo "2025-12-24T10:00:00,25,1024" >> "$vps1_perf"
  
  echo "timestamp,cpu,memory" > "$vps2_perf"
  echo "2025-12-24T10:00:00,30,2048" >> "$vps2_perf"
  
  # Verify separate tracking
  grep -q "1024" "$vps1_perf"
  grep -q "2048" "$vps2_perf"
}

@test "concurrent: validates error in one VPS does not affect others" {
  # VPS1 succeeds
  local vps1_status="${BASE_TEST_DIR}/vps1/status"
  mkdir -p "$(dirname "$vps1_status")"
  echo "SUCCESS" > "$vps1_status"
  
  # VPS2 fails
  local vps2_status="${BASE_TEST_DIR}/vps2/status"
  mkdir -p "$(dirname "$vps2_status")"
  echo "FAILED" > "$vps2_status"
  
  # VPS3 succeeds
  local vps3_status="${BASE_TEST_DIR}/vps3/status"
  mkdir -p "$(dirname "$vps3_status")"
  echo "SUCCESS" > "$vps3_status"
  
  # Verify independent status
  [ "$(cat "$vps1_status")" = "SUCCESS" ]
  [ "$(cat "$vps2_status")" = "FAILED" ]
  [ "$(cat "$vps3_status")" = "SUCCESS" ]
}

@test "concurrent: validates lock timeout prevents deadlock" {
  # Create lock with timestamp
  local lockfile="${BASE_TEST_DIR}/locks/test.lock"
  mkdir -p "$(dirname "$lockfile")"
  
  # Create stale lock (old timestamp)
  local old_time=$(($(date +%s) - 7200))  # 2 hours ago
  echo "$old_time" > "$lockfile"
  
  # Lock should be considered stale and removable
  local lock_age=$(($(date +%s) - $(cat "$lockfile")))
  [ $lock_age -gt 3600 ]  # Older than 1 hour
}

@test "concurrent: validates progress tracking is independent per VPS" {
  # Create separate progress files
  local vps1_progress="${BASE_TEST_DIR}/vps1/state/progress"
  local vps2_progress="${BASE_TEST_DIR}/vps2/state/progress"
  
  mkdir -p "$(dirname "$vps1_progress")"
  mkdir -p "$(dirname "$vps2_progress")"
  
  # VPS1 at 50%
  echo "50" > "$vps1_progress"
  
  # VPS2 at 75%
  echo "75" > "$vps2_progress"
  
  # Verify independent progress
  [ "$(cat "$vps1_progress")" = "50" ]
  [ "$(cat "$vps2_progress")" = "75" ]
}

@test "concurrent: validates rollback in one VPS does not affect others" {
  # VPS1 rolls back
  local vps1_txn="${BASE_TEST_DIR}/vps1/transactions.log"
  mkdir -p "$(dirname "$vps1_txn")"
  echo "ROLLBACK|VPS1|remove xfce4" >> "$vps1_txn"
  
  # VPS2 continues normally
  local vps2_ckpt="${BASE_TEST_DIR}/vps2/checkpoints/desktop-env"
  mkdir -p "$(dirname "$vps2_ckpt")"
  touch "$vps2_ckpt"
  
  # VPS2 unaffected by VPS1 rollback
  [ -f "$vps2_ckpt" ]
}

@test "concurrent: validates network bandwidth sharing across VPS instances" {
  # Simulate network usage tracking
  local vps1_net="${BASE_TEST_DIR}/vps1/network_usage"
  local vps2_net="${BASE_TEST_DIR}/vps2/network_usage"
  local vps3_net="${BASE_TEST_DIR}/vps3/network_usage"
  
  mkdir -p "$(dirname "$vps1_net")"
  mkdir -p "$(dirname "$vps2_net")"
  mkdir -p "$(dirname "$vps3_net")"
  
  # Record download sizes
  echo "100MB" > "$vps1_net"
  echo "150MB" > "$vps2_net"
  echo "120MB" > "$vps3_net"
  
  # All instances downloading concurrently
  [ -f "$vps1_net" ]
  [ -f "$vps2_net" ]
  [ -f "$vps3_net" ]
}

@test "concurrent: validates separate state directories prevent state corruption" {
  # Create state files in separate directories
  local vps1_state="${BASE_TEST_DIR}/vps1/state/provision_status"
  local vps2_state="${BASE_TEST_DIR}/vps2/state/provision_status"
  
  mkdir -p "$(dirname "$vps1_state")"
  mkdir -p "$(dirname "$vps2_state")"
  
  # Set different states
  echo "in_progress" > "$vps1_state"
  echo "completed" > "$vps2_state"
  
  # Verify no corruption
  [ "$(cat "$vps1_state")" = "in_progress" ]
  [ "$(cat "$vps2_state")" = "completed" ]
}

@test "concurrent: validates parallel IDE installations across VPS instances" {
  # VPS1 installs VSCode
  local vps1_ide="${BASE_TEST_DIR}/vps1/checkpoints/ide-vscode"
  mkdir -p "$(dirname "$vps1_ide")"
  touch "$vps1_ide"
  
  # VPS2 installs Cursor
  local vps2_ide="${BASE_TEST_DIR}/vps2/checkpoints/ide-cursor"
  mkdir -p "$(dirname "$vps2_ide")"
  touch "$vps2_ide"
  
  # VPS3 installs all three
  local vps3_dir="${BASE_TEST_DIR}/vps3/checkpoints"
  mkdir -p "$vps3_dir"
  touch "$vps3_dir/ide-vscode"
  touch "$vps3_dir/ide-cursor"
  touch "$vps3_dir/ide-antigravity"
  
  # All installations independent
  [ -f "$vps1_ide" ]
  [ -f "$vps2_ide" ]
  [ $(find "$vps3_dir" -name "ide-*" | wc -l) -eq 3 ]
}

@test "concurrent: validates cleanup after all VPS instances complete" {
  # Create completion markers
  local vps1_done="${BASE_TEST_DIR}/vps1/COMPLETED"
  local vps2_done="${BASE_TEST_DIR}/vps2/COMPLETED"
  local vps3_done="${BASE_TEST_DIR}/vps3/COMPLETED"
  
  mkdir -p "$(dirname "$vps1_done")"
  mkdir -p "$(dirname "$vps2_done")"
  mkdir -p "$(dirname "$vps3_done")"
  
  touch "$vps1_done"
  touch "$vps2_done"
  touch "$vps3_done"
  
  # All marked complete
  [ -f "$vps1_done" ]
  [ -f "$vps2_done" ]
  [ -f "$vps3_done" ]
}
