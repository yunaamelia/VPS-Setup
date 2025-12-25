#!/usr/bin/env bats
# test_state.bats - Unit tests for state.sh
# Tests session state management, phase tracking, and persistence

load '../test_helper.bash'

setup() {
  export TEST_DIR="${BATS_TEST_TMPDIR}/state_test_$$"
  mkdir -p "$TEST_DIR"
  
  export VPS_PROVISION_STATE_DIR="${TEST_DIR}/state"
  export LOG_DIR="${TEST_DIR}/logs"
  export LOG_FILE="${LOG_DIR}/test.log"
  export LOG_LEVEL="ERROR"
  export ENABLE_COLORS="false"
  
  source "${PROJECT_ROOT}/lib/core/logger.sh" 2>/dev/null || true
  source "${PROJECT_ROOT}/lib/core/config.sh" 2>/dev/null || true
  source "${PROJECT_ROOT}/lib/core/state.sh" 2>/dev/null || true
}

teardown() {
  if [[ -n "${TEST_DIR:-}" ]] && [[ -d "$TEST_DIR" ]]; then
    rm -rf "$TEST_DIR"
  fi
}

@test "state_init_dirs creates required directories" {
  state_init_dirs
  
  [[ -d "${VPS_PROVISION_STATE_DIR}/sessions" ]]
  [[ -d "${VPS_PROVISION_STATE_DIR}/checkpoints" ]]
}

@test "state_init_dirs creates checkpoint metadata file" {
  state_init_dirs
  
  [[ -f "${VPS_PROVISION_STATE_DIR}/checkpoints/metadata.json" ]]
}

@test "state_generate_session_id generates valid format" {
  session_id=$(state_generate_session_id)
  
  [[ "$session_id" =~ ^[0-9]{8}-[0-9]{6}$ ]]
}

@test "state_init_session creates session file" {
  session_id=$(state_init_session)
  
  [[ -n "$session_id" ]]
  [[ -f "${VPS_PROVISION_STATE_DIR}/sessions/session-${session_id}.json" ]]
}

@test "state_init_session generates valid JSON" {
  session_id=$(state_init_session)
  session_file="${VPS_PROVISION_STATE_DIR}/sessions/session-${session_id}.json"
  
  # Validate JSON structure
  grep -q '"session_id"' "$session_file"
  grep -q '"start_time"' "$session_file"
  grep -q '"status"' "$session_file"
  grep -q '"INITIALIZING"' "$session_file"
}

@test "state_init_session sets current session variables" {
  session_id=$(state_init_session)
  
  [[ "$CURRENT_SESSION_ID" == "$session_id" ]]
  [[ -n "$CURRENT_SESSION_FILE" ]]
}

@test "state_load_session loads existing session" {
  session_id=$(state_init_session)
  
  # Clear current session
  CURRENT_SESSION_ID=""
  CURRENT_SESSION_FILE=""
  
  state_load_session "$session_id"
  
  [[ "$CURRENT_SESSION_ID" == "$session_id" ]]
}

@test "state_load_session fails for non-existent session" {
  run state_load_session "nonexistent-session"
  
  assert_failure
}

@test "state_save_session updates session file" {
  session_id=$(state_init_session)
  
  # Modify in-memory state
  export SESSION_STATUS="IN_PROGRESS"
  
  state_save_session
  
  grep -q "IN_PROGRESS" "$CURRENT_SESSION_FILE"
}

@test "state_update_phase adds phase to session" {
  session_id=$(state_init_session)
  
  state_update_phase "system-prep" "IN_PROGRESS"
  
  grep -q "system-prep" "$CURRENT_SESSION_FILE"
}

@test "state_update_phase tracks phase status" {
  session_id=$(state_init_session)
  
  state_update_phase "desktop-env" "COMPLETED"
  
  session_file="$CURRENT_SESSION_FILE"
  
  grep -q "desktop-env" "$session_file"
  grep -q "COMPLETED" "$session_file"
}

@test "state_get_phase_status returns correct status" {
  session_id=$(state_init_session)
  
  state_update_phase "test-phase" "IN_PROGRESS"
  
  status=$(state_get_phase_status "test-phase")
  
  [[ "$status" == "IN_PROGRESS" ]]
}

@test "state_set_session_status updates session status" {
  session_id=$(state_init_session)
  
  state_set_session_status "COMPLETED"
  
  grep -q "COMPLETED" "$CURRENT_SESSION_FILE"
}

@test "state_set_error_details records error information" {
  session_id=$(state_init_session)
  
  state_set_error_details "Test error message"
  
  grep -q "Test error message" "$CURRENT_SESSION_FILE"
}

@test "state_get_session_duration calculates elapsed time" {
  session_id=$(state_init_session)
  
  sleep 2
  
  duration=$(state_get_session_duration)
  
  [[ $duration -ge 2 ]]
}

@test "state_finalize_session sets end time and duration" {
  session_id=$(state_init_session)
  
  sleep 1
  
  state_finalize_session "COMPLETED"
  
  session_file="$CURRENT_SESSION_FILE"
  
  grep -q "end_time" "$session_file"
  grep -q "duration_seconds" "$session_file"
  ! grep -q '"end_time": null' "$session_file"
}

