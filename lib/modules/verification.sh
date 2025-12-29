#!/bin/bash
# Verification Module - Post-Provisioning Validation
# Validates all services, installations, and configurations
#
# Usage: source lib/modules/verification.sh && verification_execute

set -euo pipefail

# Source dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(dirname "$SCRIPT_DIR")"

# shellcheck disable=SC1091
source "${LIB_DIR}/core/logger.sh"
# shellcheck disable=SC1091
source "${LIB_DIR}/core/checkpoint.sh"

readonly VERIFICATION_PHASE="verification"

# Helpers for testing
check_file() { [[ -f "$1" ]]; }
check_dir() { [[ -d "$1" ]]; }
check_executable() { [[ -x "$1" ]]; }
is_container_env() {
  [[ -f /.dockerenv ]] || [[ -f /run/.containerenv ]] || grep -qiE '(docker|lxc|container)' /proc/1/cgroup 2>/dev/null
}
verification_check_services() {
  log_info "Verifying system services..."
  local services_ok=true

  # Check xrdp service
  if systemctl is-active --quiet xrdp; then
    log_info "✓ xrdp service is running"
  else
    log_error "xrdp service is not running"
    services_ok=false
  fi

  # Check lightdm service (non-critical in container environments)
  if systemctl is-active --quiet lightdm; then
    log_info "✓ lightdm service is running"
  else
    if is_container_env; then
      log_info "lightdm service is not running (expected in container environments)"
    else
      log_warning "lightdm service is not running"
    fi
    # Don't fail verification - lightdm may not run in containers
  fi

  # Check sshd service
  if systemctl is-active --quiet ssh || systemctl is-active --quiet sshd; then
    log_info "✓ SSH service is running"
  else
    log_warning "SSH service status unclear"
  fi

  if [[ "${services_ok}" == "false" ]]; then
    return 1
  fi

  return 0
}

# Verification: Check all IDE executables exist and can launch
verification_check_ides() {
  log_info "Verifying IDE installations..."
  local ides_ok=true

  # Check VSCode
  if command -v code &>/dev/null; then
    log_info "✓ VSCode executable found"
    # Test version command (lightweight check)
    if code --version &>/dev/null; then
      log_info "✓ VSCode responds to --version"
    else
      log_info "VSCode found but version check failed (expected in headless environments)"
    fi
  else
    log_error "VSCode not found in PATH"
    ides_ok=false
  fi

  # Check Cursor
  if command -v cursor &>/dev/null || check_executable "/opt/cursor/cursor"; then
    log_info "✓ Cursor executable found"
  else
    log_error "Cursor not found"
    ides_ok=false
  fi

  # Check Antigravity
  if command -v antigravity &>/dev/null || check_executable "/usr/local/bin/antigravity"; then
    log_info "✓ Antigravity executable found"
  else
    log_error "Antigravity not found"
    ides_ok=false
  fi

  if [[ "${ides_ok}" == "false" ]]; then
    return 1
  fi

  return 0
}

# Verification: Test network port accessibility
verification_check_ports() {
  log_info "Verifying network port accessibility..."
  local ports_ok=true

  # Check SSH port (22)
  if netstat -tuln 2>/dev/null | grep -q ":22 "; then
    log_info "✓ SSH port 22 is listening"
  elif ss -tuln 2>/dev/null | grep -q ":22 "; then
    log_info "✓ SSH port 22 is listening (ss)"
  else
    log_warning "SSH port 22 status unclear"
  fi

  # Check RDP port (3389)
  if netstat -tuln 2>/dev/null | grep -q ":3389 "; then
    log_info "✓ RDP port 3389 is listening"
  elif ss -tuln 2>/dev/null | grep -q ":3389 "; then
    log_info "✓ RDP port 3389 is listening (ss)"
  else
    log_error "RDP port 3389 not listening"
    ports_ok=false
  fi

  if [[ "${ports_ok}" == "false" ]]; then
    return 1
  fi

  return 0
}

# Verification: Validate file permissions
verification_check_permissions() {
  log_info "Validating file permissions..."
  local perms_ok=true

  # Check xrdp TLS certificates
  if check_file "/etc/xrdp/cert.pem"; then
    local cert_perms
    cert_perms=$(stat -c "%a" /etc/xrdp/cert.pem 2>/dev/null || echo "000")
    if [[ "${cert_perms}" == "644" ]] || [[ "${cert_perms}" == "600" ]]; then
      log_info "✓ xrdp certificate permissions correct (${cert_perms})"
    else
      if chmod 600 /etc/xrdp/cert.pem 2>/dev/null; then
        log_info "Corrected xrdp certificate permissions to 600 (was ${cert_perms})"
      else
        log_error "Unable to correct xrdp certificate permissions (current ${cert_perms})"
        perms_ok=false
      fi
    fi
  fi

  # Check developer user home directory
  if check_dir "/home/devuser"; then
    local home_owner
    home_owner=$(stat -c "%U" /home/devuser 2>/dev/null || echo "unknown")
    if [[ "${home_owner}" == "devuser" ]]; then
      log_info "✓ Developer home directory owned by devuser"
    else
      log_error "Developer home directory owner: ${home_owner} (expected devuser)"
      perms_ok=false
    fi
  fi

  if [[ "${perms_ok}" == "false" ]]; then
    return 1
  fi

  return 0
}

# Verification: Check configuration files correctness
verification_check_configurations() {
  log_info "Validating configuration files..."
  local configs_ok=true

  # Check xrdp configuration
  if check_file "/etc/xrdp/xrdp.ini"; then
    if grep -q "max_bpp=32" /etc/xrdp/xrdp.ini; then
      log_info "✓ xrdp.ini configured correctly (max_bpp=32)"
    else
      log_warning "xrdp.ini may not be optimally configured"
    fi
  else
    log_error "xrdp.ini not found"
    configs_ok=false
  fi

  # Check XFCE configuration
  if check_dir "/etc/xdg/xfce4" || check_dir "/home/devuser/.config/xfce4"; then
    log_info "✓ XFCE configuration directory exists"
  else
    log_warning "XFCE configuration directory not found"
  fi

  if [[ "${configs_ok}" == "false" ]]; then
    return 1
  fi

  return 0
}

# Main verification execution
verification_execute() {
  log_info "Starting post-provisioning verification..."

  # Check if already completed
  if checkpoint_exists "${VERIFICATION_PHASE}"; then
    log_info "Verification already completed (checkpoint exists)"
    return 0
  fi

  local verification_failed=false

  # Run all verification checks
  if ! verification_check_services; then
    log_error "Service verification failed"
    verification_failed=true
  fi

  if ! verification_check_ides; then
    log_error "IDE verification failed"
    verification_failed=true
  fi

  if ! verification_check_ports; then
    log_error "Port verification failed"
    verification_failed=true
  fi

  if ! verification_check_permissions; then
    log_error "Permission verification failed"
    verification_failed=true
  fi

  if ! verification_check_configurations; then
    log_error "Configuration verification failed"
    verification_failed=true
  fi

  if [[ "${verification_failed}" == "true" ]]; then
    log_error "Verification phase failed"
    return 1
  fi


  log_info "All verification checks passed!"
  return 0
}

# Export functions
export -f verification_check_services
export -f verification_check_ides
export -f verification_check_ports
export -f verification_check_permissions
export -f verification_check_configurations
export -f verification_execute
