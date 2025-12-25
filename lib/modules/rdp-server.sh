#!/bin/bash
# RDP Server Module
# Installs and configures xrdp server for remote desktop access
# Includes TLS certificate generation, multi-session support, and firewall configuration
#
# Usage:
#   source lib/modules/rdp-server.sh
#   rdp_server_execute
#
# Dependencies:
#   - lib/core/logger.sh
#   - lib/core/checkpoint.sh
#   - lib/core/transaction.sh
#   - lib/core/progress.sh

set -euo pipefail

# Prevent multiple sourcing
if [[ -n "${_RDP_SERVER_SH_LOADED:-}" ]]; then
  return 0
fi
readonly _RDP_SERVER_SH_LOADED=1

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
# Module constants
readonly RDP_SERVER_PHASE="${RDP_SERVER_PHASE:-rdp-config}"
readonly XRDP_CONF_DIR="${XRDP_CONF_DIR:-/etc/xrdp}"
readonly XRDP_INI="${XRDP_INI:-${XRDP_CONF_DIR}/xrdp.ini}"
readonly SESMAN_INI="${SESMAN_INI:-${XRDP_CONF_DIR}/sesman.ini}"
readonly CERT_FILE="${CERT_FILE:-${XRDP_CONF_DIR}/cert.pem}"
readonly KEY_FILE="${KEY_FILE:-${XRDP_CONF_DIR}/key.pem}"
: "${RDP_PORT:=3389}"  # Set default if not already set
: "${SSH_PORT:=22}"  # Set default if not already set

# rdp_server_check_prerequisites
# Validates system is ready for RDP server installation
#
# Returns:
#   0 - Prerequisites met
#   1 - Prerequisites failed
rdp_server_check_prerequisites() {
  log_info "Checking RDP server prerequisites"

  # Verify desktop-install phase completed
  if ! checkpoint_exists "desktop-install"; then
    log_error "Desktop environment must be installed before RDP server"
    return 1
  fi

  # Verify XFCE is installed
  if ! command -v startxfce4 &>/dev/null; then
    log_error "XFCE desktop environment not found"
    return 1
  fi

  # Check OpenSSL is available for certificate generation
  if ! command -v openssl &>/dev/null; then
    log_error "OpenSSL not found (required for TLS certificates)"
    return 1
  fi

  log_info "Prerequisites check passed"
  return 0
}

# rdp_server_install_packages
# Installs xrdp and dependencies
#
# Returns:
#   0 - Installation successful
#   1 - Installation failed
rdp_server_install_packages() {
  log_info "Installing xrdp packages"
  progress_update "Installing RDP server" 15

  export DEBIAN_FRONTEND=noninteractive

  local -a rdp_packages=(
    "xrdp"
    "xorgxrdp"
  )

  for package in "${rdp_packages[@]}"; do
    if dpkg -l | grep -q "^ii  ${package}"; then
      log_info "Package ${package} already installed"
      continue
    fi

    log_info "Installing package: ${package}"
    if ! apt-get install -y "${package}" 2>&1 | tee -a "${LOG_FILE}"; then
      log_error "Failed to install package: ${package}"
      return 1
    fi

    transaction_log "apt-get remove -y ${package}"
  done

  # Verify installations
  for package in "${rdp_packages[@]}"; do
    if ! dpkg -l | grep -q "^ii  ${package}"; then
      log_error "Package verification failed: ${package}"
      return 1
    fi
  done

  log_info "xrdp packages installed successfully"
  progress_update "RDP packages installed" 30
  return 0
}

