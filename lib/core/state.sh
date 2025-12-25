#!/bin/bash
# State Management Module
# Handles persistence of provisioning session state, phase tracking, and checkpoint metadata
#
# Usage:
#   source lib/core/state.sh
#   state_init_session
#   state_save_session
#   state_load_session <session_id>
#   state_update_phase <phase_name> <status>

set -euo pipefail

# Prevent multiple sourcing
if [[ -n "${_STATE_SH_LOADED:-}" ]]; then
  return 0
fi
readonly _STATE_SH_LOADED=1

# Source dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/logger.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/config.sh"

# State directory paths
readonly STATE_DIR="${VPS_PROVISION_STATE_DIR:-/var/vps-provision}"
readonly SESSIONS_DIR="${STATE_DIR}/sessions"
readonly CHECKPOINTS_DIR="${STATE_DIR}/checkpoints"
readonly CHECKPOINT_METADATA="${CHECKPOINTS_DIR}/metadata.json"

# Current session variables
CURRENT_SESSION_ID=""
CURRENT_SESSION_FILE=""

# Initialize state directories
state_init_dirs() {
  log_debug "Initializing state directories"
  
  mkdir -p "${SESSIONS_DIR}" || {
    log_error "Failed to create sessions directory: ${SESSIONS_DIR}"
    return 1
  }
  
  mkdir -p "${CHECKPOINTS_DIR}" || {
    log_error "Failed to create checkpoints directory: ${CHECKPOINTS_DIR}"
    return 1
  }
  
  # Initialize checkpoint metadata if it doesn't exist
  if [[ ! -f "${CHECKPOINT_METADATA}" ]]; then
    echo "[]" > "${CHECKPOINT_METADATA}"
  fi
  
  log_info "State directories initialized"
  return 0
}

# Generate session ID in YYYYMMDD-HHMMSS format
state_generate_session_id() {
  date +"%Y%m%d-%H%M%S"
}

# Initialize a new provisioning session
state_init_session() {
  log_info "Initializing new provisioning session"
  
  state_init_dirs || return 1
  
  CURRENT_SESSION_ID=$(state_generate_session_id)
  CURRENT_SESSION_FILE="${SESSIONS_DIR}/session-${CURRENT_SESSION_ID}.json"
  
  # Export for subprocesses and tests
  export CURRENT_SESSION_ID
  export CURRENT_SESSION_FILE
  
  # Create initial session state
  local start_time
  start_time=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  
  cat > "${CURRENT_SESSION_FILE}" <<EOF
{
  "session_id": "${CURRENT_SESSION_ID}",
  "start_time": "${start_time}",
  "end_time": null,
  "status": "INITIALIZING",
  "duration_seconds": 0,
  "phases": [],
  "error_details": null,
  "vps_info": {},
  "developer_user": null,
  "ide_installations": []
}
EOF
  
  log_info "Session initialized: ${CURRENT_SESSION_ID}"
  echo "${CURRENT_SESSION_ID}"
  return 0
}

# Load existing session state
state_load_session() {
  local session_id="${1}"
  
  if [[ -z "${session_id}" ]]; then
    log_error "Session ID required for state_load_session"
    return 1
  fi
  
  local session_file="${SESSIONS_DIR}/session-${session_id}.json"
  
  if [[ ! -f "${session_file}" ]]; then
    log_error "Session file not found: ${session_file}"
    return 1
  fi
  
  CURRENT_SESSION_ID="${session_id}"
  CURRENT_SESSION_FILE="${session_file}"
  
  # Export for subprocesses and tests
  export CURRENT_SESSION_ID
  export CURRENT_SESSION_FILE
  
  log_info "Loaded session: ${session_id}"
  return 0
}

# Get current session state as JSON
state_get_session() {
  if [[ -z "${CURRENT_SESSION_FILE}" ]] || [[ ! -f "${CURRENT_SESSION_FILE}" ]]; then
    log_error "No active session"
    return 1
  fi
  
  cat "${CURRENT_SESSION_FILE}"
}

