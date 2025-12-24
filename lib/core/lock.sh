#!/bin/bash
# lock.sh - Global lock file mechanism for preventing concurrent provisioning
# Implements file-based locking with PID tracking and stale lock detection
#
# Usage:
#   source lib/core/lock.sh
#   lock_acquire || exit 1
#   # ... do work ...
#   lock_release
#
# Dependencies:
#   - lib/core/logger.sh

set -euo pipefail

# Prevent multiple sourcing
if [[ -n "${_LOCK_SH_LOADED:-}" ]]; then
  return 0
fi
readonly _LOCK_SH_LOADED=1

# Source dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/core/logger.sh
source "${SCRIPT_DIR}/logger.sh"

# Lock configuration
readonly LOCK_FILE="${LOCK_FILE:-/var/lock/vps-provision.lock}"
readonly LOCK_DIR=$(dirname "$LOCK_FILE")
readonly LOCK_TIMEOUT="${LOCK_TIMEOUT:-300}"  # 5 minutes

# Current lock state
LOCK_HELD=false

# Initialize lock system
lock_init() {
  if [[ ! -d "$LOCK_DIR" ]]; then
    mkdir -p "$LOCK_DIR" 2>/dev/null || {
      log_error "Failed to create lock directory: $LOCK_DIR"
      return 1
    }
  fi
  
  log_debug "Lock system initialized"
  log_debug "Lock file: $LOCK_FILE"
}

# Check if lock file is stale
# Args: $1 - PID from lock file
# Returns: 0 if stale, 1 if active
lock_is_stale() {
  local pid="$1"
  
  if [[ -z "$pid" ]] || [[ ! "$pid" =~ ^[0-9]+$ ]]; then
    log_debug "Invalid PID in lock file: $pid"
    return 0  # Stale (invalid PID)
  fi
  
  # Check if process exists
  if kill -0 "$pid" 2>/dev/null; then
    log_debug "Process $pid is still running"
    return 1  # Not stale (process exists)
  fi
  
  log_debug "Process $pid not found (stale lock)"
  return 0  # Stale (process doesn't exist)
}

# Check lock file age
# Returns: age in seconds
lock_get_age() {
  if [[ ! -f "$LOCK_FILE" ]]; then
    echo "0"
    return 0
  fi
  
  local current_time
  current_time=$(date +%s)
  
  local file_time
  file_time=$(stat -c %Y "$LOCK_FILE" 2>/dev/null || echo "0")
  
  local age=$((current_time - file_time))
  
  echo "$age"
}

# Acquire lock
# Args: $1 - max wait time in seconds (default: 0, no wait)
# Returns: 0 if acquired, 1 if failed
lock_acquire() {
  local max_wait="${1:-0}"
  local waited=0
  
  log_debug "Attempting to acquire lock..."
  
  # Ensure lock directory exists
  lock_init || return 1
  
  while true; do
    if [[ ! -f "$LOCK_FILE" ]]; then
      # No lock file, create it
      echo "$$" > "$LOCK_FILE" || {
        log_error "Failed to create lock file: $LOCK_FILE"
        return 1
      }
      
      LOCK_HELD=true
      log_info "Lock acquired (PID: $$)"
      return 0
    fi
    
    # Lock file exists, check if stale
    local lock_pid
    lock_pid=$(cat "$LOCK_FILE" 2>/dev/null || echo "")
    
    if lock_is_stale "$lock_pid"; then
      local age
      age=$(lock_get_age)
      log_warning "Stale lock file detected (PID: $lock_pid, age: ${age}s)"
      
      # Remove stale lock
      rm -f "$LOCK_FILE" || {
        log_error "Failed to remove stale lock file"
        return 1
      }
      
      log_info "Removed stale lock file"
      continue  # Try to acquire again
    fi
    
    # Lock is held by active process
    if [[ $max_wait -eq 0 ]]; then
      log_error "Lock is held by another process (PID: $lock_pid)"
      log_error "Wait for process to complete or use --force to override"
      return 1
    fi
    
    # Wait and retry
    if [[ $waited -ge $max_wait ]]; then
      log_error "Timeout waiting for lock (waited ${waited}s)"
      return 1
    fi
    
    log_info "Lock held by PID $lock_pid, waiting... (${waited}/${max_wait}s)"
    sleep 2
    waited=$((waited + 2))
  done
}

# Release lock
# Returns: 0 on success, 1 on failure
lock_release() {
  if [[ "$LOCK_HELD" != "true" ]]; then
    log_debug "No lock to release"
    return 0
  fi
  
  if [[ ! -f "$LOCK_FILE" ]]; then
    log_warning "Lock file does not exist (already released?)"
    LOCK_HELD=false
    return 0
  fi
  
  local lock_pid
  lock_pid=$(cat "$LOCK_FILE" 2>/dev/null || echo "")
  
  if [[ "$lock_pid" != "$$" ]]; then
    log_warning "Lock file PID ($lock_pid) doesn't match current process ($$)"
    log_warning "Not releasing lock (may be owned by another process)"
    return 1
  fi
  
  rm -f "$LOCK_FILE" || {
    log_error "Failed to remove lock file: $LOCK_FILE"
    return 1
  }
  
  LOCK_HELD=false
  log_info "Lock released"
  return 0
}

# Force release lock (removes lock regardless of owner)
# Returns: 0 on success, 1 on failure
lock_force_release() {
  if [[ ! -f "$LOCK_FILE" ]]; then
    log_info "No lock file to force release"
    return 0
  fi
  
  local lock_pid
  lock_pid=$(cat "$LOCK_FILE" 2>/dev/null || echo "unknown")
  
  log_warning "Force releasing lock (owner PID: $lock_pid)"
  
  rm -f "$LOCK_FILE" || {
    log_error "Failed to force release lock file"
    return 1
  }
  
  LOCK_HELD=false
  log_info "Lock force released"
  return 0
}

# Check if lock is held by current process
lock_is_held() {
  if [[ "$LOCK_HELD" == "true" ]]; then
    return 0
  fi
  return 1
}

# Get lock owner PID
# Returns: PID or empty if no lock
lock_get_owner() {
  if [[ ! -f "$LOCK_FILE" ]]; then
    echo ""
    return 0
  fi
  
  cat "$LOCK_FILE" 2>/dev/null || echo ""
}

# Cleanup lock on exit (register with trap)
lock_cleanup_on_exit() {
  if lock_is_held; then
    log_debug "Cleanup: releasing lock on exit"
    lock_release
  fi
}

# Wait for lock to become available
# Args: $1 - max wait time in seconds (default: 60)
# Returns: 0 if available, 1 if timeout
lock_wait() {
  local max_wait="${1:-60}"
  local waited=0
  
  log_info "Waiting for lock to become available..."
  
  while [[ -f "$LOCK_FILE" ]]; do
    local lock_pid
    lock_pid=$(cat "$LOCK_FILE" 2>/dev/null || echo "")
    
    # Check if lock is stale
    if lock_is_stale "$lock_pid"; then
      log_info "Lock is stale, will be removed"
      return 0
    fi
    
    # Check timeout
    if [[ $waited -ge $max_wait ]]; then
      log_error "Timeout waiting for lock (${waited}s)"
      return 1
    fi
    
    log_info "Lock held by PID $lock_pid, waiting... (${waited}/${max_wait}s)"
    sleep 5
    waited=$((waited + 5))
  done
  
  log_info "Lock is now available"
  return 0
}
