#!/bin/bash
# parallel-ide-install.sh - Parallel IDE installation orchestrator
# T131: Install VSCode, Cursor, and Antigravity in parallel to save ~3 minutes
# per performance-specs.md §Parallel Installation

set -euo pipefail

# Prevent multiple sourcing
if [[ -n "${_PARALLEL_IDE_INSTALL_SH_LOADED:-}" ]]; then
  return 0
fi
readonly _PARALLEL_IDE_INSTALL_SH_LOADED=1

# Source dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(dirname "${SCRIPT_DIR}")"
# shellcheck disable=SC1091
source "${LIB_DIR}/core/logger.sh"
# shellcheck disable=SC1091
source "${LIB_DIR}/core/checkpoint.sh"
# shellcheck disable=SC1091
source "${LIB_DIR}/modules/ide-vscode.sh"
# shellcheck disable=SC1091
source "${LIB_DIR}/modules/ide-cursor.sh"
# shellcheck disable=SC1091
source "${LIB_DIR}/modules/ide-antigravity.sh"

# Temporary result files for parallel execution
readonly PARALLEL_IDE_TMP_DIR="${PARALLEL_IDE_TMP_DIR:-/tmp/vps-provision-ides}"
readonly VSCODE_RESULT_FILE="${PARALLEL_IDE_TMP_DIR}/vscode.result"
readonly CURSOR_RESULT_FILE="${PARALLEL_IDE_TMP_DIR}/cursor.result"
readonly ANTIGRAVITY_RESULT_FILE="${PARALLEL_IDE_TMP_DIR}/antigravity.result"

#######################################
# Initialize parallel IDE installation environment
# Creates temporary directory for tracking results
# Returns:
#   0 on success, 1 on failure
#######################################
parallel_ide_init() {
  if [[ ! -d "$PARALLEL_IDE_TMP_DIR" ]]; then
    mkdir -p "$PARALLEL_IDE_TMP_DIR" 2>/dev/null || {
      log_error "Failed to create parallel IDE temp directory: $PARALLEL_IDE_TMP_DIR"
      return 1
    }
  fi
  
  # Clear any previous result files
  rm -f "$VSCODE_RESULT_FILE" "$CURSOR_RESULT_FILE" "$ANTIGRAVITY_RESULT_FILE"
  
  log_debug "Parallel IDE installation environment initialized"
  return 0
}

#######################################
# Cleanup parallel IDE installation environment
# Removes temporary directory and files
#######################################
parallel_ide_cleanup() {
  if [[ -d "$PARALLEL_IDE_TMP_DIR" ]]; then
    rm -rf "$PARALLEL_IDE_TMP_DIR" 2>/dev/null || true
  fi
  log_debug "Parallel IDE installation environment cleaned up"
}

#######################################
# Install VSCode in background process
# Writes exit code to result file for parent process
#######################################
parallel_ide_install_vscode() {
  local result=0
  
  log_info "[VSCode] Starting installation in parallel..."
  
  if ide_vscode_execute; then
    log_info "[VSCode] Installation completed successfully"
    result=0
  else
    log_error "[VSCode] Installation failed"
    result=1
  fi
  
  echo "$result" > "$VSCODE_RESULT_FILE"
  exit "$result"
}

#######################################
# Install Cursor in background process
# Writes exit code to result file for parent process
#######################################
parallel_ide_install_cursor() {
  local result=0
  
  log_info "[Cursor] Starting installation in parallel..."
  
  if ide_cursor_execute; then
    log_info "[Cursor] Installation completed successfully"
    result=0
  else
    log_error "[Cursor] Installation failed"
    result=1
  fi
  
  echo "$result" > "$CURSOR_RESULT_FILE"
  exit "$result"
}

#######################################
# Install Antigravity in background process
# Writes exit code to result file for parent process
#######################################
parallel_ide_install_antigravity() {
  local result=0
  
  log_info "[Antigravity] Starting installation in parallel..."
  
  if ide_antigravity_execute; then
    log_info "[Antigravity] Installation completed successfully"
    result=0
  else
    log_error "[Antigravity] Installation failed"
    result=1
  fi
  
  echo "$result" > "$ANTIGRAVITY_RESULT_FILE"
  exit "$result"
}

