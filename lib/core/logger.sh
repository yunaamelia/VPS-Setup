#!/bin/bash
# logger.sh - Logging framework for VPS provisioning
# Provides structured logging with levels, colors, and file output

set -euo pipefail

# Prevent multiple sourcing
if [[ -n "${_LOGGER_SH_LOADED:-}" ]]; then
  return 0
fi
readonly _LOGGER_SH_LOADED=1

# Global variables
readonly LOG_DIR="${LOG_DIR:-/var/log/vps-provision}"
readonly LOG_FILE="${LOG_FILE:-${LOG_DIR}/provision.log}"
readonly TRANSACTION_LOG="${TRANSACTION_LOG:-${LOG_DIR}/transactions.log}"

# Log levels
readonly LOG_LEVEL_DEBUG=0
readonly LOG_LEVEL_INFO=1
readonly LOG_LEVEL_WARNING=2
readonly LOG_LEVEL_ERROR=3

# Colors for terminal output (UX-020: Consistent color coding)
readonly COLOR_RESET='\033[0m'
readonly COLOR_DEBUG='\033[36m'    # Cyan (Blue/Cyan for Info/Progress)
readonly COLOR_INFO='\033[32m'     # Green (Success)
readonly COLOR_WARNING='\033[33m'  # Yellow (Warning)
readonly COLOR_ERROR='\033[31m'    # Red (Error)
readonly COLOR_BOLD='\033[1m'

# Text labels for accessibility (UX-021: No critical info solely by color)
readonly LABEL_DEBUG="[DEBUG]"
readonly LABEL_INFO="[OK]"       # Success indicator
readonly LABEL_WARNING="[WARN]"  # Warning indicator
readonly LABEL_ERROR="[ERR]"     # Error indicator
readonly LABEL_FATAL="[FATAL]"   # Fatal error indicator

# Current log level (default: INFO)
LOG_LEVEL="${LOG_LEVEL:-INFO}"
# UX-019: Support for --plain/--no-color mode
ENABLE_COLORS="${ENABLE_COLORS:-true}"
if [[ "${NO_COLOR:-}" == "1" ]] || [[ "${NO_COLOR:-}" == "true" ]]; then
  ENABLE_COLORS="false"
fi

# Initialize logging system
# Creates log directory and files with proper permissions
logger_init() {
  local log_dir="${1:-$LOG_DIR}"
  
  if [[ ! -d "$log_dir" ]]; then
    mkdir -p "$log_dir" || {
      echo "ERROR: Failed to create log directory: $log_dir" >&2
      return 1
    }
  fi
  
  touch "$LOG_FILE" "$TRANSACTION_LOG" || {
    echo "ERROR: Failed to create log files" >&2
    return 1
  }
  
  chmod 640 "$LOG_FILE" "$TRANSACTION_LOG" 2>/dev/null || true
  
  log_info "Logging system initialized"
  log_debug "Log directory: $log_dir"
  log_debug "Log file: $LOG_FILE"
  
  return 0
}

# Get numeric log level from string
# Args: $1 - log level string (DEBUG, INFO, WARNING, ERROR)
# Returns: numeric log level
_get_log_level_value() {
  local level="${1:-INFO}"
  
  case "${level^^}" in
    DEBUG)   echo "$LOG_LEVEL_DEBUG" ;;
    INFO)    echo "$LOG_LEVEL_INFO" ;;
    WARNING) echo "$LOG_LEVEL_WARNING" ;;
    ERROR)   echo "$LOG_LEVEL_ERROR" ;;
    *)       echo "$LOG_LEVEL_INFO" ;;
  esac
}

# Format log message with timestamp, level, and text label
# Args: $1 - log level, $2 - message
# Returns: formatted log message
_format_log_message() {
  local level="$1"
  local message="$2"
  local timestamp
  timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  
  # UX-021: Add text labels for accessibility
  local label
  case "${level^^}" in
    DEBUG)   label="$LABEL_DEBUG" ;;
    INFO)    label="$LABEL_INFO" ;;
    WARNING) label="$LABEL_WARNING" ;;
    ERROR)   label="$LABEL_ERROR" ;;
    FATAL)   label="$LABEL_FATAL" ;;
    *)       label="[$level]" ;;
  esac
  
  echo "[$timestamp] $label $message"
}

# Write log message to file and console
# Args: $1 - log level, $2 - message, $3 - color (optional)
_log_message() {
  local level="$1"
  local message="$2"
  local color="${3:-}"
  local level_value
  local current_level_value
  
  level_value=$(_get_log_level_value "$level")
  current_level_value=$(_get_log_level_value "$LOG_LEVEL")
  
  # Skip if message level is below current log level
  if [[ $level_value -lt $current_level_value ]]; then
    return 0
  fi
  
  # Auto-redact message (SEC-003)
  message=$(log_redact "$message")
  
  local formatted_message
  formatted_message=$(_format_log_message "$level" "$message")
  
  # Write to log file (always, without colors)
  if [[ -w "$LOG_FILE" ]]; then
    echo "$formatted_message" >> "$LOG_FILE"
  fi
  
  # Write to console with optional colors (always to stderr)
  if [[ "$ENABLE_COLORS" == "true" ]] && [[ -n "$color" ]] && [[ -t 2 ]]; then
    echo -e "${color}${formatted_message}${COLOR_RESET}" >&2
  else
    echo "$formatted_message" >&2
  fi
}

