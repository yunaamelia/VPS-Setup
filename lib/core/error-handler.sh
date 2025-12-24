#!/bin/bash
# error-handler.sh - Error detection, classification, and recovery framework
# Implements error classification, retry logic, circuit breaker, and exit code validation
#
# Usage:
#   source lib/core/error-handler.sh
#   error_handler_init
#   execute_with_retry "apt-get update" 3 2
#
# Dependencies:
#   - lib/core/logger.sh

set -euo pipefail

# Prevent multiple sourcing
if [[ -n "${_ERROR_HANDLER_SH_LOADED:-}" ]]; then
  return 0
fi
readonly _ERROR_HANDLER_SH_LOADED=1

# Source dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/core/logger.sh
source "${SCRIPT_DIR}/logger.sh"

# Error severity levels
readonly E_SEVERITY_CRITICAL="CRITICAL"


# Error types
readonly E_NETWORK="E_NETWORK"
readonly E_DISK="E_DISK"
readonly E_LOCK="E_LOCK"
readonly E_PKG_CORRUPT="E_PKG_CORRUPT"
readonly E_PERMISSION="E_PERMISSION"
readonly E_NOT_FOUND="E_NOT_FOUND"
readonly E_TIMEOUT="E_TIMEOUT"
readonly E_UNKNOWN="E_UNKNOWN"

# Circuit breaker state
declare -g CIRCUIT_BREAKER_FAILURES=0
declare -g CIRCUIT_BREAKER_THRESHOLD=5
declare -g CIRCUIT_BREAKER_OPEN=false
declare -g CIRCUIT_BREAKER_RESET_TIME=300  # 5 minutes

# Whitelisted exit codes (considered success)
readonly -a EXIT_CODE_WHITELIST=(
  0    # Success
  141  # SIGPIPE (broken pipe, often benign)
)

# Error suggestion mappings (UX-008: actionable suggestions)
readonly -A ERROR_SUGGESTIONS=(
  ["$E_NETWORK"]="Check internet connection and DNS resolution. Verify firewall rules."
  ["$E_DISK"]="Free up disk space by removing unnecessary files or expanding storage."
  ["$E_LOCK"]="Wait a moment and retry. Another package manager may be running."
  ["$E_PKG_CORRUPT"]="Clear package cache with 'apt-get clean' and retry installation."
  ["$E_PERMISSION"]="Ensure script is running with root/sudo privileges."
  ["$E_NOT_FOUND"]="Install missing dependency or check command spelling."
  ["$E_TIMEOUT"]="Increase timeout or check system load and network stability."
  ["$E_UNKNOWN"]="Review error details above and check system logs."
)

# Initialize error handler
error_handler_init() {
  log_debug "Error handler initialized"
  CIRCUIT_BREAKER_FAILURES=0
  CIRCUIT_BREAKER_OPEN=false
}

# Classify error based on exit code and output
# Args: $1 - exit code, $2 - stderr output, $3 - stdout output
# Returns: error type constant
error_classify() {
  local exit_code="$1"
  local stderr="${2:-}"
  local stdout="${3:-}"
  local combined="${stderr} ${stdout}"
  
  # Network-related errors
  if [[ "$exit_code" -eq 100 ]] || \
     echo "$combined" | grep -qiE "(connection.*refused|timed out|network.*unreachable|could not resolve|failed to fetch)"; then
    echo "$E_NETWORK"
    return 0
  fi
  
  # Disk space errors
  if [[ "$exit_code" -eq 28 ]] || \
     echo "$combined" | grep -qiE "(no space left|disk.*full|write error|filesystem.*full)"; then
    echo "$E_DISK"
    return 0
  fi
  
  # Lock file errors
  if echo "$combined" | grep -qiE "(could not get lock|unable to lock|locked by another process|dpkg.*lock)"; then
    echo "$E_LOCK"
    return 0
  fi
  
  # Package corruption
  if echo "$combined" | grep -qiE "(hash sum mismatch|corrupted package|failed to verify|signature.*invalid)"; then
    echo "$E_PKG_CORRUPT"
    return 0
  fi
  
  # Permission errors
  if [[ "$exit_code" -eq 1 ]] || [[ "$exit_code" -eq 13 ]] || \
     echo "$combined" | grep -qiE "(permission denied|operation not permitted|access denied)"; then
    echo "$E_PERMISSION"
    return 0
  fi
  
  # Not found errors
  if [[ "$exit_code" -eq 127 ]] || \
     echo "$combined" | grep -qiE "(command not found|no such file)"; then
    echo "$E_NOT_FOUND"
    return 0
  fi
  
  # Timeout errors
  if [[ "$exit_code" -eq 124 ]] || \
     echo "$combined" | grep -qiE "(timeout|timed out)"; then
    echo "$E_TIMEOUT"
    return 0
  fi
  
  echo "$E_UNKNOWN"
  return 0
}