# Update session status
state_update_status() {
  local new_status="${1}"
  
  if [[ -z "${CURRENT_SESSION_FILE}" ]]; then
    log_error "No active session"
    return 1
  fi
  
  log_debug "Updating session status to: ${new_status}"
  
  # Use jq to update status and calculate duration if completing
  local updated_json
  if [[ "${new_status}" == "COMPLETED" ]] || [[ "${new_status}" == "FAILED" ]] || [[ "${new_status}" == "ROLLED_BACK" ]]; then
    local end_time
    end_time=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    updated_json=$(jq --arg status "${new_status}" \
                      --arg end_time "${end_time}" \
                      '.status = $status | .end_time = $end_time' \
                      "${CURRENT_SESSION_FILE}")
  else
    updated_json=$(jq --arg status "${new_status}" \
                      '.status = $status' \
                      "${CURRENT_SESSION_FILE}")
  fi
  
  echo "${updated_json}" > "${CURRENT_SESSION_FILE}"
  return 0
}

# Add or update phase execution state
state_update_phase() {
  local phase_name="${1}"
  local status="${2}"
  
  if [[ -z "${CURRENT_SESSION_FILE}" ]]; then
    log_error "No active session"
    return 1
  fi
  
  log_debug "Updating phase ${phase_name} to status: ${status}"
  
  local timestamp
  timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  
  # Check if phase already exists
  local phase_exists
  phase_exists=$(jq --arg name "${phase_name}" \
                    '.phases | any(.phase_name == $name)' \
                    "${CURRENT_SESSION_FILE}")
  
  if [[ "${phase_exists}" == "true" ]]; then
    # Update existing phase
    local updated_json
    if [[ "${status}" == "RUNNING" ]]; then
      updated_json=$(jq --arg name "${phase_name}" \
                        --arg status "${status}" \
                        --arg timestamp "${timestamp}" \
                        '(.phases[] | select(.phase_name == $name)) |= 
                         (.status = $status | .start_time = $timestamp)' \
                        "${CURRENT_SESSION_FILE}")
    elif [[ "${status}" == "COMPLETED" ]] || [[ "${status}" == "FAILED" ]]; then
      updated_json=$(jq --arg name "${phase_name}" \
                        --arg status "${status}" \
                        --arg timestamp "${timestamp}" \
                        '(.phases[] | select(.phase_name == $name)) |= 
                         (.status = $status | .end_time = $timestamp)' \
                        "${CURRENT_SESSION_FILE}")
    else
      updated_json=$(jq --arg name "${phase_name}" \
                        --arg status "${status}" \
                        '(.phases[] | select(.phase_name == $name)) |= (.status = $status)' \
                        "${CURRENT_SESSION_FILE}")
    fi
  else
    # Add new phase
    local new_phase
    new_phase=$(cat <<EOF
{
  "phase_name": "${phase_name}",
  "status": "${status}",
  "start_time": $(if [[ "${status}" == "RUNNING" ]]; then echo "\"${timestamp}\""; else echo "null"; fi),
  "end_time": null,
  "duration_seconds": 0,
  "checkpoint_exists": false,
  "actions": [],
  "error_message": null
}
EOF
    )
    
    updated_json=$(jq --argjson phase "${new_phase}" \
                      '.phases += [$phase]' \
                      "${CURRENT_SESSION_FILE}")
  fi
  
  echo "${updated_json}" > "${CURRENT_SESSION_FILE}"
  return 0
}

# Add action to current phase
state_add_action() {
  local phase_name="${1}"
  local action_type="${2}"
  local target="${3}"
  local status="${4}"
  local rollback_cmd="${5:-}"
  
  if [[ -z "${CURRENT_SESSION_FILE}" ]]; then
    log_error "No active session"
    return 1
  fi
  
  local timestamp
  timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  
  local new_action
  new_action=$(cat <<EOF
{
  "action_type": "${action_type}",
  "target": "${target}",
  "status": "${status}",
  "rollback_command": "${rollback_cmd}",
  "timestamp": "${timestamp}",
  "output": ""
}
EOF
  )
  
  local updated_json
  updated_json=$(jq --arg name "${phase_name}" \
                    --argjson action "${new_action}" \
                    '(.phases[] | select(.phase_name == $name).actions) += [$action]' \
                    "${CURRENT_SESSION_FILE}")
  
  echo "${updated_json}" > "${CURRENT_SESSION_FILE}"
  return 0
}

# Set VPS instance information
state_set_vps_info() {
  local vps_info_json="${1}"
  
  if [[ -z "${CURRENT_SESSION_FILE}" ]]; then
    log_error "No active session"
    return 1
  fi
  
  local updated_json
  updated_json=$(jq --argjson info "${vps_info_json}" \
                    '.vps_info = $info' \
                    "${CURRENT_SESSION_FILE}")
  
  echo "${updated_json}" > "${CURRENT_SESSION_FILE}"
  return 0
}

# Set developer user information
state_set_developer_user() {
  local user_info_json="${1}"
  
  if [[ -z "${CURRENT_SESSION_FILE}" ]]; then
    log_error "No active session"
    return 1
  fi
  
  local updated_json
  updated_json=$(jq --argjson user "${user_info_json}" \
                    '.developer_user = $user' \
                    "${CURRENT_SESSION_FILE}")
  
  echo "${updated_json}" > "${CURRENT_SESSION_FILE}"
  return 0
}

# Add IDE installation record
state_add_ide() {
  local ide_info_json="${1}"
  
  if [[ -z "${CURRENT_SESSION_FILE}" ]]; then
    log_error "No active session"
    return 1
  fi
  
  local updated_json
  updated_json=$(jq --argjson ide "${ide_info_json}" \
                    '.ide_installations += [$ide]' \
                    "${CURRENT_SESSION_FILE}")
  
  echo "${updated_json}" > "${CURRENT_SESSION_FILE}"
  return 0
}

# Get list of all sessions
state_list_sessions() {
  if [[ ! -d "${SESSIONS_DIR}" ]]; then
    echo "[]"
    return 0
  fi
  
  local sessions=()
  while IFS= read -r -d '' session_file; do
    local session_id
    session_id=$(basename "${session_file}" | sed 's/session-\(.*\)\.json/\1/')
    sessions+=("\"${session_id}\"")
  done < <(find "${SESSIONS_DIR}" -name "session-*.json" -print0 | sort -rz)
  
  echo "[$(IFS=,; echo "${sessions[*]}")]"
}

# Get latest session ID
state_get_latest_session() {
  local sessions
  sessions=$(state_list_sessions)
  echo "${sessions}" | jq -r '.[0] // empty'
}

# Save checkpoint metadata
state_save_checkpoint_metadata() {
  local phase_name="${1}"
  local checksum="${2}"
  
  if [[ -z "${CURRENT_SESSION_ID}" ]]; then
    log_error "No active session"
    return 1
  fi
  
  local completed_at
  completed_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  
  local checkpoint_entry
  checkpoint_entry=$(cat <<EOF
{
  "phase_name": "${phase_name}",
  "completed_at": "${completed_at}",
  "session_id": "${CURRENT_SESSION_ID}",
  "checksum": "${checksum}",
  "verification_files": []
}
EOF
  )
  
  # Load existing metadata
  local metadata
  metadata=$(cat "${CHECKPOINT_METADATA}")
  
  # Remove any existing entry for this phase
  metadata=$(echo "${metadata}" | jq --arg name "${phase_name}" \
             'map(select(.phase_name != $name))')
  
  # Add new entry
  metadata=$(echo "${metadata}" | jq --argjson entry "${checkpoint_entry}" \
             '. += [$entry]')
  
  echo "${metadata}" > "${CHECKPOINT_METADATA}"
  log_debug "Checkpoint metadata saved for phase: ${phase_name}"
  return 0
}

# Get checkpoint metadata for a phase
state_get_checkpoint_metadata() {
  local phase_name="${1}"
  
  if [[ ! -f "${CHECKPOINT_METADATA}" ]]; then
    echo "null"
    return 0
  fi
  
  jq --arg name "${phase_name}" \
     '.[] | select(.phase_name == $name)' \
     "${CHECKPOINT_METADATA}"
}

# Save current session state to file (stub - state auto-saves on updates)
state_save_session() {
  if [[ -z "${CURRENT_SESSION_FILE}" ]]; then
    log_error "No active session"
    return 1
  fi
  
  # State is already persisted by update functions
  log_debug "Session state saved: ${CURRENT_SESSION_ID}"
  return 0
}

# Set session status (alias for state_update_status)
state_set_session_status() {
  state_update_status "$1"
}

# Set error details in session
state_set_error_details() {
  local error_message="${1}"
  
  if [[ -z "${CURRENT_SESSION_FILE}" ]]; then
    log_error "No active session"
    return 1
  fi
  
  local updated_json
  updated_json=$(jq --arg error "${error_message}" \
                    '.error_details = $error' \
                    "${CURRENT_SESSION_FILE}")
  
  echo "${updated_json}" > "${CURRENT_SESSION_FILE}"
  return 0
}

# Get session duration in seconds
state_get_session_duration() {
  if [[ -z "${CURRENT_SESSION_FILE}" ]]; then
    log_error "No active session"
    return 1
  fi
  
  local start_time
  start_time=$(jq -r '.start_time' "${CURRENT_SESSION_FILE}")
  
  if [[ -z "${start_time}" ]] || [[ "${start_time}" == "null" ]]; then
    echo "0"
    return 0
  fi
  
  local start_epoch
  local current_epoch
  
  start_epoch=$(date -d "${start_time}" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%SZ" "${start_time}" +%s 2>/dev/null)
  current_epoch=$(date +%s)
  
  echo $((current_epoch - start_epoch))
}

# Finalize session with end time and duration
state_finalize_session() {
  local final_status="${1}"
  
  if [[ -z "${CURRENT_SESSION_FILE}" ]]; then
    log_error "No active session"
    return 1
  fi
  
  local end_time
  local duration
  
  end_time=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  duration=$(state_get_session_duration)
  
  local updated_json
  updated_json=$(jq --arg status "${final_status}" \
                    --arg end_time "${end_time}" \
                    --argjson duration "${duration}" \
                    '.status = $status | .end_time = $end_time | .duration_seconds = $duration' \
                    "${CURRENT_SESSION_FILE}")
  
  echo "${updated_json}" > "${CURRENT_SESSION_FILE}"
  log_info "Session finalized: ${CURRENT_SESSION_ID} (${final_status})"
  return 0
}

# Delete a session
state_delete_session() {
  local session_id="${1}"
  local session_file="${SESSIONS_DIR}/session-${session_id}.json"
  
  if [[ ! -f "${session_file}" ]]; then
    log_warning "Session file not found: ${session_id}"
    return 1
  fi
  
  rm -f "${session_file}" || {
    log_error "Failed to delete session: ${session_id}"
    return 1
  }
  
  log_debug "Session deleted: ${session_id}"
  return 0
}

# Export session as JSON
state_export_session() {
  local session_id="${1}"
  local session_file="${SESSIONS_DIR}/session-${session_id}.json"
  
  if [[ ! -f "${session_file}" ]]; then
    log_error "Session file not found: ${session_id}"
    return 1
  fi
  
  cat "${session_file}"
}

# Import session from JSON (via stdin)
state_import_session() {
  local json_input
  json_input=$(cat)
  
  local session_id
  session_id=$(echo "${json_input}" | jq -r '.session_id')
  
  if [[ -z "${session_id}" ]] || [[ "${session_id}" == "null" ]]; then
    log_error "Invalid session JSON: missing session_id"
    return 1
  fi
  
  local session_file="${SESSIONS_DIR}/session-${session_id}.json"
  
  echo "${json_input}" > "${session_file}"
  log_debug "Session imported: ${session_id}"
  return 0
}

# Add IDE installation record (simplified version)
state_add_ide_installation() {
  local ide_name="${1}"
  local ide_version="${2}"
  local ide_status="${3}"
  
  if [[ -z "${CURRENT_SESSION_FILE}" ]]; then
    log_error "No active session"
    return 1
  fi
  
  local ide_info
  ide_info=$(cat <<EOF
{
  "name": "${ide_name}",
  "version": "${ide_version}",
  "status": "${ide_status}",
  "installed_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
EOF
  )
  
  state_add_ide "${ide_info}"
}

# Cleanup old sessions (older than N days)
state_cleanup_old_sessions() {
  local days="${1:-7}"
  
  if [[ ! -d "${SESSIONS_DIR}" ]]; then
    return 0
  fi
  
  local count
  count=$(find "${SESSIONS_DIR}" -name "session-*.json" -type f -mtime "+${days}" 2>/dev/null | wc -l)
  
  if [[ $count -gt 0 ]]; then
    find "${SESSIONS_DIR}" -name "session-*.json" -type f -mtime "+${days}" -delete 2>/dev/null || true
    log_info "Cleaned up ${count} old session(s) (older than ${days} days)"
  fi
  
  return 0
}

# Validate session integrity
state_validate_session() {
  local session_id="${1}"
  local session_file="${SESSIONS_DIR}/session-${session_id}.json"
  
  if [[ ! -f "${session_file}" ]]; then
    log_error "Session file not found: ${session_id}"
    return 1
  fi
  
  # Validate JSON structure
  if ! jq empty "${session_file}" 2>/dev/null; then
    log_error "Session file is not valid JSON: ${session_id}"
    return 1
  fi
  
  # Check required fields
  local required_fields=("session_id" "start_time" "status")
  local field
  
  for field in "${required_fields[@]}"; do
    local value
    value=$(jq -r ".${field}" "${session_file}")
    if [[ -z "${value}" ]] || [[ "${value}" == "null" ]]; then
      log_error "Session missing required field: ${field}"
      return 1
    fi
  done
  
  log_debug "Session validated: ${session_id}"
  return 0
}

# Get all phases from current session
state_get_all_phases() {
  if [[ -z "${CURRENT_SESSION_FILE}" ]]; then
    log_error "No active session"
    return 1
  fi
  
  jq -r '.phases[].phase_name' "${CURRENT_SESSION_FILE}"
}

# Get phase status
state_get_phase_status() {
  local phase_name="${1}"
  
  if [[ -z "${CURRENT_SESSION_FILE}" ]]; then
    log_error "No active session"
    return 1
  fi
  
  jq -r --arg name "${phase_name}" \
     '.phases[] | select(.phase_name == $name) | .status' \
     "${CURRENT_SESSION_FILE}"
}

# Modified state_set_vps_info to handle key-value pairs
state_set_vps_info() {
  local key="${1}"
  local value="${2}"
  
  if [[ -z "${CURRENT_SESSION_FILE}" ]]; then
    log_error "No active session"
    return 1
  fi
  
  # If first argument looks like JSON, use old behavior
  if [[ "${key}" =~ ^\{ ]]; then
    local vps_info_json="${key}"
    local updated_json
    updated_json=$(jq --argjson info "${vps_info_json}" \
                      '.vps_info = $info' \
                      "${CURRENT_SESSION_FILE}")
    echo "${updated_json}" > "${CURRENT_SESSION_FILE}"
  else
    # New behavior: key-value pairs
    local updated_json
    updated_json=$(jq --arg key "${key}" --arg value "${value}" \
                      '.vps_info[$key] = $value' \
                      "${CURRENT_SESSION_FILE}")
    echo "${updated_json}" > "${CURRENT_SESSION_FILE}"
  fi
  
  return 0
}

# Modified state_set_developer_user to handle username strings
state_set_developer_user() {
  local username="${1}"
  
  if [[ -z "${CURRENT_SESSION_FILE}" ]]; then
    log_error "No active session"
    return 1
  fi
  
  # If argument looks like JSON, use old behavior
  if [[ "${username}" =~ ^\{ ]]; then
    local user_info_json="${username}"
    local updated_json
    updated_json=$(jq --argjson user "${user_info_json}" \
                      '.developer_user = $user' \
                      "${CURRENT_SESSION_FILE}")
    echo "${updated_json}" > "${CURRENT_SESSION_FILE}"
  else
    # New behavior: simple username string
    local updated_json
    updated_json=$(jq --arg username "${username}" \
                      '.developer_user = $username' \
                      "${CURRENT_SESSION_FILE}")
    echo "${updated_json}" > "${CURRENT_SESSION_FILE}"
  fi
  
  return 0
}

# Export functions
export -f state_init_dirs
export -f state_generate_session_id
export -f state_init_session
export -f state_load_session
export -f state_get_session
export -f state_update_status
export -f state_update_phase
export -f state_add_action
export -f state_set_vps_info
export -f state_set_developer_user
export -f state_add_ide
export -f state_list_sessions
export -f state_get_latest_session
export -f state_save_checkpoint_metadata
export -f state_get_checkpoint_metadata
export -f state_save_session
export -f state_set_session_status
export -f state_set_error_details
export -f state_get_session_duration
export -f state_finalize_session
export -f state_delete_session
export -f state_export_session
export -f state_import_session
export -f state_add_ide_installation
export -f state_cleanup_old_sessions
export -f state_validate_session
export -f state_get_all_phases
export -f state_get_phase_status
