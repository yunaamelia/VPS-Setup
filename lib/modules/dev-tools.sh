#!/bin/bash
# Development Tools Module
# Installs and configures essential development utilities including git, vim,
# curl, jq, htop, tree, and other common developer tools
#
# Usage:
#   source lib/modules/dev-tools.sh
#   dev_tools_execute
#
# Dependencies:
#   - lib/core/logger.sh
#   - lib/core/checkpoint.sh
#   - lib/core/transaction.sh
#   - lib/core/progress.sh

set -euo pipefail

# Prevent multiple sourcing
if [[ -n "${_DEV_TOOLS_SH_LOADED:-}" ]]; then
  return 0
fi
readonly _DEV_TOOLS_SH_LOADED=1

# Source dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(dirname "${SCRIPT_DIR}")"
source "${LIB_DIR}/core/logger.sh"
source "${LIB_DIR}/core/checkpoint.sh"
source "${LIB_DIR}/core/transaction.sh"
source "${LIB_DIR}/core/progress.sh"

# Module constants
readonly DEV_TOOLS_PHASE="${DEV_TOOLS_PHASE:-dev-tools}"

# Development tools to install
readonly -a CORE_TOOLS=(
  "git"
  "vim"
  "curl"
  "wget"
  "jq"
  "htop"
  "tree"
  "tmux"
  "net-tools"
  "dnsutils"
)

# dev_tools_check_prerequisites
# Validates system is ready for development tools installation
#
# Returns:
#   0 - Prerequisites met
#   1 - Prerequisites failed
dev_tools_check_prerequisites() {
  log_info "Checking development tools prerequisites"
  
  # Verify system-prep phase completed
  if ! checkpoint_exists "system-prep"; then
    log_error "System preparation must be completed before dev tools installation"
    return 1
  fi
  
  # Verify apt is available
  if ! command -v apt-get &> /dev/null; then
    log_error "apt-get not found (required for package installation)"
    return 1
  fi
  
  log_info "Prerequisites check passed"
  return 0
}

# dev_tools_update_package_cache
# Updates APT package cache before installation
#
# Returns:
#   0 - Update successful
#   1 - Update failed
dev_tools_update_package_cache() {
  log_info "Updating package cache"
  
  if ! apt-get update -qq 2>&1 | tee -a "${LOG_FILE}"; then
    log_error "Failed to update package cache"
    return 1
  fi
  
  log_info "Package cache updated successfully"
  return 0
}

# dev_tools_install_package
# Installs a single package with verification
#
# Args:
#   $1 - Package name
#
# Returns:
#   0 - Installation successful
#   1 - Installation failed
dev_tools_install_package() {
  local package="$1"
  log_info "Installing package: ${package}"
  
  # Check if already installed
  if dpkg -l "${package}" 2>/dev/null | grep -q "^ii"; then
    log_info "Package already installed: ${package}"
    return 0
  fi
  
  # Install package
  if ! apt-get install -y "${package}" 2>&1 | tee -a "${LOG_FILE}"; then
    log_error "Failed to install package: ${package}"
    return 1
  fi
  
  # Verify installation
  if ! dpkg -l "${package}" 2>/dev/null | grep -q "^ii"; then
    log_error "Package installation verification failed: ${package}"
    return 1
  fi
  
  transaction_log "apt-get remove -y ${package}"
  log_info "Package installed successfully: ${package}"
  return 0
}

# dev_tools_install_core_tools
# Installs all core development tools
#
# Returns:
#   0 - All tools installed successfully
#   1 - One or more tools failed to install
dev_tools_install_core_tools() {
  log_info "Installing core development tools"
  
  local failed=0
  local installed=0
  
  for tool in "${CORE_TOOLS[@]}"; do
    if dev_tools_install_package "${tool}"; then
      ((installed++))
    else
      log_warning "Failed to install tool: ${tool}"
      ((failed++))
    fi
  done
  
  log_info "Installation summary: ${installed} succeeded, ${failed} failed"
  
  if [[ "${failed}" -gt 0 ]]; then
    log_error "Some tools failed to install"
    return 1
  fi
  
  log_info "All core development tools installed successfully"
  return 0
}

# dev_tools_configure_git
# Configures global git settings
#
# Returns:
#   0 - Configuration successful
#   1 - Configuration failed
dev_tools_configure_git() {
  log_info "Configuring global git settings"
  
  # Set default branch name to main
  if ! git config --global init.defaultBranch main 2>&1 | tee -a "${LOG_FILE}"; then
    log_warning "Failed to set default branch name"
  else
    transaction_log "git config --global --unset init.defaultBranch"
    log_debug "Default branch name set to 'main'"
  fi
  
  # Set pull strategy to rebase
  if ! git config --global pull.rebase false 2>&1 | tee -a "${LOG_FILE}"; then
    log_warning "Failed to set pull strategy"
  else
    transaction_log "git config --global --unset pull.rebase"
    log_debug "Pull strategy set to merge (default)"
  fi
  
  # Enable colored output
  if ! git config --global color.ui auto 2>&1 | tee -a "${LOG_FILE}"; then
    log_warning "Failed to enable colored output"
  else
    transaction_log "git config --global --unset color.ui"
    log_debug "Colored output enabled"
  fi
  
  # Set default editor to vim
  if ! git config --global core.editor vim 2>&1 | tee -a "${LOG_FILE}"; then
    log_warning "Failed to set default editor"
  else
    transaction_log "git config --global --unset core.editor"
    log_debug "Default editor set to vim"
  fi
  
  # Configure credential helper cache (1 hour)
  if ! git config --global credential.helper "cache --timeout=3600" 2>&1 | tee -a "${LOG_FILE}"; then
    log_warning "Failed to configure credential helper"
  else
    transaction_log "git config --global --unset credential.helper"
    log_debug "Credential helper configured (1 hour cache)"
  fi
  
  log_info "Git configuration completed"
  return 0
}