# Get error severity based on error type
# Args: $1 - error type
# Returns: severity level (FATAL, ERROR, WARNING per UX-011)
error_get_severity() {
  local error_type="$1"
  
  case "$error_type" in
    "$E_NETWORK"|"$E_LOCK"|"$E_TIMEOUT"|"$E_PKG_CORRUPT")
      echo "ERROR"  # Retryable but still an error
      ;;
    "$E_DISK"|"$E_PERMISSION"|"$E_NOT_FOUND")
      echo "FATAL"  # Critical, abort immediately
      ;;
    *)
      echo "WARNING"  # Non-fatal informational
      ;;
  esac
}

# Get actionable suggestion for error type (UX-008)
# Args: $1 - error type
# Returns: suggestion text
error_get_suggestion() {
  local error_type="$1"
  echo "${ERROR_SUGGESTIONS[$error_type]:-Review error details and consult documentation.}"
}

# Format standardized error message (UX-007)
# Args: $1 - severity, $2 - message, $3 - suggestion (optional)
# Output: [SEVERITY] <Message>\n > Suggested Action
error_format_message() {
  local severity="$1"
  local message="$2"
  local suggestion="${3:-}"
  
  echo "[$severity] $message"
  if [[ -n "$suggestion" ]]; then
    echo " > $suggestion"
  fi
}

# Check if exit code is whitelisted
# Args: $1 - exit code
# Returns: 0 if whitelisted, 1 otherwise
error_exit_code_whitelisted() {
  local exit_code="$1"
  local allowed_code
  
  for allowed_code in "${EXIT_CODE_WHITELIST[@]}"; do
    if [[ "$exit_code" -eq "$allowed_code" ]]; then
      return 0
    fi
  done
  
  return 1
}

# Validate command exit code with formatted error output (UX-007, UX-008, UX-011)
# Args: $1 - exit code, $2 - command description, $3 - stderr, $4 - stdout
# Returns: 0 if valid, 1 otherwise
error_validate_exit_code() {
  local exit_code="$1"
  local description="${2:-command}"
  local stderr="${3:-}"
  local stdout="${4:-}"
  
  if error_exit_code_whitelisted "$exit_code"; then
    log_debug "$description completed with whitelisted exit code: $exit_code"
    return 0
  fi
  
  local error_type
  error_type=$(error_classify "$exit_code" "$stderr" "$stdout")
  
  local severity
  severity=$(error_get_severity "$error_type")
  
  local suggestion
  suggestion=$(error_get_suggestion "$error_type")
  
  # Format and log standardized error message (UX-007)
  local formatted_error
  formatted_error=$(error_format_message "$severity" "$description failed with exit code $exit_code (Type: $error_type)" "$suggestion")
  
  if [[ "$severity" == "FATAL" ]]; then
    log_fatal "$formatted_error"
  else
    log_error "$formatted_error"
  fi
  
  if [[ -n "$stderr" ]]; then
    log_error "Error output: $stderr"
  fi
  
  return 1
}

