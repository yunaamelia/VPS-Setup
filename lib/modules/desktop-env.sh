#!/bin/bash
# Desktop Environment Module
# Installs and configures XFCE 4.18 desktop environment for RDP access
# 
# Usage:
#   source lib/modules/desktop-env.sh
#   desktop_env_execute
#
# Dependencies:
#   - lib/core/logger.sh
#   - lib/core/checkpoint.sh
#   - lib/core/transaction.sh
#   - lib/core/progress.sh

set -euo pipefail

# Prevent multiple sourcing
if [[ -n "${_DESKTOP_ENV_SH_LOADED:-}" ]]; then
  return 0
fi
readonly _DESKTOP_ENV_SH_LOADED=1

# Source dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(dirname "${SCRIPT_DIR}")"
source "${LIB_DIR}/core/logger.sh"
source "${LIB_DIR}/core/checkpoint.sh"
source "${LIB_DIR}/core/transaction.sh"
source "${LIB_DIR}/core/progress.sh"

# Module constants
# Module constants
readonly DESKTOP_ENV_PHASE="${DESKTOP_ENV_PHASE:-desktop-install}"
readonly XFCE_PACKAGES=(
  "task-xfce-desktop"
  "xfce4-goodies"
  "lightdm"
  "dbus-x11"
  "x11-xserver-utils"
)

readonly LIGHTDM_CONF="${LIGHTDM_CONF:-/etc/lightdm/lightdm.conf}"
readonly XFCE_CONFIG_DIR="${XFCE_CONFIG_DIR:-/etc/skel/.config/xfce4}"
readonly DESKTOP_CONFIG_SOURCE="${DESKTOP_CONFIG_SOURCE:-${LIB_DIR}/../config/desktop}"

# desktop_env_check_prerequisites
# Validates system is ready for desktop installation
#
# Returns:
#   0 - Prerequisites met
#   1 - Prerequisites failed
desktop_env_check_prerequisites() {
  log_info "Checking desktop environment prerequisites"
  
  # Verify system-prep phase completed
  if ! checkpoint_exists "system-prep"; then
    log_error "System preparation must complete before desktop installation"
    return 1
  fi
  
  # Check available disk space (need at least 3GB for XFCE)
  local available_space
  available_space=$(df / | awk 'NR==2 {print $4}')
  local required_space=$((3 * 1024 * 1024))  # 3GB in KB
  
  if [[ ${available_space} -lt ${required_space} ]]; then
    log_error "Insufficient disk space for desktop installation"
    log_error "Available: $((available_space / 1024 / 1024))GB, Required: 3GB"
    return 1
  fi
  
  log_info "Prerequisites check passed"
  return 0
}

# desktop_env_install_packages
# Installs XFCE desktop environment and LightDM display manager
#
# Returns:
#   0 - Installation successful
#   1 - Installation failed
desktop_env_install_packages() {
  log_info "Installing XFCE desktop environment packages"
  progress_update "Installing desktop environment" 20
  
  # Set DEBIAN_FRONTEND to avoid interactive prompts
  export DEBIAN_FRONTEND=noninteractive
  
  # Install XFCE packages
  for package in "${XFCE_PACKAGES[@]}"; do
    if dpkg -l | grep -q "^ii  ${package}"; then
      log_info "Package ${package} already installed"
      continue
    fi
    
    log_info "Installing package: ${package}"
    if ! apt-get install -y --no-install-recommends "${package}" 2>&1 | tee -a "${LOG_FILE}"; then
      log_error "Failed to install package: ${package}"
      return 1
    fi
    
    transaction_log "apt-get remove -y ${package}"
  done
  
  # Verify installations
  for package in "${XFCE_PACKAGES[@]}"; do
    if ! dpkg -l | grep -q "^ii  ${package}"; then
      log_error "Package verification failed: ${package}"
      return 1
    fi
  done
  
  log_info "Desktop environment packages installed successfully"
  progress_update "Desktop packages installed" 40
  return 0
}

# desktop_env_configure_lightdm
# Configures LightDM display manager for XFCE session
#
# Returns:
#   0 - Configuration successful
#   1 - Configuration failed
desktop_env_configure_lightdm() {
  log_info "Configuring LightDM display manager"
  progress_update "Configuring display manager" 60
  
  # Backup original config if exists
  if [[ -f "${LIGHTDM_CONF}" ]]; then
    transaction_log "mv /etc/lightdm/lightdm.conf.vps-backup ${LIGHTDM_CONF}"
    cp "${LIGHTDM_CONF}" "${LIGHTDM_CONF}.vps-backup"
  fi
  
  # Create LightDM configuration
  cat > "${LIGHTDM_CONF}" <<'EOF'
[Seat:*]
# XFCE session configuration for RDP access
greeter-session=lightdm-gtk-greeter
user-session=xfce
autologin-guest=false
autologin-user-timeout=0
allow-guest=false

# Performance optimizations
xserver-command=X -core
EOF
  
  transaction_log "rm -f ${LIGHTDM_CONF}"
  
  # Set LightDM as default display manager
  if command -v update-alternatives &> /dev/null; then
    echo "/usr/sbin/lightdm" | tee /etc/X11/default-display-manager > /dev/null
    transaction_log "echo '' > /etc/X11/default-display-manager"
  fi
  
  log_info "LightDM configuration completed"
  return 0
}

