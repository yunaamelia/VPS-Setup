#!/bin/bash
# checkpoint.sh - Checkpoint mechanism for idempotency support
# Provides create, check, validate, and clear functions for phase checkpoints

set -euo pipefail

# Source logger for output
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/core/logger.sh
source "${SCRIPT_DIR}/logger.sh"

# Prevent multiple sourcing
if [[ -n "${_CHECKPOINT_SH_LOADED:-}" ]]; then
  return 0
fi
readonly _CHECKPOINT_SH_LOADED=1

# Checkpoint directory
readonly CHECKPOINT_DIR="${CHECKPOINT_DIR:-/var/vps-provision/checkpoints}"

# Initialize checkpoint system
# Creates checkpoint directory with proper permissions
checkpoint_init() {
  if [[ ! -d "$CHECKPOINT_DIR" ]]; then
    mkdir -p "$CHECKPOINT_DIR" || {
      log_error "Failed to create checkpoint directory: $CHECKPOINT_DIR"
      return 1
    }
    log_debug "Checkpoint directory created: $CHECKPOINT_DIR"
  fi
  
  chmod 750 "$CHECKPOINT_DIR" 2>/dev/null || true
  log_debug "Checkpoint system initialized"
  
  return 0
}

# Create a checkpoint
# Args: $1 - checkpoint name (phase identifier)
checkpoint_create() {
  local checkpoint_name="$1"
  local checkpoint_file="${CHECKPOINT_DIR}/${checkpoint_name}.checkpoint"
  local timestamp
  
  if [[ -z "$checkpoint_name" ]]; then
    log_error "Checkpoint name cannot be empty"
    return 1
  fi
  
  timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  
  cat > "$checkpoint_file" <<EOF
CHECKPOINT_NAME="$checkpoint_name"
CREATED_AT="$timestamp"
HOSTNAME="$(hostname)"
USER="$(whoami)"
EOF
  
  chmod 640 "$checkpoint_file" 2>/dev/null || true
  
  log_debug "Checkpoint created: $checkpoint_name"
  
  return 0
}

# Check if checkpoint exists
# Args: $1 - checkpoint name
# Returns: 0 if exists, 1 if not
checkpoint_exists() {
  local checkpoint_name="$1"
  local checkpoint_file="${CHECKPOINT_DIR}/${checkpoint_name}.checkpoint"
  
  if [[ -f "$checkpoint_file" ]]; then
    log_debug "Checkpoint exists: $checkpoint_name"
    return 0
  fi
  
  log_debug "Checkpoint does not exist: $checkpoint_name"
  return 1
}

# Validate checkpoint integrity
# Args: $1 - checkpoint name
# Returns: 0 if valid, 1 if invalid
checkpoint_validate() {
  local checkpoint_name="$1"
  local checkpoint_file="${CHECKPOINT_DIR}/${checkpoint_name}.checkpoint"
  
  if [[ ! -f "$checkpoint_file" ]]; then
    log_warning "Checkpoint file not found: $checkpoint_name"
    return 1
  fi
  
  # Check if file is readable
  if [[ ! -r "$checkpoint_file" ]]; then
    log_error "Checkpoint file not readable: $checkpoint_name"
    return 1
  fi
  
  # Validate required fields
  local required_fields=("CHECKPOINT_NAME" "CREATED_AT")
  local field
  
  for field in "${required_fields[@]}"; do
    if ! grep -q "^${field}=" "$checkpoint_file"; then
      log_error "Checkpoint missing required field: $field"
      return 1
    fi
  done
  
  log_debug "Checkpoint validated: $checkpoint_name"
  return 0
}

# Get checkpoint creation time
# Args: $1 - checkpoint name
# Returns: checkpoint timestamp
checkpoint_get_timestamp() {
  local checkpoint_name="$1"
  local checkpoint_file="${CHECKPOINT_DIR}/${checkpoint_name}.checkpoint"
  
  if [[ ! -f "$checkpoint_file" ]]; then
    echo ""
    return 1
  fi
  
  grep "^CREATED_AT=" "$checkpoint_file" | cut -d'"' -f2
}

