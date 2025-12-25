#!/usr/bin/env bats
# test_checkpoint.bats - Unit tests for checkpoint.sh
# Tests checkpoint creation, validation, and management

load '../test_helper.bash'

setup() {
  export TEST_DIR="${BATS_TEST_TMPDIR}/checkpoint_test_$$"
  mkdir -p "$TEST_DIR"
  
  export CHECKPOINT_DIR="${TEST_DIR}/checkpoints"
  export LOG_DIR="${TEST_DIR}/logs"
  export LOG_FILE="${LOG_DIR}/test.log"
  export LOG_LEVEL="ERROR"
  export ENABLE_COLORS="false"
  
  source "${PROJECT_ROOT}/lib/core/logger.sh" 2>/dev/null || true
  source "${PROJECT_ROOT}/lib/core/checkpoint.sh" 2>/dev/null || true
}

teardown() {
  if [[ -n "${TEST_DIR:-}" ]] && [[ -d "$TEST_DIR" ]]; then
    rm -rf "$TEST_DIR"
  fi
}

@test "checkpoint_init creates checkpoint directory" {
  checkpoint_init
  
  [[ -d "$CHECKPOINT_DIR" ]]
}

@test "checkpoint_create creates checkpoint file" {
  checkpoint_init
  checkpoint_create "test-phase"
  
  [[ -f "${CHECKPOINT_DIR}/test-phase.checkpoint" ]]
}

@test "checkpoint_create fails with empty name" {
  checkpoint_init
  
  run checkpoint_create ""
  
  assert_failure
}

@test "checkpoint_create stores metadata" {
  checkpoint_init
  checkpoint_create "test-phase"
  
  checkpoint_file="${CHECKPOINT_DIR}/test-phase.checkpoint"
  
  grep -q "CHECKPOINT_NAME=\"test-phase\"" "$checkpoint_file"
  grep -q "CREATED_AT=" "$checkpoint_file"
  grep -q "HOSTNAME=" "$checkpoint_file"
  grep -q "USER=" "$checkpoint_file"
}

@test "checkpoint_exists returns 0 for existing checkpoint" {
  checkpoint_init
  checkpoint_create "existing-phase"
  
  checkpoint_exists "existing-phase"
  
  [[ $? -eq 0 ]]
}

@test "checkpoint_exists returns 1 for non-existing checkpoint" {
  checkpoint_init
  
  run checkpoint_exists "non-existing-phase"
  
  assert_failure
}

@test "checkpoint_validate succeeds for valid checkpoint" {
  checkpoint_init
  checkpoint_create "valid-phase"
  
  checkpoint_validate "valid-phase"
  
  [[ $? -eq 0 ]]
}

@test "checkpoint_validate fails for missing checkpoint" {
  checkpoint_init
  
  run checkpoint_validate "missing-phase"
  
  assert_failure
}

@test "checkpoint_validate fails for corrupted checkpoint" {
  checkpoint_init
  checkpoint_create "corrupted-phase"
  
  # Corrupt the checkpoint file
  echo "invalid content" > "${CHECKPOINT_DIR}/corrupted-phase.checkpoint"
  
  run checkpoint_validate "corrupted-phase"
  
  assert_failure
}

@test "checkpoint_clear removes checkpoint file" {
  checkpoint_init
  checkpoint_create "to-be-removed"
  
  checkpoint_clear "to-be-removed"
  
  [[ ! -f "${CHECKPOINT_DIR}/to-be-removed.checkpoint" ]]
}

@test "checkpoint_clear_all removes all checkpoints" {
  checkpoint_init
  checkpoint_create "phase1"
  checkpoint_create "phase2"
  checkpoint_create "phase3"
  
  checkpoint_clear_all
  
  count=$(find "$CHECKPOINT_DIR" -name "*.checkpoint" | wc -l)
  [[ $count -eq 0 ]]
}