# Log debug message
# Args: $@ - message parts
log_debug() {
  _log_message "DEBUG" "$*" "$COLOR_DEBUG"
}

# Log info message
# Args: $@ - message parts
log_info() {
  _log_message "INFO" "$*" "$COLOR_INFO"
}

# Log warning message
# Args: $@ - message parts
log_warning() {
  _log_message "WARNING" "$*" "$COLOR_WARNING"
}

# Log error message
# Args: $@ - message parts
log_error() {
  _log_message "ERROR" "$*" "$COLOR_ERROR" >&2
}

# Log fatal error message (UX-011: FATAL severity for critical abort situations)
# Args: $@ - message parts
log_fatal() {
  _log_message "FATAL" "$*" "${COLOR_ERROR}${COLOR_BOLD}" >&2
}

# Log message with custom level
# Args: $1 - level, $@ - message
log_custom() {
  local level="$1"
  shift
  _log_message "$level" "$*"
}

# Set log level
# Args: $1 - log level (DEBUG, INFO, WARNING, ERROR)
logger_set_level() {
  local level="${1:-INFO}"
  
  case "${level^^}" in
    DEBUG|INFO|WARNING|ERROR)
      LOG_LEVEL="${level^^}"
      log_debug "Log level set to: $LOG_LEVEL"
      return 0
      ;;
    *)
      log_error "Invalid log level: $level"
      return 1
      ;;
  esac
}

# Enable or disable colored output
# Args: $1 - true/false
logger_set_colors() {
  local enable="${1:-true}"
  ENABLE_COLORS="$enable"
  log_debug "Colored output: $ENABLE_COLORS"
}

# Get current log file path
logger_get_logfile() {
  echo "$LOG_FILE"
}

# Clear log file
logger_clear() {
  if [[ -f "$LOG_FILE" ]]; then
: > "$LOG_FILE"
    log_info "Log file cleared"
  fi
}

# Log a separator line
log_separator() {
  local char="${1:--}"
  local length="${2:-60}"
  local line
  line=$(printf '%*s' "$length" "" | tr ' ' "$char")
  log_info "$line"
}

# Log a section header
# Args: $1 - section title
log_section() {
  local title="$1"
  log_separator "="
  log_info "${COLOR_BOLD}${title}${COLOR_RESET}"
  log_separator "="
}

# Redact sensitive information from strings (UX-024)
# Args: $1 - text potentially containing sensitive data
# Output: text with sensitive patterns replaced with [REDACTED]
log_redact() {
  local text="$1"
  
  # Patterns to redact (case-insensitive)
  # Password patterns
  text=$(echo "$text" | sed -E 's/(password[=: ]+)[^ ]*/\1[REDACTED]/gi')
  text=$(echo "$text" | sed -E 's/(passwd[=: ]+)[^ ]*/\1[REDACTED]/gi')
  text=$(echo "$text" | sed -E 's/(pwd[=: ]+)[^ ]*/\1[REDACTED]/gi')
  
  # API key patterns
  text=$(echo "$text" | sed -E 's/(api[_-]?key[=: ]+)[^ ]*/\1[REDACTED]/gi')
  text=$(echo "$text" | sed -E 's/(apikey[=: ]+)[^ ]*/\1[REDACTED]/gi')
  text=$(echo "$text" | sed -E 's/(access[_-]?key[=: ]+)[^ ]*/\1[REDACTED]/gi')
  text=$(echo "$text" | sed -E 's/(secret[_-]?key[=: ]+)[^ ]*/\1[REDACTED]/gi')
  
  # Token patterns
  text=$(echo "$text" | sed -E 's/(token[=: ]+)[^ ]*/\1[REDACTED]/gi')
  text=$(echo "$text" | sed -E 's/(auth[=: ]+)[^ ]*/\1[REDACTED]/gi')
  text=$(echo "$text" | sed -E 's/(bearer[=: ]+)[^ ]*/\1[REDACTED]/gi')
  
  # SSH key patterns
  text=$(echo "$text" | sed -E 's/(ssh[_-]?key[=: ]+)[^ ]*/\1[REDACTED]/gi')
  text=$(echo "$text" | sed -E 's/(private[_-]?key[=: ]+)[^ ]*/\1[REDACTED]/gi')
  
  # Connection string patterns
  text=$(echo "$text" | sed -E 's/([a-z]+:\/\/[^:]+:)([^@]+)(@)/\1[REDACTED]\3/gi')
  
  echo "$text"
}

# Log with automatic redaction (UX-024)
# Args: $1 - log level, $@ - message
log_redacted() {
  local level="$1"
  shift
  local message="$*"
  local redacted_message
  redacted_message=$(log_redact "$message")
  
  case "${level^^}" in
    DEBUG)   log_debug "$redacted_message" ;;
    INFO)    log_info "$redacted_message" ;;
    WARNING) log_warning "$redacted_message" ;;
    ERROR)   log_error "$redacted_message" ;;
    FATAL)   log_fatal "$redacted_message" ;;
    *)       _log_message "$level" "$redacted_message" ;;
  esac
}

# Export functions for use in other scripts
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  # Script is being run directly, not sourced
  echo "This script should be sourced, not executed directly" >&2
  exit 1
fi
