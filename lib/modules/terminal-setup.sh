#!/bin/bash
# Terminal Enhancement Module
# Installs bash-completion, configures git aliases, and sets up colored prompt
# with git branch display for improved developer experience
#
# Usage:
#   source lib/modules/terminal-setup.sh
#   terminal_setup_execute
#
# Dependencies:
#   - lib/core/logger.sh
#   - lib/core/checkpoint.sh
#   - lib/core/transaction.sh
#   - lib/core/progress.sh

set -euo pipefail

# Prevent multiple sourcing
if [[ -n "${_TERMINAL_SETUP_SH_LOADED:-}" ]]; then
  return 0
fi
readonly _TERMINAL_SETUP_SH_LOADED=1

# Source dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(dirname "${SCRIPT_DIR}")"
# shellcheck disable=SC1091
source "${LIB_DIR}/core/logger.sh"
# shellcheck disable=SC1091
source "${LIB_DIR}/core/checkpoint.sh"
# shellcheck disable=SC1091
source "${LIB_DIR}/core/transaction.sh"
# shellcheck disable=SC1091
source "${LIB_DIR}/core/progress.sh"

# Module constants
readonly TERMINAL_SETUP_PHASE="${TERMINAL_SETUP_PHASE:-terminal-setup}"
readonly BASHRC_BACKUP_DIR="${BASHRC_BACKUP_DIR:-/var/vps-provision/backups/bashrc}"

# Git aliases to configure
declare -A GIT_ALIASES=(
  ["st"]="status"
  ["ci"]="commit"
  ["co"]="checkout"
  ["br"]="branch"
  ["lg"]="log --graph --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset' --abbrev-commit"
)

# terminal_setup_check_prerequisites
# Validates system is ready for terminal setup
#
# Returns:
#   0 - Prerequisites met
#   1 - Prerequisites failed
terminal_setup_check_prerequisites() {
  log_info "Checking terminal setup prerequisites"

  # Verify system-prep phase completed
  if ! checkpoint_exists "system-prep"; then
    log_error "System preparation must be completed before terminal setup"
    return 1
  fi

  # Verify user-creation phase completed
  if ! checkpoint_exists "user-creation"; then
    log_error "User provisioning must be completed before terminal setup"
    return 1
  fi

  # Verify git is installed
  if ! command -v git &>/dev/null; then
    log_error "Git not found (required for terminal setup)"
    return 1
  fi

  log_info "Prerequisites check passed"
  return 0
}

# terminal_setup_install_bash_completion
# Installs bash-completion package for command autocompletion
#
# Returns:
#   0 - Installation successful
#   1 - Installation failed
terminal_setup_install_bash_completion() {
  log_info "Installing bash-completion package"

  # Check if already installed
  if dpkg -l bash-completion 2>/dev/null | grep -q "^ii"; then
    log_info "bash-completion already installed"
    return 0
  fi

  # Install package
  if ! apt-get update -qq || ! apt-get install -y bash-completion 2>&1 | tee -a "${LOG_FILE}"; then
    log_error "Failed to install bash-completion"
    return 1
  fi

  transaction_log "apt-get remove -y bash-completion"
  log_info "bash-completion installed successfully"
  return 0
}

# terminal_setup_configure_git_aliases
# Configures git aliases in global gitconfig
#
# Returns:
#   0 - Configuration successful
#   1 - Configuration failed
terminal_setup_configure_git_aliases() {
  log_info "Configuring git aliases"

  for alias_name in "${!GIT_ALIASES[@]}"; do
    local alias_command="${GIT_ALIASES[$alias_name]}"

    # Check if alias already exists
    if git config --global "alias.${alias_name}" &>/dev/null; then
      log_debug "Git alias already exists: ${alias_name}"
      continue
    fi

    # Set global alias
    if ! git config --global "alias.${alias_name}" "${alias_command}" 2>&1 | tee -a "${LOG_FILE}"; then
      log_error "Failed to set git alias: ${alias_name}"
      return 1
    fi

    transaction_log "git config --global --unset alias.${alias_name}"
    log_debug "Git alias configured: ${alias_name} = ${alias_command}"
  done

  log_info "Git aliases configured successfully"
  return 0
}

# terminal_setup_create_ps1_function
# Creates bash function for colored prompt with git branch display
#
# Returns:
#   String containing PS1 function definition
terminal_setup_create_ps1_function() {
  cat <<'EOF'
# VPS Provision - Enhanced PS1 with Git Branch Display
__vps_git_branch() {
  local branch
  if branch=$(git symbolic-ref --short HEAD 2>/dev/null); then
    echo " (${branch})"
  fi
}

__vps_ps1() {
  local reset='\[\033[0m\]'
  local bold='\[\033[1m\]'
  local red='\[\033[0;31m\]'
  local green='\[\033[0;32m\]'
  local yellow='\[\033[0;33m\]'
  local blue='\[\033[0;34m\]'
  local cyan='\[\033[0;36m\]'
  
  local user_color="${green}"
  if [[ "${EUID}" -eq 0 ]]; then
    user_color="${red}"
  fi
  
  PS1="${user_color}${bold}\u${reset}@${cyan}\h${reset}:${blue}\w${reset}"
  PS1+="${yellow}\$(__vps_git_branch)${reset}"
  PS1+="${user_color}${bold}\$${reset} "
}

# Set prompt command
PROMPT_COMMAND=__vps_ps1
EOF
}