# Execute command with retry logic and exponential backoff
# Args: $1 - command to execute, $2 - max retries (default: 3), $3 - initial delay (default: 2)
# Returns: 0 on success, 1 on failure
execute_with_retry() {
  local cmd="$1"
  local max_retries="${2:-3}"
  local initial_delay="${3:-2}"
  local attempt=0
  local delay="$initial_delay"
  
  while [[ $attempt -lt $max_retries ]]; do
    attempt=$((attempt + 1))
    
    log_info "Executing: $cmd (attempt $attempt/$max_retries)"
    
    local output
    local stderr
    local exit_code
    
    # Execute command and capture output
    if output=$(eval "$cmd" 2>&1); then
      exit_code=0
    else
      exit_code=$?
    fi
    
    stderr="$output"
    
    # Check if exit code is acceptable
    if error_exit_code_whitelisted "$exit_code"; then
      log_info "Command succeeded"
      return 0
    fi
    
    # Classify error
    local error_type
    error_type=$(error_classify "$exit_code" "$stderr" "")
    
    local severity
    severity=$(error_get_severity "$error_type")
    
    log_warning "Command failed with error type: $error_type (severity: $severity)"
    
    # Critical errors should not be retried
    if [[ "$severity" == "$E_SEVERITY_CRITICAL" ]]; then
      log_error "Critical error detected, aborting retries"
      circuit_breaker_record_failure
      return 1
    fi
    
    # Check if we should retry
    if [[ $attempt -lt $max_retries ]]; then
      log_info "Retrying in ${delay}s..."
      sleep "$delay"
      
      # Exponential backoff
      delay=$((delay * 2))
    else
      log_error "Max retries exceeded for command: $cmd"
      circuit_breaker_record_failure
      return 1
    fi
  done
  
  return 1
}

# Record circuit breaker failure
circuit_breaker_record_failure() {
  CIRCUIT_BREAKER_FAILURES=$((CIRCUIT_BREAKER_FAILURES + 1))
  
  log_debug "Circuit breaker failures: $CIRCUIT_BREAKER_FAILURES"
  
  if [[ $CIRCUIT_BREAKER_FAILURES -ge $CIRCUIT_BREAKER_THRESHOLD ]]; then
    log_error "Circuit breaker threshold reached: $CIRCUIT_BREAKER_FAILURES failures"
    circuit_breaker_open
  fi
}

# Open circuit breaker
circuit_breaker_open() {
  CIRCUIT_BREAKER_OPEN=true
  log_error "Circuit breaker OPENED - failing fast to prevent cascading failures"
  log_info "Circuit will reset after ${CIRCUIT_BREAKER_RESET_TIME}s"
}

# Close circuit breaker (reset)
circuit_breaker_close() {
  CIRCUIT_BREAKER_OPEN=false
  CIRCUIT_BREAKER_FAILURES=0
  log_info "Circuit breaker CLOSED - normal operations resumed"
}

# Check if circuit breaker is open
# Returns: 0 if closed (OK to proceed), 1 if open (should fail fast)
circuit_breaker_is_open() {
  if [[ "$CIRCUIT_BREAKER_OPEN" == "true" ]]; then
    log_error "Circuit breaker is OPEN - operation rejected"
    return 0
  fi
  return 1
}

# Execute command with circuit breaker protection
# Args: $1 - command to execute
# Returns: 0 on success, 1 on failure
execute_with_circuit_breaker() {
  local cmd="$1"
  
  if circuit_breaker_is_open; then
    log_error "Circuit breaker is open, command rejected: $cmd"
    return 1
  fi
  
  local output
  local exit_code
  
  if output=$(eval "$cmd" 2>&1); then
    exit_code=0
  else
    exit_code=$?
  fi
  
  if error_exit_code_whitelisted "$exit_code"; then
    return 0
  fi
  
  local error_type
  error_type=$(error_classify "$exit_code" "$output" "")
  
  # Network failures contribute to circuit breaker
  if [[ "$error_type" == "$E_NETWORK" ]]; then
    circuit_breaker_record_failure
  fi
  
  return 1
}



# Wrapper function for safe command execution with all protections
# Args: $1 - command, $2 - description, $3 - retry count (optional)
# Returns: 0 on success, 1 on failure
safe_execute() {
  local cmd="$1"
  local description="${2:-command}"
  local max_retries="${3:-3}"
  
  log_info "Executing: $description"
  
  # Check circuit breaker first
  if circuit_breaker_is_open; then
    log_error "Circuit breaker open, operation aborted: $description"
    return 1
  fi
  
  # Execute with retry logic
  if execute_with_retry "$cmd" "$max_retries" 2; then
    log_info "$description completed successfully"
    return 0
  fi
  
  log_error "$description failed after $max_retries attempts"
  return 1
}

