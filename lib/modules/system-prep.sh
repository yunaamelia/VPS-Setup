#!/bin/bash
# System Preparation Module
# Prepares Debian 13 system for provisioning: updates packages, installs core dependencies,
# configures unattended upgrades, and establishes baseline system state
#
# Usage:
#   source lib/modules/system-prep.sh
#   system_prep_execute
#
# Dependencies:
#   - lib/core/logger.sh
#   - lib/core/checkpoint.sh
#   - lib/core/transaction.sh
#   - lib/core/progress.sh

set -euo pipefail

# Prevent multiple sourcing
if [[ -n "${_SYSTEM_PREP_SH_LOADED:-}" ]]; then
  return 0
fi
readonly _SYSTEM_PREP_SH_LOADED=1

# Source dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(dirname "${SCRIPT_DIR}")"
source "${LIB_DIR}/core/logger.sh"
source "${LIB_DIR}/core/checkpoint.sh"
source "${LIB_DIR}/core/transaction.sh"
source "${LIB_DIR}/core/progress.sh"

# Module constants
# Module constants
readonly SYSTEM_PREP_PHASE="${SYSTEM_PREP_PHASE:-system-prep}"
readonly APT_CONF_DIR="${APT_CONF_DIR:-/etc/apt/apt.conf.d}"
readonly APT_CUSTOM_CONF="${APT_CUSTOM_CONF:-${APT_CONF_DIR}/99vps-provision}"
readonly UNATTENDED_UPGRADES_CONF="${UNATTENDED_UPGRADES_CONF:-${APT_CONF_DIR}/50unattended-upgrades}"

# Core packages required for provisioning
readonly -a CORE_PACKAGES=(
  "build-essential"
  "curl"
  "wget"
  "git"
  "ca-certificates"
  "gnupg"
  "lsb-release"
  "apt-transport-https"
  "software-properties-common"
  "unattended-upgrades"
  "apt-listchanges"
)

# Configure APT for provisioning
system_prep_configure_apt() {
  log_info "Configuring APT for provisioning..."
  
  # Create custom APT configuration
  cat > "${APT_CUSTOM_CONF}" <<'EOF'
# VPS Provisioning APT Configuration
# Optimized for automated provisioning with error recovery

# Install recommended packages but skip suggestions
APT::Install-Recommends "true";
APT::Install-Suggests "false";

# Automatic yes to prompts
APT::Get::Assume-Yes "true";

# Fix broken dependencies automatically
APT::Get::Fix-Broken "true";

# Retry failed downloads
Acquire::Retries "3";
Acquire::http::Timeout "300";
Acquire::https::Timeout "300";

# Quiet mode for cleaner logs
Dpkg::Options {
  "--force-confdef";
  "--force-confold";
}

# Progress indicator
Dpkg::Progress-Fancy "1";
EOF

  transaction_log "create_file" "${APT_CUSTOM_CONF}" "rm -f '${APT_CUSTOM_CONF}'"
  log_info "APT configuration created at ${APT_CUSTOM_CONF}"
}

# Update APT package lists
system_prep_update_apt() {
  log_info "Updating APT package lists..."
  
  local max_retries=3
  local retry_delay=5
  
  for attempt in $(seq 1 ${max_retries}); do
    if apt-get update 2>&1 | tee -a "${LOG_FILE:-/dev/null}"; then
      log_info "APT package lists updated successfully"
      transaction_log "apt_update" "package lists" "# No rollback for apt update"
      return 0
    fi
    
    if [[ ${attempt} -lt ${max_retries} ]]; then
      log_warning "APT update failed (attempt ${attempt}/${max_retries}), retrying in ${retry_delay}s..."
      sleep ${retry_delay}
    fi
  done
  
  log_error "Failed to update APT package lists after ${max_retries} attempts"
  return 1
}