# terminal_setup_backup_bashrc
# Creates backup of existing bashrc files
#
# Args:
#   $1 - File to backup
#
# Returns:
#   0 - Backup successful
#   1 - Backup failed
terminal_setup_backup_bashrc() {
  local file_to_backup="$1"

  if [[ ! -f "${file_to_backup}" ]]; then
    log_debug "File does not exist, no backup needed: ${file_to_backup}"
    return 0
  fi

  # Create backup directory
  mkdir -p "${BASHRC_BACKUP_DIR}"

  # Create timestamped backup
  local timestamp
  timestamp=$(date +%Y%m%d_%H%M%S)
  local backup_name
  backup_name=$(basename "${file_to_backup}")
  local backup_file="${BASHRC_BACKUP_DIR}/${backup_name}.${timestamp}"

  if ! cp -a "${file_to_backup}" "${backup_file}" 2>&1 | tee -a "${LOG_FILE}"; then
    log_error "Failed to backup: ${file_to_backup}"
    return 1
  fi

  log_debug "Backup created: ${backup_file}"
  return 0
}

# terminal_setup_apply_to_skel
# Applies terminal configuration to /etc/skel/.bashrc
#
# Returns:
#   0 - Configuration applied
#   1 - Configuration failed
terminal_setup_apply_to_skel() {
  local skel_bashrc="${SKEL_BASHRC:-/etc/skel/.bashrc}"

  log_info "Applying terminal configuration to /etc/skel"

  # Backup existing file
  if ! terminal_setup_backup_bashrc "${skel_bashrc}"; then
    return 1
  fi

  # Check if configuration already applied
  if [[ -f "${skel_bashrc}" ]] && grep -q "__vps_git_branch" "${skel_bashrc}"; then
    log_info "Terminal configuration already present in ${skel_bashrc}"
    return 0
  fi

  # Append configuration
  {
    echo ""
    echo "# ===================================================================="
    echo "# VPS Provision - Terminal Enhancements"
    echo "# Added: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "# ===================================================================="
    echo ""
    terminal_setup_create_ps1_function
    echo ""
    echo "# Enable bash-completion if available"
    echo "if [[ -f /usr/share/bash-completion/bash_completion ]]; then"
    echo "  . /usr/share/bash-completion/bash_completion"
    echo "fi"
    echo ""
  } >>"${skel_bashrc}"

  # shellcheck disable=SC2181,SC2320
  if [[ $? -ne 0 ]]; then
    log_error "Failed to update ${skel_bashrc}"
    return 1
  fi

  transaction_log "restore_file_from_backup ${skel_bashrc}"
  log_info "Terminal configuration applied to ${skel_bashrc}"
  return 0
}

# terminal_setup_apply_to_user
# Applies terminal configuration to existing user's bashrc
#
# Args:
#   $1 - Username
#
# Returns:
#   0 - Configuration applied
#   1 - Configuration failed
terminal_setup_apply_to_user() {
  local username="$1"
  local user_home

  # Get user home directory
  user_home=$(getent passwd "${username}" | cut -d: -f6)

  if [[ -z "${user_home}" ]] || [[ ! -d "${user_home}" ]]; then
    log_error "Home directory not found for user: ${username}"
    return 1
  fi

  local user_bashrc="${user_home}/.bashrc"

  log_info "Applying terminal configuration to ${username}'s .bashrc"

  # Backup existing file
  if ! terminal_setup_backup_bashrc "${user_bashrc}"; then
    return 1
  fi

  # Check if configuration already applied
  if [[ -f "${user_bashrc}" ]] && grep -q "__vps_git_branch" "${user_bashrc}"; then
    log_info "Terminal configuration already present in ${user_bashrc}"
    return 0
  fi

  # Append configuration
  {
    echo ""
    echo "# ===================================================================="
    echo "# VPS Provision - Terminal Enhancements"
    echo "# Added: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "# ===================================================================="
    echo ""
    terminal_setup_create_ps1_function
    echo ""
    echo "# Enable bash-completion if available"
    echo "if [[ -f /usr/share/bash-completion/bash_completion ]]; then"
    echo "  . /usr/share/bash-completion/bash_completion"
    echo "fi"
    echo ""
  } >>"${user_bashrc}"

  # shellcheck disable=SC2181,SC2320
  if [[ $? -ne 0 ]]; then
    log_error "Failed to update ${user_bashrc}"
    return 1
  fi

  # Set correct ownership
  if ! chown "${username}:${username}" "${user_bashrc}" 2>/dev/null; then
    log_info "Note: Could not set ownership for ${user_bashrc} (expected in some container environments)"
  fi

  transaction_log "restore_file_from_backup ${user_bashrc}"
  log_info "Terminal configuration applied to ${user_bashrc}"
  return 0
}