# rdp_server_generate_certificates
# Generates self-signed TLS certificates for xrdp
#
# Returns:
#   0 - Certificate generation successful
#   1 - Certificate generation failed
rdp_server_generate_certificates() {
  log_info "Generating TLS certificates for xrdp"
  progress_update "Generating TLS certificates" 40

  # Check if certificates already exist
  if [[ -f "${CERT_FILE}" && -f "${KEY_FILE}" ]]; then
    log_info "TLS certificates already exist"

    # Verify certificate validity (at least 30 days remaining)
    local expiry_date
    expiry_date=$(openssl x509 -in "${CERT_FILE}" -noout -enddate | cut -d= -f2)
    local expiry_epoch
    expiry_epoch=$(date -d "${expiry_date}" +%s 2>/dev/null || echo 0)
    local now_epoch
    now_epoch=$(date +%s)
    local days_remaining=$(((expiry_epoch - now_epoch) / 86400))

    if [[ ${days_remaining} -gt 30 ]]; then
      log_info "Existing certificates valid for ${days_remaining} days"
      return 0
    else
      log_warning "Certificates expiring soon (${days_remaining} days), regenerating"
    fi
  fi

  # Backup existing certificates if present
  if [[ -f "${CERT_FILE}" ]]; then
    transaction_log "mv ${CERT_FILE}.vps-backup ${CERT_FILE}"
    mv "${CERT_FILE}" "${CERT_FILE}.vps-backup"
  fi
  if [[ -f "${KEY_FILE}" ]]; then
    transaction_log "mv ${KEY_FILE}.vps-backup ${KEY_FILE}"
    mv "${KEY_FILE}" "${KEY_FILE}.vps-backup"
  fi

  # Generate new self-signed certificate (valid for 10 years)
  # SEC-007: Use 4096-bit RSA for strong encryption
  local hostname
  hostname=$(hostname -f 2>/dev/null || hostname)

  log_info "Generating 4096-bit RSA self-signed certificate (SEC-007)"
  if ! openssl req -x509 -newkey rsa:4096 \
    -keyout "${KEY_FILE}" \
    -out "${CERT_FILE}" \
    -days 3650 -nodes \
    -subj "/C=US/ST=State/L=City/O=VPS-Provision/CN=${hostname}" \
    2>&1 | tee -a "${LOG_FILE}"; then
    log_error "Failed to generate TLS certificates"
    return 1
  fi

  # Set proper permissions (must be done AFTER openssl creates the files)
  chmod 600 "${KEY_FILE}"
  chmod 644 "${CERT_FILE}"
  
  # Set ownership (chown doesn't change permissions in this case)
  chown xrdp:xrdp "${KEY_FILE}" "${CERT_FILE}"
  
  # Verify permissions were set correctly
  local key_perms
  key_perms=$(stat -c "%a" "${KEY_FILE}")
  if [[ "${key_perms}" != "600" ]]; then
    log_warning "Key permissions were ${key_perms}, fixing to 600"
    chmod 600 "${KEY_FILE}"
  fi

  transaction_log "rm -f ${CERT_FILE} ${KEY_FILE}"

  log_info "TLS certificates generated successfully"
  return 0
}

# rdp_server_configure_xrdp
# Configures xrdp.ini for optimal performance and security
#
# Returns:
#   0 - Configuration successful
#   1 - Configuration failed
rdp_server_configure_xrdp() {
  log_info "Configuring xrdp server"
  progress_update "Configuring xrdp" 50

  # Backup original configuration
  if [[ -f "${XRDP_INI}" && ! -f "${XRDP_INI}.vps-backup" ]]; then
    transaction_log "mv ${XRDP_INI}.vps-backup ${XRDP_INI}"
    cp "${XRDP_INI}" "${XRDP_INI}.vps-backup"
  fi

  # Create optimized xrdp configuration
  cat >"${XRDP_INI}" <<EOF
; VPS-PROVISION CONFIGURED xrdp.ini
[Globals]
ini_version=1
fork=true
port=${RDP_PORT}
tcp_nodelay=true
tcp_keepalive=true
security_layer=negotiate
crypt_level=high
certificate=${CERT_FILE}
key_file=${KEY_FILE}
ssl_protocols=TLSv1.2, TLSv1.3
max_bpp=32
new_cursors=true
use_fastpath=both
autorun=

[Logging]
LogFile=/var/log/xrdp.log
LogLevel=INFO
EnableSyslog=true
SyslogLevel=INFO

[Channels]
rdpdr=true
rdpsnd=true
drdynvc=true
cliprdr=true
rail=true
xrdpvr=true

[Xorg]
name=Xorg
lib=libxup.so
username=ask
password=ask
ip=127.0.0.1
port=-1
chansrvport=DISPLAY(10)
EOF

  transaction_log "mv ${XRDP_INI}.vps-backup ${XRDP_INI}"

  log_info "xrdp configuration completed"
  return 0
}