# dev_tools_verify_tool
# Verifies that a tool is installed and executable
#
# Args:
#   $1 - Tool name/command
#
# Returns:
#   0 - Tool verified
#   1 - Tool not found or not executable
dev_tools_verify_tool() {
  local tool="$1"
  
  if ! command -v "${tool}" &> /dev/null; then
    log_error "Tool not found or not executable: ${tool}"
    return 1
  fi
  
  log_debug "Tool verified: ${tool}"
  return 0
}

# dev_tools_verify_all_tools
# Verifies that all installed tools are executable
#
# Returns:
#   0 - All tools verified
#   1 - One or more tools failed verification
dev_tools_verify_all_tools() {
  log_info "Verifying all development tools"
  
  local failed=0
  local verified=0
  
  for tool in "${CORE_TOOLS[@]}"; do
    if dev_tools_verify_tool "${tool}"; then
      ((verified++))
    else
      log_warning "Tool verification failed: ${tool}"
      ((failed++))
    fi
  done
  
  log_info "Verification summary: ${verified} succeeded, ${failed} failed"
  
  if [[ "${failed}" -gt 0 ]]; then
    log_error "Some tools failed verification"
    return 1
  fi
  
  log_info "All development tools verified successfully"
  return 0
}

# dev_tools_validate
# Validates development tools installation
#
# Returns:
#   0 - Validation successful
#   1 - Validation failed
dev_tools_validate() {
  log_info "Validating development tools installation"
  
  local validation_passed=true
  
  # Verify all core tools are installed
  for tool in "${CORE_TOOLS[@]}"; do
    if ! dpkg -l "${tool}" 2>/dev/null | grep -q "^ii"; then
      log_error "Tool not installed: ${tool}"
      validation_passed=false
    fi
  done
  
  # Verify git is configured
  if ! git config --global init.defaultBranch &> /dev/null; then
    log_warning "Git default branch not configured (non-critical)"
  fi
  
  # Verify all tools are executable
  for tool in "${CORE_TOOLS[@]}"; do
    if ! command -v "${tool}" &> /dev/null; then
      log_error "Tool not executable: ${tool}"
      validation_passed=false
    fi
  done
  
  if [[ "${validation_passed}" == "false" ]]; then
    log_error "Development tools validation failed"
    return 1
  fi
  
  log_info "Development tools validation passed"
  return 0
}

# dev_tools_execute
# Main execution function for development tools module
#
# Returns:
#   0 - Installation successful
#   1 - Installation failed
dev_tools_execute() {
  log_info "Starting development tools module"
  progress_start "${DEV_TOOLS_PHASE}" "Development Tools Installation"
  
  # Check if already completed
  if checkpoint_exists "${DEV_TOOLS_PHASE}"; then
    log_info "Development tools already installed (checkpoint exists)"
    progress_complete "${DEV_TOOLS_PHASE}"
    return 0
  fi
  
  # Validate prerequisites
  progress_update "${DEV_TOOLS_PHASE}" 10 "Checking prerequisites"
  if ! dev_tools_check_prerequisites; then
    progress_fail "${DEV_TOOLS_PHASE}" "Prerequisites check failed"
    return 1
  fi
  
  # Update package cache
  progress_update "${DEV_TOOLS_PHASE}" 20 "Updating package cache"
  if ! dev_tools_update_package_cache; then
    progress_fail "${DEV_TOOLS_PHASE}" "Failed to update package cache"
    return 1
  fi
  
  # Install core development tools
  progress_update "${DEV_TOOLS_PHASE}" 40 "Installing core development tools"
  if ! dev_tools_install_core_tools; then
    progress_fail "${DEV_TOOLS_PHASE}" "Failed to install core tools"
    return 1
  fi
  
  # Configure git
  progress_update "${DEV_TOOLS_PHASE}" 70 "Configuring git"
  if ! dev_tools_configure_git; then
    log_warning "Git configuration had warnings, but continuing"
    # Don't fail the entire module for git config warnings
  fi
  
  # Verify all tools
  progress_update "${DEV_TOOLS_PHASE}" 85 "Verifying tools"
  if ! dev_tools_verify_all_tools; then
    progress_fail "${DEV_TOOLS_PHASE}" "Tool verification failed"
    return 1
  fi
  
  # Validate installation
  progress_update "${DEV_TOOLS_PHASE}" 95 "Validating installation"
  if ! dev_tools_validate; then
    progress_fail "${DEV_TOOLS_PHASE}" "Validation failed"
    return 1
  fi
  
  # Create checkpoint
  checkpoint_create "${DEV_TOOLS_PHASE}"
  progress_complete "${DEV_TOOLS_PHASE}"
  log_info "Development tools module completed successfully"
  return 0
}

# Allow sourcing without execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  dev_tools_execute
fi