@test "state_list_sessions returns all sessions" {
  state_init_session
  sleep 1
  state_init_session
  
  sessions=$(state_list_sessions)
  
  # Should have at least 2 sessions
  count=$(echo "$sessions" | wc -l)
  [[ $count -ge 2 ]]
}

@test "state_get_latest_session returns most recent session" {
  state_init_session
  sleep 1
  second_session=$(state_init_session)
  
  latest=$(state_get_latest_session)
  
  [[ "$latest" == "$second_session" ]]
}

@test "state_delete_session removes session file" {
  session_id=$(state_init_session)
  session_file="$CURRENT_SESSION_FILE"
  
  state_delete_session "$session_id"
  
  [[ ! -f "$session_file" ]]
}

@test "state_export_session generates JSON output" {
  session_id=$(state_init_session)
  
  json=$(state_export_session "$session_id")
  
  [[ "$json" =~ "session_id" ]]
  [[ "$json" =~ "start_time" ]]
  [[ "$json" =~ "status" ]]
}

@test "state_import_session restores session from JSON" {
  session_id=$(state_init_session)
  
  json=$(state_export_session "$session_id")
  
  state_delete_session "$session_id"
  
  echo "$json" | state_import_session
  
  state_load_session "$session_id"
  [[ $? -eq 0 ]]
}

@test "state tracks multiple phases in order" {
  session_id=$(state_init_session)
  
  state_update_phase "phase1" "COMPLETED"
  state_update_phase "phase2" "IN_PROGRESS"
  state_update_phase "phase3" "PENDING"
  
  session_file="$CURRENT_SESSION_FILE"
  
  grep -q "phase1" "$session_file"
  grep -q "phase2" "$session_file"
  grep -q "phase3" "$session_file"
}

@test "state preserves VPS info" {
  session_id=$(state_init_session)
  
  state_set_vps_info "hostname" "test-vps"
  state_set_vps_info "ip_address" "192.168.1.100"
  
  session_file="$CURRENT_SESSION_FILE"
  
  grep -q "test-vps" "$session_file"
  grep -q "192.168.1.100" "$session_file"
}

@test "state preserves developer user info" {
  session_id=$(state_init_session)
  
  state_set_developer_user "testuser"
  
  grep -q "testuser" "$CURRENT_SESSION_FILE"
}

@test "state tracks IDE installations" {
  session_id=$(state_init_session)
  
  state_add_ide_installation "vscode" "1.85.0" "COMPLETED"
  state_add_ide_installation "cursor" "0.12.0" "COMPLETED"
  
  session_file="$CURRENT_SESSION_FILE"
  
  grep -q "vscode" "$session_file"
  grep -q "cursor" "$session_file"
}

@test "state handles concurrent session creation" {
  # Multiple sessions created in quick succession should have unique IDs
  session1=$(state_init_session)
  sleep 1
  session2=$(state_init_session)
  
  [[ "$session1" != "$session2" ]]
}

@test "state_cleanup removes old sessions" {
  # Create multiple sessions
  state_init_session
  sleep 1
  state_init_session
  sleep 1
  current=$(state_init_session)
  
  # Clean up sessions older than 1 second (keep only current)
  state_cleanup_old_sessions 1
  
  # Current session should still exist
  state_load_session "$current"
  [[ $? -eq 0 ]]
}

@test "state_validate_session checks session integrity" {
  session_id=$(state_init_session)
  
  state_validate_session "$session_id"
  
  [[ $? -eq 0 ]]
}

@test "state_validate_session fails for corrupted session" {
  session_id=$(state_init_session)
  
  # Corrupt the session file
  echo "invalid json" > "$CURRENT_SESSION_FILE"
  
  run state_validate_session "$session_id"
  
  assert_failure
}

@test "state persists across process restarts" {
  session_id=$(state_init_session)
  state_update_phase "test-phase" "COMPLETED"
  
  # Unload state module
  unset CURRENT_SESSION_ID
  unset CURRENT_SESSION_FILE
  
  # Reload and verify
  source "${PROJECT_ROOT}/lib/core/state.sh" 2>/dev/null || true
  state_load_session "$session_id"
  
  status=$(state_get_phase_status "test-phase")
  [[ "$status" == "COMPLETED" ]]
}

@test "state handles missing state directory gracefully" {
  rm -rf "$VPS_PROVISION_STATE_DIR"
  
  state_init_session
  
  [[ $? -eq 0 ]]
  [[ -d "$VPS_PROVISION_STATE_DIR" ]]
}

@test "state_get_all_phases returns phase list" {
  session_id=$(state_init_session)
  
  state_update_phase "phase1" "COMPLETED"
  state_update_phase "phase2" "IN_PROGRESS"
  
  phases=$(state_get_all_phases)
  
  [[ "$phases" =~ "phase1" ]]
  [[ "$phases" =~ "phase2" ]]
}

@test "state handles ISO 8601 timestamps correctly" {
  session_id=$(state_init_session)
  
  session_file="$CURRENT_SESSION_FILE"
  timestamp=$(grep '"start_time"' "$session_file" | cut -d'"' -f4)
  
  [[ "$timestamp" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]
}