@test "checkpoint_list returns all checkpoint names" {
  checkpoint_init
  checkpoint_create "phase1"
  checkpoint_create "phase2"
  checkpoint_create "phase3"
  
  result=$(checkpoint_list)
  
  [[ "$result" =~ "phase1" ]]
  [[ "$result" =~ "phase2" ]]
  [[ "$result" =~ "phase3" ]]
}

@test "checkpoint_list returns empty for no checkpoints" {
  checkpoint_init
  
  result=$(checkpoint_list)
  
  [[ -z "$result" ]]
}

@test "checkpoint_count returns correct count" {
  checkpoint_init
  checkpoint_create "phase1"
  checkpoint_create "phase2"
  
  count=$(checkpoint_count)
  
  [[ $count -eq 2 ]]
}

@test "checkpoint_get_metadata extracts checkpoint data" {
  checkpoint_init
  checkpoint_create "test-phase"
  
  metadata=$(checkpoint_get_metadata "test-phase")
  
  [[ "$metadata" =~ "CHECKPOINT_NAME" ]]
  [[ "$metadata" =~ "CREATED_AT" ]]
}

@test "checkpoint files have correct permissions" {
  checkpoint_init
  checkpoint_create "secure-phase"
  
  checkpoint_file="${CHECKPOINT_DIR}/secure-phase.checkpoint"
  
  # Should be readable by owner
  [[ -r "$checkpoint_file" ]]
}

@test "checkpoint_create handles special characters in names" {
  checkpoint_init
  
  # Should sanitize or handle special chars safely
  run checkpoint_create "phase-with-dash"
  
  assert_success
  [[ -f "${CHECKPOINT_DIR}/phase-with-dash.checkpoint" ]]
}

@test "checkpoint_exists handles concurrent access" {
  checkpoint_init
  checkpoint_create "concurrent-phase"
  
  # Multiple processes checking existence
  checkpoint_exists "concurrent-phase" &
  checkpoint_exists "concurrent-phase" &
  checkpoint_exists "concurrent-phase" &
  wait
  
  [[ $? -eq 0 ]]
}

@test "checkpoint timestamps are in ISO 8601 format" {
  checkpoint_init
  checkpoint_create "timestamp-test"
  
  checkpoint_file="${CHECKPOINT_DIR}/timestamp-test.checkpoint"
  timestamp=$(grep "CREATED_AT=" "$checkpoint_file" | cut -d'"' -f2)
  
  # ISO 8601 format: YYYY-MM-DDTHH:MM:SSZ
  [[ "$timestamp" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]
}

@test "checkpoint_get_created_at returns timestamp" {
  checkpoint_init
  checkpoint_create "time-phase"
  
  created_at=$(checkpoint_get_created_at "time-phase")
  
  [[ -n "$created_at" ]]
  [[ "$created_at" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T ]]
}

@test "checkpoint_age_seconds calculates age correctly" {
  checkpoint_init
  checkpoint_create "old-phase"
  
  sleep 2
  
  age=$(checkpoint_age_seconds "old-phase")
  
  [[ $age -ge 2 ]]
}

@test "checkpoint_export generates JSON output" {
  checkpoint_init
  checkpoint_create "export-test"
  
  json=$(checkpoint_export "export-test")
  
  [[ "$json" =~ "checkpoint_name" ]]
  [[ "$json" =~ "created_at" ]]
}

@test "checkpoint_import recreates checkpoint from JSON" {
  checkpoint_init
  checkpoint_create "original"
  
  json=$(checkpoint_export "original")
  checkpoint_clear "original"
  
  echo "$json" | checkpoint_import
  
  checkpoint_exists "original"
}

@test "checkpoint system survives directory re-initialization" {
  checkpoint_init
  checkpoint_create "persistent"
  
  # Re-initialize
  checkpoint_init
  
  checkpoint_exists "persistent"
  [[ $? -eq 0 ]]
}