# rdp_server_configure_sesman
# Configures sesman.ini for multi-session support
#
# Returns:
#   0 - Configuration successful
#   1 - Configuration failed
rdp_server_configure_sesman() {
  log_info "Configuring xrdp session manager"
  progress_update "Configuring session manager" 60

  # Backup original configuration
  if [[ -f "${SESMAN_INI}" && ! -f "${SESMAN_INI}.vps-backup" ]]; then
    transaction_log "mv ${SESMAN_INI}.vps-backup ${SESMAN_INI}"
    cp "${SESMAN_INI}" "${SESMAN_INI}.vps-backup"
  fi

  # Create session manager configuration
  cat >"${SESMAN_INI}" <<EOF
; VPS-PROVISION CONFIGURED sesman.ini
[Globals]
ListenAddress=127.0.0.1
ListenPort=3350
EnableUserWindowManager=1
UserWindowManager=startxfce4
DefaultWindowManager=startxfce4

[Security]
AllowRootLogin=false
MaxLoginRetry=3
AlwaysGroupCheck=false

[Sessions]
X11DisplayOffset=10
MaxSessions=50
KillDisconnected=false
; SEC-016: Session timeout - 60 minutes (3600 seconds) idle timeout
IdleTimeLimit=3600
DisconnectedTimeLimit=0
Policy=Default

[Logging]
LogFile=/var/log/xrdp-sesman.log
LogLevel=INFO
EnableSyslog=1
SyslogLevel=INFO

[X11rdp]
param=-bs
param=-nolisten
param=tcp
param=-uds

[Xorg]
param=-bs
param=-nolisten
param=tcp
param=-uds
EOF

  transaction_log "mv ${SESMAN_INI}.vps-backup ${SESMAN_INI}"

  log_info "Session manager configuration completed"
  return 0
}

# rdp_server_configure_firewall
# Configures UFW firewall to allow RDP and SSH
#
# Returns:
#   0 - Firewall configuration successful
#   1 - Firewall configuration failed
rdp_server_configure_firewall() {
  log_info "Configuring firewall rules"
  progress_update "Configuring firewall" 70

  # Check if ufw is installed
  if ! command -v ufw &>/dev/null; then
    log_info "Installing UFW firewall"
    apt-get install -y ufw 2>&1 | tee -a "${LOG_FILE}" || {
      log_error "Failed to install UFW"
      return 1
    }
    transaction_log "apt-get remove -y ufw"
  fi

  # Reset firewall to defaults (only on first configuration)
  if ! ufw status | grep -q "Status: active"; then
    log_info "Initializing firewall rules"
    ufw --force reset 2>&1 | tee -a "${LOG_FILE}"

    # Set default policies
    ufw default deny incoming 2>&1 | tee -a "${LOG_FILE}"
    ufw default allow outgoing 2>&1 | tee -a "${LOG_FILE}"

    transaction_log "ufw --force disable"
  fi

  # Allow SSH (critical - do not block)
  if ! ufw status | grep -q "${SSH_PORT}/tcp.*ALLOW"; then
    log_info "Allowing SSH port ${SSH_PORT}"
    ufw allow "${SSH_PORT}/tcp" comment 'SSH access' 2>&1 | tee -a "${LOG_FILE}"
  else
    log_info "SSH port ${SSH_PORT} already allowed"
  fi

  # Allow RDP
  if ! ufw status | grep -q "${RDP_PORT}/tcp.*ALLOW"; then
    log_info "Allowing RDP port ${RDP_PORT}"
    ufw allow "${RDP_PORT}/tcp" comment 'RDP access' 2>&1 | tee -a "${LOG_FILE}"
  else
    log_info "RDP port ${RDP_PORT} already allowed"
  fi

  # Enable firewall
  if ! ufw status | grep -q "Status: active"; then
    log_info "Enabling firewall"
    echo "y" | ufw enable 2>&1 | tee -a "${LOG_FILE}"
  fi

  # Verify rules
  log_info "Firewall rules configured:"
  ufw status numbered 2>&1 | tee -a "${LOG_FILE}"

  log_info "Firewall configuration completed"
  return 0
}

# rdp_server_enable_services
# Enables and starts xrdp services
#
# Returns:
#   0 - Services enabled and started
#   1 - Service configuration failed
rdp_server_enable_services() {
  log_info "Enabling xrdp services"
  progress_update "Enabling RDP services" 85

  local -a services=("xrdp" "xrdp-sesman")

  for service in "${services[@]}"; do
    # Enable service
    if ! systemctl is-enabled "${service}" &>/dev/null; then
      log_info "Enabling service: ${service}"
      systemctl enable "${service}" 2>&1 | tee -a "${LOG_FILE}"
      transaction_log "systemctl disable ${service}"
    else
      log_info "Service ${service} already enabled"
    fi

    # Start or restart service
    if systemctl is-active "${service}" &>/dev/null; then
      log_info "Restarting service: ${service}"
      systemctl restart "${service}" 2>&1 | tee -a "${LOG_FILE}"
    else
      log_info "Starting service: ${service}"
      systemctl start "${service}" 2>&1 | tee -a "${LOG_FILE}"
      transaction_log "systemctl stop ${service}"
    fi

    # Verify service is running
    if ! systemctl is-active "${service}" &>/dev/null; then
      log_error "Failed to start service: ${service}"
      systemctl status "${service}" 2>&1 | tee -a "${LOG_FILE}"
      return 1
    fi
  done

  log_info "xrdp services enabled and started"
  return 0
}