# List all checkpoints
# Returns: list of checkpoint names
checkpoint_list() {
  local checkpoint_files
  
  if [[ ! -d "$CHECKPOINT_DIR" ]]; then
    log_debug "Checkpoint directory does not exist"
    return 0
  fi
  
  mapfile -t checkpoint_files < <(find "$CHECKPOINT_DIR" -name "*.checkpoint" -type f 2>/dev/null)
  
  if [[ ${#checkpoint_files[@]} -eq 0 ]]; then
    log_debug "No checkpoints found"
    return 0
  fi
  
  local file
  for file in "${checkpoint_files[@]}"; do
    basename "$file" .checkpoint
  done
}

# Clear a specific checkpoint
# Args: $1 - checkpoint name
checkpoint_clear() {
  local checkpoint_name="$1"
  local checkpoint_file="${CHECKPOINT_DIR}/${checkpoint_name}.checkpoint"
  
  if [[ ! -f "$checkpoint_file" ]]; then
    log_warning "Checkpoint not found: $checkpoint_name"
    return 1
  fi
  
  rm -f "$checkpoint_file" || {
    log_error "Failed to remove checkpoint: $checkpoint_name"
    return 1
  }
  
  log_debug "Checkpoint cleared: $checkpoint_name"
  return 0
}

# Clear all checkpoints
checkpoint_clear_all() {
  if [[ ! -d "$CHECKPOINT_DIR" ]]; then
    log_debug "Checkpoint directory does not exist"
    return 0
  fi
  
  local count
  count=$(find "$CHECKPOINT_DIR" -name "*.checkpoint" -type f 2>/dev/null | wc -l)
  
  if [[ $count -eq 0 ]]; then
    log_debug "No checkpoints to clear"
    return 0
  fi
  
  rm -f "${CHECKPOINT_DIR}"/*.checkpoint 2>/dev/null || true
  
  log_info "Cleared $count checkpoint(s)"
  return 0
}

# Get checkpoint count
checkpoint_count() {
  if [[ ! -d "$CHECKPOINT_DIR" ]]; then
    echo "0"
    return 0
  fi
  
  find "$CHECKPOINT_DIR" -name "*.checkpoint" -type f 2>/dev/null | wc -l
}

# Display checkpoint status
checkpoint_show_status() {
  local checkpoints
  local count
  
  count=$(checkpoint_count)
  
  log_info "Checkpoint Status:"
  log_info "  Total checkpoints: $count"
  
  if [[ $count -gt 0 ]]; then
    log_info "  Checkpoints:"
    
    mapfile -t checkpoints < <(checkpoint_list)
    local checkpoint
    for checkpoint in "${checkpoints[@]}"; do
      local timestamp
      timestamp=$(checkpoint_get_timestamp "$checkpoint")
      log_info "    - $checkpoint (created: $timestamp)"
    done
  fi
}

# Check if phase should be skipped (checkpoint exists)
# Args: $1 - phase name
# Returns: 0 if should skip, 1 if should run
# Environment: FORCE_MODE - if "true", never skip (re-run everything)
checkpoint_should_skip() {
  local phase_name="$1"
  local force_mode="${FORCE_MODE:-false}"
  
  # Force mode: always run, never skip
  if [[ "${force_mode}" == "true" ]]; then
    log_debug "Phase '$phase_name' will run (force mode enabled)"
    return 1
  fi
  
  if checkpoint_exists "$phase_name"; then
    log_info "Skipping phase '$phase_name' (checkpoint exists)"
    return 0
  fi
  
  log_debug "Phase '$phase_name' will run (no checkpoint)"
  return 1
}

# Mark phase as complete
# Args: $1 - phase name
checkpoint_mark_complete() {
  local phase_name="$1"
  
  checkpoint_create "$phase_name" || {
    log_error "Failed to mark phase complete: $phase_name"
    return 1
  }
  
  log_info "Phase marked complete: $phase_name"
  return 0
}

# Cleanup old checkpoints (older than N days)
# Args: $1 - days (default: 7)
checkpoint_cleanup_old() {
  local days="${1:-7}"
  
  if [[ ! -d "$CHECKPOINT_DIR" ]]; then
    return 0
  fi
  
  local count
  count=$(find "$CHECKPOINT_DIR" -name "*.checkpoint" -type f -mtime "+$days" 2>/dev/null | wc -l)
  
  if [[ $count -gt 0 ]]; then
    find "$CHECKPOINT_DIR" -name "*.checkpoint" -type f -mtime "+$days" -delete 2>/dev/null || true
    log_info "Cleaned up $count old checkpoint(s) (older than $days days)"
  fi
  
  return 0
}

# Handle force mode - clear all checkpoints if force mode is enabled
# Environment: FORCE_MODE - if "true", clear all checkpoints
# Returns: 0 on success
checkpoint_handle_force_mode() {
  local force_mode="${FORCE_MODE:-false}"
  
  if [[ "${force_mode}" != "true" ]]; then
    log_debug "Force mode not enabled, checkpoints preserved"
    return 0
  fi
  
  local count
  count=$(checkpoint_count)
  
  if [[ $count -eq 0 ]]; then
    log_info "Force mode enabled (no existing checkpoints to clear)"
    return 0
  fi
  
  log_warning "Force mode enabled: clearing $count existing checkpoint(s)"
  checkpoint_clear_all
  
  log_info "All checkpoints cleared - full re-provisioning will occur"
  return 0
}

# Get checkpoint metadata
# Args: $1 - checkpoint name
# Returns: full checkpoint file contents
checkpoint_get_metadata() {
  local checkpoint_name="$1"
  local checkpoint_file="${CHECKPOINT_DIR}/${checkpoint_name}.checkpoint"
  
  if [[ ! -f "$checkpoint_file" ]]; then
    return 1
  fi
  
  cat "$checkpoint_file"
}

# Get checkpoint creation timestamp
# Args: $1 - checkpoint name
# Returns: ISO 8601 timestamp
checkpoint_get_created_at() {
  local checkpoint_name="$1"
  checkpoint_get_timestamp "$checkpoint_name"
}

# Calculate checkpoint age in seconds
# Args: $1 - checkpoint name
# Returns: age in seconds
checkpoint_age_seconds() {
  local checkpoint_name="$1"
  local timestamp
  
  timestamp=$(checkpoint_get_timestamp "$checkpoint_name")
  if [[ -z "$timestamp" ]]; then
    return 1
  fi
  
  local created_epoch
  local current_epoch
  
  created_epoch=$(date -d "$timestamp" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%SZ" "$timestamp" +%s 2>/dev/null)
  current_epoch=$(date +%s)
  
  echo $((current_epoch - created_epoch))
}

# Export checkpoint as JSON
# Args: $1 - checkpoint name
# Returns: JSON representation
checkpoint_export() {
  local checkpoint_name="$1"
  local checkpoint_file="${CHECKPOINT_DIR}/${checkpoint_name}.checkpoint"
  
  if [[ ! -f "$checkpoint_file" ]]; then
    return 1
  fi
  
  local created_at
  local hostname
  local user
  
  created_at=$(grep "^CREATED_AT=" "$checkpoint_file" | cut -d'"' -f2)
  hostname=$(grep "^HOSTNAME=" "$checkpoint_file" | cut -d'"' -f2)
  user=$(grep "^USER=" "$checkpoint_file" | cut -d'"' -f2)
  
  cat <<EOF
{
  "checkpoint_name": "$checkpoint_name",
  "created_at": "$created_at",
  "hostname": "$hostname",
  "user": "$user"
}
EOF
}

# Import checkpoint from JSON (via stdin)
# Reads JSON from stdin and recreates checkpoint
checkpoint_import() {
  local json_input
  json_input=$(cat)
  
  local checkpoint_name
  local created_at
  local hostname
  local user
  
  checkpoint_name=$(echo "$json_input" | grep -o '"checkpoint_name": *"[^"]*"' | cut -d'"' -f4)
  created_at=$(echo "$json_input" | grep -o '"created_at": *"[^"]*"' | cut -d'"' -f4)
  hostname=$(echo "$json_input" | grep -o '"hostname": *"[^"]*"' | cut -d'"' -f4)
  user=$(echo "$json_input" | grep -o '"user": *"[^"]*"' | cut -d'"' -f4)
  
  if [[ -z "$checkpoint_name" ]]; then
    return 1
  fi
  
  local checkpoint_file="${CHECKPOINT_DIR}/${checkpoint_name}.checkpoint"
  
  cat > "$checkpoint_file" <<EOF
CHECKPOINT_NAME="$checkpoint_name"
CREATED_AT="$created_at"
HOSTNAME="$hostname"
USER="$user"
EOF
  
  chmod 640 "$checkpoint_file" 2>/dev/null || true
  
  return 0
}