# Upgrade existing packages
system_prep_upgrade_packages() {
  log_info "Upgrading existing packages..."
  
  # Use upgrade, not dist-upgrade to avoid potential conflicts
  if apt-get upgrade -y 2>&1 | tee -a "${LOG_FILE:-/dev/null}"; then
    log_info "Existing packages upgraded successfully"
    transaction_log "apt_upgrade" "system packages" "# Packages upgraded - rollback via system snapshot"
    return 0
  else
    log_error "Failed to upgrade packages"
    return 1
  fi
}

# Install core dependencies
system_prep_install_core_packages() {
  log_info "Installing core dependencies..."
  
  local failed_packages=()
  
  for package in "${CORE_PACKAGES[@]}"; do
    log_info "Installing ${package}..."
    
    # Check if already installed
    if dpkg -s "${package}" 2>/dev/null | grep -q "Status: install ok installed"; then
      log_info "${package} is already installed"
      continue
    fi
    
    # Install package with retry logic
    if apt-get install -y "${package}" 2>&1 | tee -a "${LOG_FILE:-/dev/null}"; then
      log_info "${package} installed successfully"
      transaction_log "apt_install" "${package}" "apt-get remove -y '${package}' 2>/dev/null || true"
    else
      log_error "Failed to install ${package}"
      failed_packages+=("${package}")
    fi
  done
  
  # Report failures
  if [[ ${#failed_packages[@]} -gt 0 ]]; then
    log_error "Failed to install packages: ${failed_packages[*]}"
    return 1
  fi
  
  log_info "All core packages installed successfully"
  return 0
}

# Verify package installation
system_prep_verify_package() {
  local package=$1
  
  if dpkg -s "${package}" 2>/dev/null | grep -q "Status: install ok installed"; then
    return 0
  else
    return 1
  fi
}

# Configure unattended upgrades
system_prep_configure_unattended_upgrades() {
  log_info "Configuring unattended upgrades..."
  
  # Backup original configuration if it exists
  if [[ -f "${UNATTENDED_UPGRADES_CONF}" ]]; then
    cp "${UNATTENDED_UPGRADES_CONF}" "${UNATTENDED_UPGRADES_CONF}.backup"
    transaction_log "backup_file" "${UNATTENDED_UPGRADES_CONF}" \
      "mv '${UNATTENDED_UPGRADES_CONF}.backup' '${UNATTENDED_UPGRADES_CONF}'"
  fi
  
  # Create unattended upgrades configuration
  cat > "${UNATTENDED_UPGRADES_CONF}" <<'EOF'
// VPS Provisioning: Unattended Upgrades Configuration
// Automatically install security updates

Unattended-Upgrade::Allowed-Origins {
  "${distro_id}:${distro_codename}";
  "${distro_id}:${distro_codename}-security";
  "${distro_id}:${distro_codename}-updates";
};

// Automatically reboot if required (at 3 AM)
Unattended-Upgrade::Automatic-Reboot "false";
Unattended-Upgrade::Automatic-Reboot-Time "03:00";

// Remove unused dependencies
Unattended-Upgrade::Remove-Unused-Dependencies "true";

// Fix interrupted dpkg on upgrade
Unattended-Upgrade::AutoFixInterruptedDpkg "true";

// Email notifications (disabled by default)
// Unattended-Upgrade::Mail "root";
Unattended-Upgrade::MailReport "only-on-error";

// Verbose logging
Unattended-Upgrade::Verbose "true";
EOF

  transaction_log "create_file" "${UNATTENDED_UPGRADES_CONF}" \
    "rm -f '${UNATTENDED_UPGRADES_CONF}'"
  
  # Enable unattended upgrades
  if dpkg-reconfigure -plow unattended-upgrades 2>&1 | tee -a "${LOG_FILE:-/dev/null}"; then
    log_info "Unattended upgrades configured successfully"
  else
    log_warning "Failed to reconfigure unattended-upgrades (may not be critical)"
  fi
}

# Fix broken packages (if any)
system_prep_fix_broken_packages() {
  log_info "Checking for broken packages..."
  
  # Try to fix broken packages
  if dpkg --configure -a 2>&1 | tee -a "${LOG_FILE:-/dev/null}"; then
    log_info "dpkg configuration completed"
  else
    log_warning "dpkg --configure -a reported issues"
  fi
  
  if apt-get install -f -y 2>&1 | tee -a "${LOG_FILE:-/dev/null}"; then
    log_info "Dependency issues resolved"
  else
    log_warning "apt-get install -f reported issues"
  fi
}

# Clean APT cache
system_prep_clean_apt_cache() {
  log_info "Cleaning APT cache..."
  
  # Keep package lists but remove cached .deb files
  if apt-get clean 2>&1 | tee -a "${LOG_FILE:-/dev/null}"; then
    log_info "APT cache cleaned (freed disk space)"
  else
    log_warning "Failed to clean APT cache"
  fi
}

# Verify system preparation
system_prep_verify() {
  log_info "Verifying system preparation..."
  
  local verification_failed=false
  
  # Verify all core packages installed
  for package in "${CORE_PACKAGES[@]}"; do
    if ! system_prep_verify_package "${package}"; then
      log_error "Verification failed: ${package} not installed"
      verification_failed=true
    fi
  done
  
  # Verify APT configuration exists
  if [[ ! -f "${APT_CUSTOM_CONF}" ]]; then
    log_error "Verification failed: APT configuration missing"
    verification_failed=true
  fi
  
  # Verify unattended upgrades configuration
  if [[ ! -f "${UNATTENDED_UPGRADES_CONF}" ]]; then
    log_error "Verification failed: Unattended upgrades configuration missing"
    verification_failed=true
  fi
  
  # Verify critical commands available
  local -a critical_commands=("git" "curl" "wget" "gcc" "make")
  for cmd in "${critical_commands[@]}"; do
    if ! command -v "${cmd}" &>/dev/null; then
      log_error "Verification failed: Command not found: ${cmd}"
      verification_failed=true
    fi
  done
  
  if [[ "${verification_failed}" == "true" ]]; then
    log_error "System preparation verification failed"
    return 1
  fi
  
  log_info "System preparation verification passed"
  return 0
}

# Main execution function
system_prep_execute() {
  log_info "Starting system preparation phase..."
  
  # Check if already completed
  if checkpoint_exists "${SYSTEM_PREP_PHASE}"; then
    log_info "System preparation already completed (checkpoint exists)"
    return 0
  fi
  
  # Start checkpoint
  checkpoint_start "${SYSTEM_PREP_PHASE}"
  
  # Configure APT
  if ! system_prep_configure_apt; then
    log_error "Failed to configure APT"
    return 1
  fi
  
  # Update package lists
  if ! system_prep_update_apt; then
    log_error "Failed to update APT package lists"
    return 1
  fi
  
  # Upgrade existing packages
  if ! system_prep_upgrade_packages; then
    log_error "Failed to upgrade packages"
    return 1
  fi
  
  # Fix any broken packages before installing new ones
  system_prep_fix_broken_packages
  
  # Install core dependencies
  if ! system_prep_install_core_packages; then
    log_error "Failed to install core packages"
    return 1
  fi
  
  # Configure unattended upgrades
  if ! system_prep_configure_unattended_upgrades; then
    log_error "Failed to configure unattended upgrades"
    return 1
  fi
  
  # Clean APT cache
  system_prep_clean_apt_cache
  
  # Verify installation
  if ! system_prep_verify; then
    log_error "System preparation verification failed"
    return 1
  fi
  
  # Complete checkpoint
  checkpoint_complete "${SYSTEM_PREP_PHASE}"
  
  log_info "System preparation phase completed successfully"
  return 0
}

# Export functions
export -f system_prep_execute
export -f system_prep_verify_package
export -f system_prep_verify
