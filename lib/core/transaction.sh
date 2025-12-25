#!/bin/bash
# transaction.sh - Transaction logging for rollback support
# Records all actions with rollback commands in LIFO format

set -euo pipefail

# Prevent multiple sourcing
if [[ -n "${_TRANSACTION_SH_LOADED:-}" ]]; then
  return 0
fi
readonly _TRANSACTION_SH_LOADED=1

# Source logger for output
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/core/logger.sh
# shellcheck disable=SC1091  # Intentional sourcing - path resolved at runtime
source "${SCRIPT_DIR}/logger.sh"

# Transaction log file (use logger's value if set)
if [[ -z "${TRANSACTION_LOG:-}" ]]; then
  readonly TRANSACTION_LOG="/var/log/vps-provision/transactions.log"
fi

# Initialize transaction logging system
transaction_init() {
  local log_dir
  log_dir=$(dirname "$TRANSACTION_LOG")
  
  if [[ ! -d "$log_dir" ]]; then
    mkdir -p "$log_dir" || {
      log_error "Failed to create transaction log directory: $log_dir"
      return 1
    }
  fi
  
  if [[ ! -f "$TRANSACTION_LOG" ]]; then
    touch "$TRANSACTION_LOG" || {
      log_error "Failed to create transaction log: $TRANSACTION_LOG"
      return 1
    }
  fi
  
  chmod 640 "$TRANSACTION_LOG" 2>/dev/null || true
  
  log_debug "Transaction logging initialized"
  log_debug "Transaction log: $TRANSACTION_LOG"
  
  return 0
}

# Record a transaction with rollback command
# Args: $1 - action description, $2 - rollback command
transaction_record() {
  local action="$1"
  local rollback_cmd="$2"
  local timestamp
  
  if [[ -z "$action" ]] || [[ -z "$rollback_cmd" ]]; then
    log_error "Transaction record requires both action and rollback command"
    return 1
  fi
  
  timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  
  # Format: TIMESTAMP|ACTION|ROLLBACK_COMMAND
  echo "${timestamp}|${action}|${rollback_cmd}" >> "$TRANSACTION_LOG"
  
  log_debug "Transaction recorded: $action"
  
  return 0
}

# Get all transactions in LIFO order (most recent first)
# Returns: transaction records in reverse order
transaction_get_all_reverse() {
  if [[ ! -f "$TRANSACTION_LOG" ]]; then
    return 0
  fi
  
  tac "$TRANSACTION_LOG"
}

# Get transaction count
transaction_count() {
  if [[ ! -f "$TRANSACTION_LOG" ]]; then
    echo "0"
    return 0
  fi
  
  wc -l < "$TRANSACTION_LOG"
}

# Parse transaction record
# Args: $1 - transaction line
# Returns: timestamp, action, rollback_cmd (via stdout)
transaction_parse() {
  local line="$1"
  local timestamp
  local action
  local rollback_cmd
  
  IFS='|' read -r timestamp action rollback_cmd <<< "$line"
  
  echo "$timestamp"
  echo "$action"
  echo "$rollback_cmd"
}

# Get rollback commands for all transactions
# Returns: rollback commands in LIFO order
transaction_get_rollback_commands() {
  if [[ ! -f "$TRANSACTION_LOG" ]]; then
    return 0
  fi
  
  # Read transactions in reverse order and extract rollback commands
  tac "$TRANSACTION_LOG" | cut -d'|' -f3
}

# Clear transaction log
transaction_clear() {
  if [[ -f "$TRANSACTION_LOG" ]]; then
: > "$TRANSACTION_LOG"
    log_info "Transaction log cleared"
  fi
}

# Backup transaction log
# Args: $1 - backup file path (optional)
transaction_backup() {
  local backup_file="${1:-${TRANSACTION_LOG}.backup}"
  
  if [[ ! -f "$TRANSACTION_LOG" ]]; then
    log_warning "Transaction log not found, cannot backup"
    return 1
  fi
  
  cp "$TRANSACTION_LOG" "$backup_file" || {
    log_error "Failed to backup transaction log"
    return 1
  }
  
  log_info "Transaction log backed up to: $backup_file"
  return 0
}

# Display transaction summary
transaction_show_summary() {
  local count
  count=$(transaction_count)
  
  log_info "Transaction Summary:"
  log_info "  Total transactions: $count"
  
  if [[ $count -gt 0 ]]; then
    log_info "  Recent transactions:"
    
    # Show last 5 transactions
    tail -n 5 "$TRANSACTION_LOG" | while IFS='|' read -r timestamp action rollback_cmd; do
      log_info "    [$timestamp] $action"
    done
  fi
}

# Common transaction recording functions for typical operations

# Record package installation
# Args: $1 - package name
transaction_record_package_install() {
  local package="$1"
  transaction_record "Installed package: $package" "apt-get remove -y $package"
}

# Record file creation
# Args: $1 - file path
transaction_record_file_create() {
  local file="$1"
  transaction_record "Created file: $file" "rm -f '$file'"
}