# terminal_setup_apply_to_existing_users
# Applies terminal configuration to all existing non-system users
#
# Returns:
#   0 - Configuration applied to all users
#   1 - Configuration failed for one or more users
terminal_setup_apply_to_existing_users() {
  log_info "Applying terminal configuration to existing users"

  local failed=0

  # Get list of non-system users (UID >= 1000)
  while IFS=: read -r username _ uid _ _ _ shell; do
    if [[ "${uid}" -ge 1000 ]] && [[ "${shell}" == */bash ]]; then
      log_debug "Applying configuration to user: ${username}"

      if ! terminal_setup_apply_to_user "${username}"; then
        log_warning "Failed to apply configuration to user: ${username}"
        ((failed++))
      fi
    fi
  done </etc/passwd

  if [[ "${failed}" -gt 0 ]]; then
    log_warning "Configuration failed for ${failed} user(s)"
    return 1
  fi

  log_info "Terminal configuration applied to all existing users"
  return 0
}

# terminal_setup_validate
# Validates terminal setup configuration
#
# Returns:
#   0 - Validation successful
#   1 - Validation failed
terminal_setup_validate() {
  log_info "Validating terminal setup"

  local validation_passed=true

  # Verify bash-completion installed
  if ! dpkg -l bash-completion 2>/dev/null | grep -q "^ii"; then
    log_warning "bash-completion not installed (will be installed in dev-tools phase)"
    # Don't fail validation - this is non-critical
  fi

  # Verify git aliases configured
  for alias_name in "${!GIT_ALIASES[@]}"; do
    if ! git config --global "alias.${alias_name}" &>/dev/null; then
      log_error "Git alias not configured: ${alias_name}"
      validation_passed=false
    fi
  done

  # Verify /etc/skel/.bashrc has configuration
  local skel_bashrc="${SKEL_BASHRC:-/etc/skel/.bashrc}"
  if [[ ! -f "${skel_bashrc}" ]] || ! grep -q "__vps_git_branch" "${skel_bashrc}"; then
    log_error "Terminal configuration not found in ${skel_bashrc}"
    validation_passed=false
  fi

  if [[ "${validation_passed}" == "false" ]]; then
    log_error "Terminal setup validation failed"
    return 1
  fi

  log_info "Terminal setup validation passed"
  return 0
}

# terminal_setup_execute
# Main execution function for terminal setup module
#
# Returns:
#   0 - Setup successful
#   1 - Setup failed
terminal_setup_execute() {
  log_info "Starting terminal setup module"
  progress_start_phase "${TERMINAL_SETUP_PHASE}"

  # Check if already completed
  if checkpoint_exists "${TERMINAL_SETUP_PHASE}"; then
    log_info "Terminal setup already completed (checkpoint found)"
    progress_complete_phase
    return 0
  fi

  # Validate prerequisites
  progress_update "${TERMINAL_SETUP_PHASE}" 10 "Checking prerequisites"
  if ! terminal_setup_check_prerequisites; then
    progress_fail "${TERMINAL_SETUP_PHASE}" "Prerequisites check failed"
    return 1
  fi

  # Install bash-completion
  progress_update "${TERMINAL_SETUP_PHASE}" 25 "Installing bash-completion"
  if ! terminal_setup_install_bash_completion; then
    progress_fail "${TERMINAL_SETUP_PHASE}" "Failed to install bash-completion"
    return 1
  fi

  # Configure git aliases
  progress_update "${TERMINAL_SETUP_PHASE}" 40 "Configuring git aliases"
  if ! terminal_setup_configure_git_aliases; then
    progress_fail "${TERMINAL_SETUP_PHASE}" "Failed to configure git aliases"
    return 1
  fi

  # Apply to /etc/skel
  progress_update "${TERMINAL_SETUP_PHASE}" 60 "Applying configuration to /etc/skel"
  if ! terminal_setup_apply_to_skel; then
    progress_fail "${TERMINAL_SETUP_PHASE}" "Failed to apply configuration to /etc/skel"
    return 1
  fi

  # Apply to existing users
  progress_update "${TERMINAL_SETUP_PHASE}" 80 "Applying configuration to existing users"
  if ! terminal_setup_apply_to_existing_users; then
    log_warning "Some users may not have received terminal configuration"
    # Don't fail the entire module for this
  fi

  # Validate setup
  progress_update "${TERMINAL_SETUP_PHASE}" 95 "Validating configuration"
  if ! terminal_setup_validate; then
    log_warning "Terminal setup validation failed (non-critical)"
    # Don't fail - validation issues are non-critical
  fi

  # Create checkpoint
  checkpoint_create "${TERMINAL_SETUP_PHASE}"
  progress_complete_phase
  log_info "Terminal setup module completed successfully"
  return 0
}

# Allow sourcing without execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  terminal_setup_execute
fi