# rdp_server_validate_installation
# Validates RDP server installation and configuration
#
# Returns:
#   0 - Validation successful
#   1 - Validation failed
rdp_server_validate_installation() {
  log_info "Validating RDP server installation"
  progress_update "Validating installation" 95

  # Check xrdp service is active
  if ! systemctl is-active xrdp &>/dev/null; then
    log_error "xrdp service is not active"
    return 1
  fi

  # Check xrdp-sesman service is active
  if ! systemctl is-active xrdp-sesman &>/dev/null; then
    log_error "xrdp-sesman service is not active"
    return 1
  fi

  # Check port 3389 is listening
  if ! ss -tuln | grep -q ":${RDP_PORT}"; then
    log_error "RDP port ${RDP_PORT} is not listening"
    ss -tuln | grep ":${RDP_PORT}" 2>&1 | tee -a "${LOG_FILE}"
    return 1
  fi

  # Check TLS certificates exist with correct permissions
  if [[ ! -f "${CERT_FILE}" ]]; then
    log_error "TLS certificate not found: ${CERT_FILE}"
    return 1
  fi

  if [[ ! -f "${KEY_FILE}" ]]; then
    log_error "TLS key not found: ${KEY_FILE}"
    return 1
  fi

  # Verify key permissions (must be 600)
  local key_perms
  key_perms=$(stat -c "%a" "${KEY_FILE}")
  if [[ "${key_perms}" != "600" ]]; then
    log_warning "Incorrect key file permissions: ${key_perms}, fixing to 600"
    chmod 600 "${KEY_FILE}"
    # Verify fix worked
    key_perms=$(stat -c "%a" "${KEY_FILE}")
    if [[ "${key_perms}" != "600" ]]; then
      log_error "Failed to fix key file permissions: still ${key_perms} (expected 600)"
      return 1
    fi
    log_info "Key file permissions corrected to 600"
  fi

  # Verify firewall rules
  if command -v ufw &>/dev/null; then
    if ! ufw status | grep -q "${RDP_PORT}/tcp.*ALLOW"; then
      log_error "RDP port not allowed in firewall"
      return 1
    fi

    if ! ufw status | grep -q "${SSH_PORT}/tcp.*ALLOW"; then
      log_error "SSH port not allowed in firewall (critical)"
      return 1
    fi
  fi

  # Verify configuration files contain expected markers
  if ! grep -q "VPS-PROVISION CONFIGURED" "${XRDP_INI}"; then
    log_error "xrdp.ini does not contain expected configuration"
    return 1
  fi

  if ! grep -q "VPS-PROVISION CONFIGURED" "${SESMAN_INI}"; then
    log_error "sesman.ini does not contain expected configuration"
    return 1
  fi

  log_info "RDP server validation passed"
  return 0
}

# rdp_server_execute
# Main execution function for RDP server setup
#
# Returns:
#   0 - RDP server setup successful
#   1 - Setup failed
rdp_server_execute() {
  log_info "Starting RDP server installation"
  progress_start_phase "rdp-server"

  # Check if already completed
  if checkpoint_exists "${RDP_SERVER_PHASE}"; then
    log_info "RDP server already configured (checkpoint exists)"
    progress_complete "RDP server (cached)"
    return 0
  fi

  # Execute installation steps
  rdp_server_check_prerequisites || return 1
  rdp_server_install_packages || return 1
  rdp_server_generate_certificates || return 1
  rdp_server_configure_xrdp || return 1
  rdp_server_configure_sesman || return 1
  rdp_server_configure_firewall || return 1
  rdp_server_enable_services || return 1
  rdp_server_validate_installation || return 1

  # Create checkpoint
  checkpoint_create "${RDP_SERVER_PHASE}" || {
    log_error "Failed to create checkpoint"
    return 1
  }

  progress_complete "RDP server configured"
  log_info "RDP server installation completed successfully"
  log_info "RDP access available on port ${RDP_PORT}"
  return 0
}

# Export functions
export -f rdp_server_check_prerequisites
export -f rdp_server_install_packages
export -f rdp_server_generate_certificates
export -f rdp_server_configure_xrdp
export -f rdp_server_configure_sesman
export -f rdp_server_configure_firewall
export -f rdp_server_enable_services
export -f rdp_server_validate_installation
export -f rdp_server_execute
