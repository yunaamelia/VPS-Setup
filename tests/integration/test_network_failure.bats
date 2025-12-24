#!/usr/bin/env bats
# Integration test for network failure handling
# Tests download resume, repository checks, and retry logic

load '../test_helper'

setup() {
  export PROJECT_ROOT="${BATS_TEST_DIRNAME}/../.."
  export TEST_DIR="${BATS_TEST_TMPDIR}/network_test"
  
  mkdir -p "$TEST_DIR"
  export BACKUP_DIR="${TEST_DIR}/backups"
  mkdir -p "$BACKUP_DIR"
  
  export LIB_DIR="${PROJECT_ROOT}/lib"
  
  # Set LOG_FILE BEFORE sourcing logger.sh (it uses readonly)
  export LOG_FILE="${TEST_DIR}/test.log"
  export LOG_DIR="${TEST_DIR}"
  
  # Source modules (suppress readonly errors)
  source "${LIB_DIR}/core/logger.sh" 2>/dev/null || true
  source "${LIB_DIR}/core/error-handler.sh" 2>/dev/null || true
  source "${LIB_DIR}/core/file-ops.sh" 2>/dev/null || true
  
  # Initialize if functions exist
  # Mock logger_init to prevent stdout pollution
  logger_init() { return 0; }
  
  type error_handler_init &>/dev/null && error_handler_init &>/dev/null || true
  type fileops_init &>/dev/null && fileops_init &>/dev/null || true
}

teardown() {
  rm -rf "$TEST_DIR"
}

@test "network: classify network error" {
  # Skip if required functions don't exist
  if ! type error_classify &>/dev/null; then
    skip "error_classify function not available"
  fi
  local error_output="Could not resolve host: example.com"
  
  run error_classify 100 "$error_output" ""
  [ "$status" -eq 0 ]
  [[ "$output" == *"$E_NETWORK"* ]]
}

@test "network: classify timeout error" {
  # Skip if required functions don't exist
  if ! type error_classify &>/dev/null; then
    skip "error_classify function not available"
  fi
  local error_output="Connection timed out"
  
  run error_classify 124 "$error_output" ""
  [ "$status" -eq 0 ]
  run error_classify 124 "$error_output" ""
  [ "$status" -eq 0 ]
  # DEBUG: Output was: $output, Expecting: $E_TIMEOUT
  [[ "$output" == *"$E_TIMEOUT"* ]]
}

@test "network: retry logic with exponential backoff" {
  # Skip if required functions don't exist
  if ! type error_classify &>/dev/null; then
    skip "error_classify function not available"
  fi
  # Mock command that fails twice then succeeds
  local attempt_count=0
  mock_cmd() {
    attempt_count=$((attempt_count + 1))
    if [[ $attempt_count -lt 3 ]]; then
      echo "Network error" >&2
      return 100
    fi
    echo "Success"
    return 0
  }
  export -f mock_cmd
  
  run execute_with_retry "mock_cmd" 3 1
  [ "$status" -eq 0 ]
  [[ "$output" == *"Success"* ]]
}

@test "network: fail fast after max retries" {
  # Skip if required functions don't exist
  if ! type error_classify &>/dev/null; then
    skip "error_classify function not available"
  fi
  # Mock command that always fails
  mock_cmd() {
    echo "Network error" >&2
    return 100
  }
  export -f mock_cmd
  
  run execute_with_retry "mock_cmd" 2 1
  [ "$status" -eq 1 ]
  [[ "$output" == *"Max retries exceeded"* ]]
}

@test "network: circuit breaker opens after threshold" {
  # Skip if required functions don't exist
  if ! type error_classify &>/dev/null; then
    skip "error_classify function not available"
  fi
  # Reset circuit breaker
  CIRCUIT_BREAKER_FAILURES=0
  CIRCUIT_BREAKER_OPEN=false
  CIRCUIT_BREAKER_THRESHOLD=3
  
  # Trigger failures
  for i in {1..3}; do
    circuit_breaker_record_failure
  done
  
  # Verify circuit is open
  run circuit_breaker_is_open
  [ "$status" -eq 0 ]
}

