#!/usr/bin/env bats
# test_logger.bats - Unit tests for logger.sh
# Tests logging initialization, levels, formatting, and redaction

load '../test_helper.bash'

setup() {
  # Create temporary directory for test logs
  export TEST_DIR="${BATS_TEST_TMPDIR}/logger_test_$$"
  mkdir -p "$TEST_DIR"
  
  export LOG_DIR="${TEST_DIR}/logs"
  export LOG_FILE="${LOG_DIR}/test.log"
  export TRANSACTION_LOG="${LOG_DIR}/transactions.log"
  export LOG_LEVEL="DEBUG"
  export ENABLE_COLORS="false"
  
  # Source logger module
  source "${PROJECT_ROOT}/lib/core/logger.sh" 2>/dev/null || true
}

teardown() {
  if [[ -n "${TEST_DIR:-}" ]] && [[ -d "$TEST_DIR" ]]; then
    rm -rf "$TEST_DIR"
  fi
}

@test "logger_init creates log directory and files" {
  logger_init "$LOG_DIR"
  
  [[ -d "$LOG_DIR" ]]
  [[ -f "$LOG_FILE" ]]
  [[ -f "$TRANSACTION_LOG" ]]
}

@test "logger_init fails with invalid directory" {
  LOG_DIR="/root/forbidden"
  run logger_init "$LOG_DIR"
  
  assert_failure
}

@test "_get_log_level_value returns correct numeric levels" {
  result=$(_get_log_level_value "DEBUG")
  [[ "$result" -eq 0 ]]
  
  result=$(_get_log_level_value "INFO")
  [[ "$result" -eq 1 ]]
  
  result=$(_get_log_level_value "WARNING")
  [[ "$result" -eq 2 ]]
  
  result=$(_get_log_level_value "ERROR")
  [[ "$result" -eq 3 ]]
}

@test "_format_log_message includes timestamp and label" {
  result=$(_format_log_message "INFO" "Test message")
  
  [[ "$result" =~ [0-9]{4}-[0-9]{2}-[0-9]{2} ]]
  [[ "$result" =~ \[OK\] ]]
  [[ "$result" =~ "Test message" ]]
}

@test "log_debug writes to file with DEBUG level" {
  logger_init "$LOG_DIR"
  LOG_LEVEL="DEBUG"
  
  log_debug "Debug message test"
  
  grep -q "Debug message test" "$LOG_FILE"
}

@test "log_debug is suppressed when LOG_LEVEL is INFO" {
  logger_init "$LOG_DIR"
  LOG_LEVEL="INFO"
  
  log_debug "Should not appear"
  
  ! grep -q "Should not appear" "$LOG_FILE"
}

@test "log_info writes to file" {
  logger_init "$LOG_DIR"
  
  log_info "Info message test"
  
  grep -q "Info message test" "$LOG_FILE"
  grep -q "\[OK\]" "$LOG_FILE"
}

@test "log_warning writes to file with WARNING label" {
  logger_init "$LOG_DIR"
  
  log_warning "Warning message test"
  
  grep -q "Warning message test" "$LOG_FILE"
  grep -q "\[WARN\]" "$LOG_FILE"
}

@test "log_error writes to file and stderr" {
  logger_init "$LOG_DIR"
  
  run log_error "Error message test"
  
  grep -q "Error message test" "$LOG_FILE"
  grep -q "\[ERR\]" "$LOG_FILE"
}

@test "log_fatal writes to file with FATAL label" {
  logger_init "$LOG_DIR"
  
  run log_fatal "Fatal error test"
  
  grep -q "Fatal error test" "$LOG_FILE"
  grep -q "\[FATAL\]" "$LOG_FILE"
}

@test "log_separator creates visual separator" {
  logger_init "$LOG_DIR"
  
  log_separator "="
  
  grep -q "========" "$LOG_FILE"
}

@test "log_redact_sensitive redacts passwords" {
  result=$(log_redact_sensitive "password=secret123")
  
  [[ "$result" == "password=[REDACTED]" ]]
}

@test "log_redact_sensitive redacts API keys" {
  result=$(log_redact_sensitive "api_key=sk_live_abc123")
  
  [[ "$result" == "api_key=[REDACTED]" ]]
}

@test "log_redact_sensitive redacts tokens" {
  result=$(log_redact_sensitive "token=ghp_abc123xyz")
  
  [[ "$result" == "token=[REDACTED]" ]]
}

@test "log_redact_sensitive preserves non-sensitive data" {
  result=$(log_redact_sensitive "username=testuser port=3389")
  
  [[ "$result" == "username=testuser port=3389" ]]
}

@test "NO_COLOR=1 disables color output" {
  NO_COLOR=1
  source "${PROJECT_ROOT}/lib/core/logger.sh" 2>/dev/null || true
  
  [[ "$ENABLE_COLORS" == "false" ]]
}

@test "log functions work without initialization" {
  # Should not crash when logger_init not called
  run log_info "Test without init"
  
  # May fail but should not crash
  [[ "$status" -eq 0 ]] || [[ "$status" -eq 1 ]]
}

@test "multiple log messages maintain order" {
  logger_init "$LOG_DIR"
  
  log_info "First message"
  log_warning "Second message"
  log_error "Third message"
  
  # Check order in log file
  lines=$(grep -E "First message|Second message|Third message" "$LOG_FILE")
  [[ $(echo "$lines" | head -1) =~ "First message" ]]
  [[ $(echo "$lines" | tail -1) =~ "Third message" ]]
}

@test "log_with_level respects level filtering" {
  logger_init "$LOG_DIR"
  LOG_LEVEL="WARNING"
  
  log_with_level "DEBUG" "Should not appear"
  log_with_level "WARNING" "Should appear"
  
  ! grep -q "Should not appear" "$LOG_FILE"
  grep -q "Should appear" "$LOG_FILE"
}

@test "logger handles long messages" {
  logger_init "$LOG_DIR"
  
  long_msg=$(printf 'A%.0s' {1..1000})
  log_info "$long_msg"
  
  grep -q "$long_msg" "$LOG_FILE"
}

@test "logger handles special characters in messages" {
  logger_init "$LOG_DIR"
  
  log_info 'Message with $special @characters & "quotes"'
  
  grep -q "special" "$LOG_FILE"
}

@test "log_transaction_entry writes to transaction log" {
  logger_init "$LOG_DIR"
  
  log_transaction_entry "test_action" "rollback_command"
  
  grep -q "test_action" "$TRANSACTION_LOG"
  grep -q "rollback_command" "$TRANSACTION_LOG"
}