# Record directory creation
# Args: $1 - directory path
transaction_record_dir_create() {
  local dir="$1"
  transaction_record "Created directory: $dir" "rm -rf '$dir'"
}

# Record file modification (with backup)
# Args: $1 - file path, $2 - backup path
transaction_record_file_modify() {
  local file="$1"
  local backup="$2"
  transaction_record "Modified file: $file" "cp '$backup' '$file'"
}

# Record user creation
# Args: $1 - username
transaction_record_user_create() {
  local username="$1"
  transaction_record "Created user: $username" "userdel -r '$username'"
}

# Record service enable
# Args: $1 - service name
transaction_record_service_enable() {
  local service="$1"
  transaction_record "Enabled service: $service" "systemctl disable '$service' && systemctl stop '$service'"
}

# Record configuration change
# Args: $1 - description, $2 - restore command
transaction_record_config_change() {
  local description="$1"
  local restore_cmd="$2"
  transaction_record "Configuration: $description" "$restore_cmd"
}

# Backwards compatibility / Shim for transaction_log
transaction_log() {
  if [[ $# -eq 1 ]]; then
    # format: transaction_log "rollback_cmd"
    transaction_record "System Action" "$1"
  elif [[ $# -eq 2 ]]; then
     # format: transaction_log "action" "rollback_cmd"
     transaction_record "$1" "$2"
  elif [[ $# -ge 3 ]]; then
    # format: transaction_log "type" "subject" "rollback"
    transaction_record "$1: $2" "$3"
  else
    log_error "Invalid arguments to transaction_log"
    return 1
  fi
}

transaction_validate() {
  if [[ ! -f "$TRANSACTION_LOG" ]]; then
    log_warning "Transaction log not found"
    return 1
  fi
  
  local line_num=0
  local errors=0
  
  while IFS= read -r line; do
    line_num=$((line_num + 1))
    
    # Check format: should have 3 fields separated by |
    local field_count
    field_count=$(echo "$line" | awk -F'|' '{print NF}')
    
    if [[ $field_count -ne 3 ]]; then
      log_error "Transaction log format error at line $line_num"
      errors=$((errors + 1))
    fi
  done < "$TRANSACTION_LOG"
  
  if [[ $errors -gt 0 ]]; then
    log_error "Transaction log validation failed with $errors error(s)"
    return 1
  fi
  
  log_debug "Transaction log validation passed"
  return 0
}

# Restore transaction log from backup
transaction_restore() {
  local backup_file="${1}"
  
  if [[ ! -f "${backup_file}" ]]; then
    log_error "Backup file not found: ${backup_file}"
    return 1
  fi
  
  cp "${backup_file}" "${TRANSACTION_LOG}" || {
    log_error "Failed to restore transaction log from backup"
    return 1
  }
  
  log_info "Transaction log restored from: ${backup_file}"
  return 0
}

# Get last (most recent) transaction
transaction_get_last() {
  if [[ ! -f "$TRANSACTION_LOG" ]]; then
    return 0
  fi
  
  tail -n 1 "$TRANSACTION_LOG"
}

# Get first (oldest) transaction
transaction_get_first() {
  if [[ ! -f "$TRANSACTION_LOG" ]]; then
    return 0
  fi
  
  head -n 1 "$TRANSACTION_LOG"
}

# Filter transactions by pattern
transaction_filter_by_pattern() {
  local pattern="${1}"
  
  if [[ ! -f "$TRANSACTION_LOG" ]]; then
    return 0
  fi
  
  grep "${pattern}" "$TRANSACTION_LOG" || true
}

# Export transactions as JSON array
transaction_export_json() {
  if [[ ! -f "$TRANSACTION_LOG" ]]; then
    echo "[]"
    return 0
  fi
  
  echo "["
  local first=true
  while IFS='|' read -r timestamp action rollback_cmd; do
    if [[ "$first" == "true" ]]; then
      first=false
    else
      echo ","
    fi
    
    # Escape quotes in values using jq for robust JSON encoding
    local ts_json action_json rollback_json
    ts_json=$(printf '%s' "$timestamp" | jq -Rs .)
    action_json=$(printf '%s' "$action" | jq -Rs .)
    rollback_json=$(printf '%s' "$rollback_cmd" | jq -Rs .)
    
    cat <<EOF
  {
    "timestamp": $ts_json,
    "action": $action_json,
    "rollback_command": $rollback_json
  }
EOF
  done < "$TRANSACTION_LOG"
  echo ""
  echo "]"
}

# Get transaction by index (1-indexed)
transaction_get_by_index() {
  local index="${1}"
  
  if [[ ! -f "$TRANSACTION_LOG" ]]; then
    return 1
  fi
  
  sed -n "${index}p" "$TRANSACTION_LOG"
}

# Get transaction summary statistics
transaction_summarize() {
  local count
  count=$(transaction_count)
  
  cat <<EOF
Transaction Log Summary:
  Total Transactions: ${count}
  Log File: ${TRANSACTION_LOG}
  Latest Transaction: $(transaction_get_last | cut -d'|' -f2 || echo "None")
EOF
}
