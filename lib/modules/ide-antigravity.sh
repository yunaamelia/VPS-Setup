#!/bin/bash
# IDE Antigravity Installation Module
# Purpose: Install Antigravity IDE via official APT repository
# Requirements: FR-019, FR-037, SC-009
# Documentation: https://antigravity.google/download/linux

set -euo pipefail

# Source dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(dirname "$SCRIPT_DIR")"

# shellcheck disable=SC1091
source "${LIB_DIR}/core/logger.sh"
# shellcheck disable=SC1091
source "${LIB_DIR}/core/checkpoint.sh"
# shellcheck disable=SC1091
source "${LIB_DIR}/core/transaction.sh"

# Constants
readonly ANTIGRAVITY_CHECKPOINT="${ANTIGRAVITY_CHECKPOINT:-ide-antigravity}"
readonly ANTIGRAVITY_GPG_URL="https://us-central1-apt.pkg.dev/doc/repo-signing-key.gpg"
readonly ANTIGRAVITY_GPG_KEY="/etc/apt/keyrings/antigravity-repo-key.gpg"
readonly ANTIGRAVITY_REPO="deb [signed-by=/etc/apt/keyrings/antigravity-repo-key.gpg] https://us-central1-apt.pkg.dev/projects/antigravity-auto-updater-dev/ antigravity-debian main"
readonly ANTIGRAVITY_LIST="/etc/apt/sources.list.d/antigravity.list"
readonly ANTIGRAVITY_DESKTOP="/usr/share/applications/antigravity.desktop"

#######################################
# Check prerequisites for Antigravity installation
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   0 if prerequisites met, 1 otherwise
#######################################
ide_antigravity_check_prerequisites() {
  log_info "Checking Antigravity prerequisites..."

  # Verify desktop environment is installed
  if ! checkpoint_exists "desktop-install"; then
    log_error "Desktop environment not installed (checkpoint missing: desktop-install)"
    return 1
  fi

  # Verify required commands
  local required_cmds=("wget" "curl" "gpg" "apt-get")
  for cmd in "${required_cmds[@]}"; do
    if ! command -v "$cmd" &>/dev/null; then
      log_error "Required command not found: $cmd"
      return 1
    fi
  done

  log_info "Antigravity prerequisites check passed"
  return 0
}

#######################################
# Add Antigravity GPG key
# Globals:
#   ANTIGRAVITY_GPG_URL, ANTIGRAVITY_GPG_KEY
# Arguments:
#   None
# Returns:
#   0 on success, 1 on failure
#######################################
ide_antigravity_add_gpg_key() {
  log_info "Adding Antigravity repository GPG key..."

  # Create keyrings directory if it doesn't exist
  mkdir -p /etc/apt/keyrings

  # Check if key already exists
  if [[ -f "$ANTIGRAVITY_GPG_KEY" ]]; then
    log_info "Antigravity GPG key already exists"
    return 0
  fi

  # Download and install GPG key with retry
  local max_retries=3
  local retry_count=0

  while ((retry_count < max_retries)); do
    if curl -fsSL "$ANTIGRAVITY_GPG_URL" | gpg --dearmor --yes -o "$ANTIGRAVITY_GPG_KEY"; then
      transaction_log "gpg_key_add" "rm -f '$ANTIGRAVITY_GPG_KEY'"
      log_info "Antigravity GPG key added successfully"
      return 0
    fi

    retry_count=$((retry_count + 1))
    if ((retry_count < max_retries)); then
      log_warning "Failed to download GPG key (attempt $retry_count/$max_retries), retrying..."
      sleep 2
    fi
  done

  log_error "Failed to add Antigravity GPG key after $max_retries attempts"
  return 1
}

#######################################
# Add Antigravity repository
# Globals:
#   ANTIGRAVITY_REPO, ANTIGRAVITY_LIST
# Arguments:
#   None
# Returns:
#   0 on success, 1 on failure
#######################################
ide_antigravity_add_repository() {
  log_info "Adding Antigravity repository..."

  # Check if repository already exists
  if [[ -f "$ANTIGRAVITY_LIST" ]]; then
    log_info "Antigravity repository already configured"
    return 0
  fi

  # Add repository
  if ! echo "$ANTIGRAVITY_REPO" | tee "$ANTIGRAVITY_LIST" >/dev/null; then
    log_error "Failed to add Antigravity repository"
    return 1
  fi

  transaction_log "repo_add" "rm -f '$ANTIGRAVITY_LIST'"
  log_info "Antigravity repository added successfully"
  return 0
}