# desktop_env_apply_customizations
# Applies XFCE customizations for optimal development experience
#
# Returns:
#   0 - Customizations applied
#   1 - Customizations failed
desktop_env_apply_customizations() {
  log_info "Applying XFCE customizations"
  progress_update "Applying desktop customizations" 70
  
  # Create config directory structure
  mkdir -p "${XFCE_CONFIG_DIR}/xfconf/xfce-perchannel-xml"
  mkdir -p "${XFCE_CONFIG_DIR}/terminal"
  mkdir -p "${XFCE_CONFIG_DIR}/panel"
  
  # Apply panel customization
  if [[ -f "${DESKTOP_CONFIG_SOURCE}/xfce4-panel.xml" ]]; then
    cp "${DESKTOP_CONFIG_SOURCE}/xfce4-panel.xml" \
       "${XFCE_CONFIG_DIR}/xfconf/xfce-perchannel-xml/xfce4-panel.xml"
  else
    log_warning "Panel customization file not found, using defaults"
  fi
  
  # Apply terminal customization
  if [[ -f "${DESKTOP_CONFIG_SOURCE}/terminalrc" ]]; then
    cp "${DESKTOP_CONFIG_SOURCE}/terminalrc" \
       "${XFCE_CONFIG_DIR}/terminal/terminalrc"
  else
    log_warning "Terminal customization file not found, using defaults"
  fi
  
  # Apply theme settings
  if [[ -f "${DESKTOP_CONFIG_SOURCE}/xsettings.xml" ]]; then
    cp "${DESKTOP_CONFIG_SOURCE}/xsettings.xml" \
       "${XFCE_CONFIG_DIR}/xfconf/xfce-perchannel-xml/xsettings.xml"
  else
    log_warning "Theme settings file not found, using defaults"
  fi
  
  # Set permissions
  chmod -R 644 "${XFCE_CONFIG_DIR}"
  find "${XFCE_CONFIG_DIR}" -type d -exec chmod 755 {} \;
  
  log_info "XFCE customizations applied"
  return 0
}

# desktop_env_enable_services
# Enables and starts desktop-related services
#
# Returns:
#   0 - Services enabled
#   1 - Service configuration failed
desktop_env_enable_services() {
  log_info "Enabling desktop services"
  progress_update "Enabling desktop services" 85
  
  # Enable LightDM
  if systemctl list-unit-files | grep -q lightdm.service; then
    systemctl enable lightdm.service 2>&1 | tee -a "${LOG_FILE}"
    transaction_log "systemctl disable lightdm.service"
  fi
  
  # Don't start LightDM now (will interfere with RDP setup)
  # It will start on next boot or when explicitly started
  
  log_info "Desktop services enabled"
  return 0
}

# desktop_env_validate_installation
# Validates desktop environment installation
#
# Returns:
#   0 - Validation successful
#   1 - Validation failed
desktop_env_validate_installation() {
  log_info "Validating desktop environment installation"
  progress_update "Validating installation" 95
  
  # Check XFCE installation
  if ! command -v startxfce4 &> /dev/null; then
    log_error "XFCE not properly installed (startxfce4 missing)"
    return 1
  fi
  
  # Check LightDM installation
  if ! command -v lightdm &> /dev/null; then
    log_error "LightDM not properly installed"
    return 1
  fi
  
  # Verify critical files exist
  local -a critical_files=(
    "/usr/bin/xfce4-session"
    "/usr/bin/xfce4-panel"
    "/usr/bin/xfce4-terminal"
    "/usr/sbin/lightdm"
  )
  
  for file in "${critical_files[@]}"; do
    if [[ ! -f "${file}" ]]; then
      log_error "Critical file missing: ${file}"
      return 1
    fi
  done
  
  # Check desktop session file
  if [[ ! -f "/usr/share/xsessions/xfce.desktop" ]]; then
    log_error "XFCE desktop session file missing"
    return 1
  fi
  
  log_info "Desktop environment validation passed"
  return 0
}

# desktop_env_execute
# Main execution function for desktop environment setup
#
# Returns:
#   0 - Desktop environment setup successful
#   1 - Setup failed
desktop_env_execute() {
  log_info "Starting desktop environment installation"
  progress_start "Desktop Environment Setup"
  
  # Check if already completed
  if checkpoint_exists "${DESKTOP_ENV_PHASE}"; then
    log_info "Desktop environment already installed (checkpoint exists)"
    progress_complete "Desktop environment (cached)"
    return 0
  fi
  
  # Execute installation steps
  desktop_env_check_prerequisites || return 1
  desktop_env_install_packages || return 1
  desktop_env_configure_lightdm || return 1
  desktop_env_apply_customizations || return 1
  desktop_env_enable_services || return 1
  desktop_env_validate_installation || return 1
  
  # Create checkpoint
  checkpoint_create "${DESKTOP_ENV_PHASE}" || {
    log_error "Failed to create checkpoint"
    return 1
  }
  
  progress_complete "Desktop environment installed"
  log_info "Desktop environment installation completed successfully"
  return 0
}

# Export functions
export -f desktop_env_check_prerequisites
export -f desktop_env_install_packages
export -f desktop_env_configure_lightdm
export -f desktop_env_apply_customizations
export -f desktop_env_enable_services
export -f desktop_env_validate_installation
export -f desktop_env_execute