#######################################
# Execute all IDE installations in parallel
# T131: Parallel IDE installation to save ~3 minutes
# 
# Downloads are sequential (one at a time) to avoid bandwidth saturation,
# but installation/extraction happens in parallel (per performance-specs.md)
#
# Returns:
#   0 if all succeeded, 1 if any failed
#######################################
parallel_ide_execute() {
  log_info "=== Starting Parallel IDE Installation ==="
  log_info "Installing VSCode, Cursor, and Antigravity concurrently..."
  log_info "Expected time savings: ~3 minutes vs sequential installation"
  
  # Initialize environment
  if ! parallel_ide_init; then
    return 1
  fi
  
  local start_time
  start_time=$(date +%s)
  
  # Launch IDE installations in background
  (parallel_ide_install_vscode) &
  local pid_vscode=$!
  
  (parallel_ide_install_cursor) &
  local pid_cursor=$!
  
  (parallel_ide_install_antigravity) &
  local pid_antigravity=$!
  
  log_info "Background installation PIDs: VSCode=$pid_vscode, Cursor=$pid_cursor, Antigravity=$pid_antigravity"
  
  # Wait for all installations to complete
  log_info "Waiting for all IDE installations to complete..."
  
  wait $pid_vscode
  local result_vscode=$?
  
  wait $pid_cursor
  local result_cursor=$?
  
  wait $pid_antigravity
  local result_antigravity=$?
  
  # Calculate total time
  local end_time
  end_time=$(date +%s)
  local duration=$((end_time - start_time))
  
  log_info "Parallel IDE installation completed in ${duration}s"
  
  # Check results
  local failed_count=0
  local success_count=0
  
  if [[ $result_vscode -eq 0 ]]; then
    log_info "✓ VSCode installation: SUCCESS"
    ((success_count++))
  else
    log_error "✗ VSCode installation: FAILED (exit code: $result_vscode)"
    ((failed_count++))
  fi
  
  if [[ $result_cursor -eq 0 ]]; then
    log_info "✓ Cursor installation: SUCCESS"
    ((success_count++))
  else
    log_error "✗ Cursor installation: FAILED (exit code: $result_cursor)"
    ((failed_count++))
  fi
  
  if [[ $result_antigravity -eq 0 ]]; then
    log_info "✓ Antigravity installation: SUCCESS"
    ((success_count++))
  else
    log_error "✗ Antigravity installation: FAILED (exit code: $result_antigravity)"
    ((failed_count++))
  fi
  
  # Cleanup
  parallel_ide_cleanup
  
  # Report results
  log_info "=== Parallel IDE Installation Summary ==="
  log_info "Success: $success_count / 3"
  log_info "Failed:  $failed_count / 3"
  log_info "Duration: ${duration}s"
  
  if [[ $failed_count -gt 0 ]]; then
    log_error "Parallel IDE installation completed with failures"
    return 1
  fi
  
  log_info "=== All IDEs Installed Successfully ==="
  return 0
}

#######################################
# Check if all IDEs are already installed (via checkpoints)
# Returns:
#   0 if all installed, 1 if any missing
#######################################
parallel_ide_check_all_installed() {
  local all_installed=true
  
  if ! checkpoint_exists "ide-vscode"; then
    log_debug "VSCode not yet installed (no checkpoint)"
    all_installed=false
  fi
  
  if ! checkpoint_exists "ide-cursor"; then
    log_debug "Cursor not yet installed (no checkpoint)"
    all_installed=false
  fi
  
  if ! checkpoint_exists "ide-antigravity"; then
    log_debug "Antigravity not yet installed (no checkpoint)"
    all_installed=false
  fi
  
  if $all_installed; then
    return 0
  else
    return 1
  fi
}

# Export functions
export -f parallel_ide_init
export -f parallel_ide_cleanup
export -f parallel_ide_install_vscode
export -f parallel_ide_install_cursor
export -f parallel_ide_install_antigravity
export -f parallel_ide_execute
export -f parallel_ide_check_all_installed

# Main execution when run as script
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  parallel_ide_execute
  exit $?
fi