#######################################
# Update APT cache after adding repository
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   0 on success, 1 on failure
#######################################
ide_antigravity_update_apt() {
  log_info "Updating APT cache..."

  if ! apt-get update 2>&1 | tee -a "${LOG_FILE:-/dev/null}"; then
    log_error "Failed to update APT cache"
    return 1
  fi

  log_info "APT cache updated successfully"
  return 0
}

#######################################
# Install Antigravity package
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   0 on success, 1 on failure
#######################################
ide_antigravity_install_package() {
  log_info "Installing Antigravity package..."

  # Check if already installed
  if dpkg -l antigravity 2>/dev/null | grep -q "^ii"; then
    log_info "Antigravity package already installed"
    return 0
  fi

  # Install with auto-fix for dependencies
  if ! DEBIAN_FRONTEND=noninteractive apt-get install -y --fix-broken antigravity 2>&1 |
    tee -a "${LOG_FILE:-/dev/null}"; then
    log_error "Failed to install Antigravity package"
    return 1
  fi

  transaction_log "package_install" "apt-get remove -y antigravity"
  log_info "Antigravity package installed successfully"
  return 0
}

#######################################
# Verify Antigravity installation
# Globals:
#   ANTIGRAVITY_DESKTOP
# Arguments:
#   None
# Returns:
#   0 if verification passes, 1 otherwise
#######################################
ide_antigravity_verify() {
  log_info "Verifying Antigravity installation..."

  # Check package status first (most reliable)
  if ! dpkg -l antigravity 2>/dev/null | grep -q "^ii"; then
    log_error "Antigravity package not properly installed (dpkg status check failed)"
    return 1
  fi

  # Check executable exists
  if ! command -v antigravity &>/dev/null; then
    log_error "Antigravity command not found in PATH"
    return 1
  fi

  # Check desktop launcher exists
  if [[ ! -f "$ANTIGRAVITY_DESKTOP" ]]; then
    log_warning "Antigravity desktop launcher not found at $ANTIGRAVITY_DESKTOP"
    # Non-fatal - desktop file might be created later
  fi

  # Verify binary is executable
  if [[ ! -x "$(command -v antigravity)" ]]; then
    log_error "Antigravity binary is not executable"
    return 1
  fi

  log_info "Antigravity verification passed"
  return 0
}

#######################################
# Main execution function for Antigravity installation
# Globals:
#   ANTIGRAVITY_CHECKPOINT
# Arguments:
#   None
# Returns:
#   0 on success, 1 on failure
#######################################
ide_antigravity_execute() {
  log_info "=== Starting Antigravity Installation ==="

  # Check if already completed
  if checkpoint_exists "$ANTIGRAVITY_CHECKPOINT"; then
    log_info "Antigravity installation already completed (checkpoint exists)"
    return 0
  fi

  # Check prerequisites
  if ! ide_antigravity_check_prerequisites; then
    log_error "Antigravity prerequisites check failed"
    return 1
  fi

  # Add GPG key
  if ! ide_antigravity_add_gpg_key; then
    log_error "Failed to add Antigravity GPG key"
    return 1
  fi

  # Add repository
  if ! ide_antigravity_add_repository; then
    log_error "Failed to add Antigravity repository"
    return 1
  fi

  # Update APT cache
  if ! ide_antigravity_update_apt; then
    log_error "Failed to update APT cache"
    return 1
  fi

  # Install package
  if ! ide_antigravity_install_package; then
    log_error "Failed to install Antigravity package"
    return 1
  fi

  # Verify installation
  if ! ide_antigravity_verify; then
    log_error "Antigravity verification failed"
    return 1
  fi

  # Create checkpoint
  checkpoint_create "$ANTIGRAVITY_CHECKPOINT"

  log_info "=== Antigravity Installation Completed Successfully ==="
  return 0
}

# Export functions for testing
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
  export -f ide_antigravity_check_prerequisites
  export -f ide_antigravity_add_gpg_key
  export -f ide_antigravity_add_repository
  export -f ide_antigravity_update_apt
  export -f ide_antigravity_install_package
  export -f ide_antigravity_verify
  export -f ide_antigravity_execute
fi