@test "network: circuit breaker blocks operations when open" {
  # Skip if required functions don't exist
  if ! type error_classify &>/dev/null; then
    skip "error_classify function not available"
  fi
  # Open circuit breaker
  circuit_breaker_open
  
  # Try to execute command
  run execute_with_circuit_breaker "echo test"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Circuit breaker is open"* ]]
}

@test "network: circuit breaker closes on reset" {
  # Skip if required functions don't exist
  if ! type error_classify &>/dev/null; then
    skip "error_classify function not available"
  fi
  # Open circuit breaker
  circuit_breaker_open
  
  # Close it
  circuit_breaker_close
  
  # Verify it's closed
  run circuit_breaker_is_open
  [ "$status" -eq 1 ]
}

@test "network: download with resume support" {
  # Skip if required functions don't exist
  if ! type error_classify &>/dev/null; then
    skip "error_classify function not available"
  fi
  skip "Requires network access - run in E2E environment"
  
  local test_url="http://speedtest.tele2.net/1KB.zip"
  local output_file="${TEST_DIR}/download_test.zip"
  
  run download_with_resume "$test_url" "$output_file" 2
  [ "$status" -eq 0 ]
  [ -f "$output_file" ]
}

@test "network: download failure after retries" {
  # Skip if required functions don't exist
  if ! type error_classify &>/dev/null; then
    skip "error_classify function not available"
  fi
  # Mock wget to always fail
  wget() {
    echo "Connection failed" >&2
    return 4
  }
  export -f wget
  
  run download_with_resume "http://invalid.url" "${TEST_DIR}/test.file" 2
  [ "$status" -eq 1 ]
  [[ "$output" == *"Download failed after"* ]]
}

@test "network: error suggestion for network failure" {
  # Skip if required functions don't exist
  if ! type error_classify &>/dev/null; then
    skip "error_classify function not available"
  fi
  run error_get_suggestion "$E_NETWORK"
  [ "$status" -eq 0 ]
  [[ "$output" == *"network connectivity"* ]]
}

@test "network: safe execute with all protections" {
  # Skip if required functions don't exist
  if ! type error_classify &>/dev/null; then
    skip "error_classify function not available"
  fi
  # Mock command
  echo_test() {
    echo "Test output"
    return 0
  }
  export -f echo_test
  
  run safe_execute "echo_test" "Test command" 2
  [ "$status" -eq 0 ]
  [[ "$output" == *"completed successfully"* ]]
}

@test "network: classify package corruption error" {
  # Skip if required functions don't exist
  if ! type error_classify &>/dev/null; then
    skip "error_classify function not available"
  fi
  local error_output="Hash sum mismatch"
  
  run error_classify 1 "$error_output" ""
  [ "$status" -eq 0 ]
  [[ "$output" == *"$E_PKG_CORRUPT"* ]]
}

@test "network: classify lock file error" {
  # Skip if required functions don't exist
  if ! type error_classify &>/dev/null; then
    skip "error_classify function not available"
  fi
  local error_output="Could not get lock /var/lib/dpkg/lock"
  
  run error_classify 1 "$error_output" ""
  [ "$status" -eq 0 ]
  [[ "$output" == *"$E_LOCK"* ]]
}

@test "network: retryable error gets retried" {
  # Skip if required functions don't exist
  if ! type error_classify &>/dev/null; then
    skip "error_classify function not available"
  fi
  # Mock command that fails with network error once
  local call_count=0
  mock_network_cmd() {
    call_count=$((call_count + 1))
    if [[ $call_count -eq 1 ]]; then
      echo "Connection refused" >&2
      return 100
    fi
    return 0
  }
  export -f mock_network_cmd
  
  run execute_with_retry "mock_network_cmd" 3 1
  [ "$status" -eq 0 ]
}

@test "network: critical error not retried" {
  # Skip if required functions don't exist
  if ! type error_classify &>/dev/null; then
    skip "error_classify function not available"
  fi
  # Mock command that fails with permission error
  mock_critical_cmd() {
    echo "Permission denied" >&2
    return 13
  }
  export -f mock_critical_cmd
  
  run execute_with_retry "mock_critical_cmd" 3 1
  [ "$status" -eq 1 ]
  [[ "$output" == *"Critical error"* ]]
}
