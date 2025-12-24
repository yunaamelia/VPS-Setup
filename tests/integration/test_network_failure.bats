#!/usr/bin/env bats
# Integration test for network failure handling
# Tests download resume, repository checks, and retry logic

load '../test_helper'

setup() {
  export TEST_DIR="${BATS_TEST_TMPDIR}/network_test"
  export LOG_FILE="${TEST_DIR}/test.log"
  
  mkdir -p "$TEST_DIR"
  
  # Source modules
  source "${LIB_DIR}/core/logger.sh"
  source "${LIB_DIR}/core/error-handler.sh"
  source "${LIB_DIR}/core/file-ops.sh"
  
  logger_init
  error_handler_init
  fileops_init
}

teardown() {
  rm -rf "$TEST_DIR"
}

@test "network: classify network error" {
  local error_output="Could not resolve host: example.com"
  
  run error_classify 100 "$error_output" ""
  [ "$status" -eq 0 ]
  [[ "$output" == "$E_NETWORK" ]]
}

@test "network: classify timeout error" {
  local error_output="Connection timed out"
  
  run error_classify 124 "$error_output" ""
  [ "$status" -eq 0 ]
  [[ "$output" == "$E_TIMEOUT" ]]
}

@test "network: retry logic with exponential backoff" {
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
  # Open circuit breaker
  circuit_breaker_open
  
  # Try to execute command
  run execute_with_circuit_breaker "echo test"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Circuit breaker is open"* ]]
}

@test "network: circuit breaker closes on reset" {
  # Open circuit breaker
  circuit_breaker_open
  
  # Close it
  circuit_breaker_close
  
  # Verify it's closed
  run circuit_breaker_is_open
  [ "$status" -eq 1 ]
}

@test "network: download with resume support" {
  skip "Requires network access - run in E2E environment"
  
  local test_url="http://speedtest.tele2.net/1KB.zip"
  local output_file="${TEST_DIR}/download_test.zip"
  
  run download_with_resume "$test_url" "$output_file" 2
  [ "$status" -eq 0 ]
  [ -f "$output_file" ]
}

@test "network: download failure after retries" {
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
  run error_get_suggestion "$E_NETWORK"
  [ "$status" -eq 0 ]
  [[ "$output" == *"network connectivity"* ]]
}

@test "network: safe execute with all protections" {
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
  local error_output="Hash sum mismatch"
  
  run error_classify 1 "$error_output" ""
  [ "$status" -eq 0 ]
  [[ "$output" == "$E_PKG_CORRUPT" ]]
}

@test "network: classify lock file error" {
  local error_output="Could not get lock /var/lib/dpkg/lock"
  
  run error_classify 1 "$error_output" ""
  [ "$status" -eq 0 ]
  [[ "$output" == "$E_LOCK" ]]
}

@test "network: retryable error gets retried" {
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
