#!/bin/bash
# Audit Logging Module
# Configures auditd for security event logging
# Implements SEC-014 and SEC-015 requirements
#
# Usage:
#   source lib/modules/audit-logging.sh
#   audit_logging_execute
#
# Dependencies:
#   - lib/core/logger.sh
#   - lib/core/checkpoint.sh
#   - lib/core/transaction.sh
#   - lib/core/progress.sh

set -euo pipefail

# Prevent multiple sourcing
if [[ -n "${_AUDIT_LOGGING_SH_LOADED:-}" ]]; then
  return 0
fi
readonly _AUDIT_LOGGING_SH_LOADED=1

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
readonly AUDIT_PHASE="${AUDIT_PHASE:-audit-logging}"
# Allow override for testing
AUDIT_RULES_FILE="${AUDIT_RULES_FILE:-/etc/audit/rules.d/vps-provision.rules}"
readonly LOG_RETENTION_DAYS="${LOG_RETENTION_DAYS:-30}"
readonly AUDITD_CONF="${AUDITD_CONF:-/etc/audit/auditd.conf}"
readonly LOGROTATE_CONF="${LOGROTATE_CONF:-/etc/logrotate.d/auth-vps}"
readonly AUTH_LOG_FILE="${AUTH_LOG_FILE:-/var/log/auth.log}"
readonly AUDIT_LOG_DIR="${AUDIT_LOG_DIR:-/var/log/audit}"

# audit_logging_check_prerequisites
# Validates system is ready for audit logging configuration
#
# Returns:
#   0 - Prerequisites met
#   1 - Prerequisites failed
audit_logging_check_prerequisites() {
  log_info "Checking audit logging prerequisites"
  
  # Verify system-prep phase completed
  if ! checkpoint_exists "system-prep"; then
    log_error "System preparation must be completed before audit logging"
    return 1
  fi
  
  log_info "Prerequisites check passed"
  return 0
}

# audit_logging_install_auditd
# Installs auditd package
#
# Returns:
#   0 - Installation successful
#   1 - Installation failed
audit_logging_install_auditd() {
  log_info "Installing auditd"
  progress_update "Installing auditd" 10
  
  # Check if already installed
  if command -v auditctl &> /dev/null; then
    log_info "auditd already installed"
    return 0
  fi
  
  export DEBIAN_FRONTEND=noninteractive
  
  if ! apt-get install -y auditd audispd-plugins 2>&1 | tee -a "${LOG_FILE}"; then
    log_error "Failed to install auditd"
    return 1
  fi
  
  transaction_log "apt-get remove -y auditd audispd-plugins"
  
  # Verify installation
  if ! command -v auditctl &> /dev/null; then
    log_error "auditd installation verification failed"
    return 1
  fi
  
  log_info "auditd installed successfully"
  return 0
}

# audit_logging_configure_sudo_monitoring
# Configures audit rules for sudo monitoring (SEC-014)
#
# Returns:
#   0 - Configuration successful
#   1 - Configuration failed
audit_logging_configure_sudo_monitoring() {
  log_info "Configuring sudo monitoring (SEC-014)"
  progress_update "Configuring audit rules" 30
  
  # Backup existing rules if present
  if [[ -f "${AUDIT_RULES_FILE}" ]]; then
    transaction_log "mv ${AUDIT_RULES_FILE}.vps-backup ${AUDIT_RULES_FILE}"
    cp "${AUDIT_RULES_FILE}" "${AUDIT_RULES_FILE}.vps-backup"
  fi
  
  # Create audit rules for sudo monitoring
  # SEC-014: Log all sudo executions
  cat > "${AUDIT_RULES_FILE}" <<'EOF'
# VPS-PROVISION CONFIGURED audit rules
# SEC-014: Monitor all sudo command executions

# Monitor sudo execution
-a always,exit -F arch=b64 -F auid>=1000 -F auid!=4294967295 -S execve -F exe=/usr/bin/sudo -k sudo_execution
-a always,exit -F arch=b32 -F auid>=1000 -F auid!=4294967295 -S execve -F exe=/usr/bin/sudo -k sudo_execution

# Monitor changes to sudo configuration
-w /etc/sudoers -p wa -k sudoers_changes
-w /etc/sudoers.d/ -p wa -k sudoers_changes

# Monitor authentication events
-w ${AUTH_LOG_FILE} -p wa -k auth_log_changes
-w /var/log/faillog -p wa -k auth_failures

# Monitor user/group modifications
-w /etc/passwd -p wa -k passwd_changes
-w /etc/group -p wa -k group_changes
-w /etc/shadow -p wa -k shadow_changes

# Monitor SSH configuration changes
-w /etc/ssh/sshd_config -p wa -k sshd_config_changes

# Monitor system calls for privilege escalation
-a always,exit -F arch=b64 -S setuid -S setgid -S setreuid -S setregid -k privilege_escalation
-a always,exit -F arch=b32 -S setuid -S setgid -S setreuid -S setregid -k privilege_escalation

# Monitor file permission changes
-a always,exit -F arch=b64 -S chmod -S fchmod -S fchmodat -k perm_mod
-a always,exit -F arch=b32 -S chmod -S fchmod -S fchmodat -k perm_mod
-a always,exit -F arch=b64 -S chown -S fchown -S lchown -S fchownat -k ownership_mod
-a always,exit -F arch=b32 -S chown -S fchown -S lchown -S fchownat -k ownership_mod
EOF
  
  transaction_log "rm -f ${AUDIT_RULES_FILE}"
  
  log_info "Sudo monitoring configured successfully"
  return 0
}

# audit_logging_configure_retention
# Configures log retention for 30 days (SEC-014)
#
# Returns:
#   0 - Configuration successful
#   1 - Configuration failed
audit_logging_configure_retention() {
  log_info "Configuring log retention (SEC-014: 30 days)"
  progress_update "Configuring log retention" 50
  
  local auditd_conf="${AUDITD_CONF}"
  
  # Backup original configuration
  if [[ -f "${auditd_conf}" && ! -f "${auditd_conf}.vps-backup" ]]; then
    transaction_log "mv ${auditd_conf}.vps-backup ${auditd_conf}"
    cp "${auditd_conf}" "${auditd_conf}.vps-backup"
  fi
  
  # Configure log rotation and retention
  # Set max_log_file_action to rotate when logs get large
  if grep -q "^max_log_file_action" "${auditd_conf}"; then
    sed -i.tmp 's/^max_log_file_action.*/max_log_file_action = ROTATE/' "${auditd_conf}"
  else
    echo "max_log_file_action = ROTATE" >> "${auditd_conf}"
  fi
  
  # Keep 30 rotated log files (approximately 30 days worth)
  if grep -q "^num_logs" "${auditd_conf}"; then
    sed -i.tmp 's/^num_logs.*/num_logs = 30/' "${auditd_conf}"
  else
    echo "num_logs = 30" >> "${auditd_conf}"
  fi
  
  # Set max log file size to 10MB
  if grep -q "^max_log_file " "${auditd_conf}"; then
    sed -i.tmp 's/^max_log_file .*/max_log_file = 10/' "${auditd_conf}"
  else
    echo "max_log_file = 10" >> "${auditd_conf}"
  fi
  
  rm -f "${auditd_conf}.tmp"
  
  # Configure logrotate for auth.log (SEC-015)
  local logrotate_conf="${LOGROTATE_CONF}"
  cat > "${logrotate_conf}" <<EOF
# VPS-PROVISION auth.log rotation
# SEC-015: Ensure authentication logs are retained for 30 days
${AUTH_LOG_FILE} {
    daily
    rotate 30
    missingok
    notifempty
    compress
    delaycompress
    postrotate
        invoke-rc.d rsyslog rotate > /dev/null
    endscript
}
EOF
  
  transaction_log "rm -f ${logrotate_conf}"
  
  log_info "Log retention configured successfully"
  return 0
}

# audit_logging_enable
# Enables and starts auditd service
#
# Returns:
#   0 - Enable successful
#   1 - Enable failed
audit_logging_enable() {
  log_info "Enabling auditd service"
  progress_update "Enabling audit logging" 70
  
  # Load audit rules
  if ! auditctl -R "${AUDIT_RULES_FILE}" 2>&1 | tee -a "${LOG_FILE}"; then
    log_error "Failed to load audit rules"
    return 1
  fi
  
  # Restart auditd to apply configuration
  if ! systemctl restart auditd 2>&1 | tee -a "${LOG_FILE}"; then
    log_error "Failed to restart auditd"
    return 1
  fi
  
  # Enable on boot
  if ! systemctl enable auditd 2>&1 | tee -a "${LOG_FILE}"; then
    log_warning "Failed to enable auditd on boot (non-critical)"
  fi
  
  transaction_log "systemctl stop auditd && systemctl disable auditd && auditctl -D"
  
  log_info "auditd service enabled successfully"
  return 0
}

# audit_logging_verify
# Verifies audit logging is active
#
# Returns:
#   0 - Verification successful
#   1 - Verification failed
audit_logging_verify() {
  log_info "Verifying audit logging configuration"
  progress_update "Verifying audit logging" 90
  
  # Check auditd service status
  if ! systemctl is-active --quiet auditd; then
    log_error "auditd service is not running"
    return 1
  fi
  
  # Check if audit rules are loaded
  local rules_count
  rules_count=$(auditctl -l | grep -c -v "^No rules")
  
  if [[ ${rules_count} -lt 5 ]]; then
    log_error "Insufficient audit rules loaded (found ${rules_count}, expected >5)"
    return 1
  fi
  
  log_info "Audit rules loaded: ${rules_count} rules"
  
  # Verify sudo monitoring rule exists
  local audit_output
  audit_output=$(auditctl -l)
  # log_info "DEBUG: auditctl output: $audit_output"
  if ! echo "$audit_output" | grep -q "sudo_execution"; then
    log_error "Sudo execution monitoring rule not found"
    return 1
  fi
  
  # Verify auth.log exists (SEC-015)
  if [[ ! -f ${AUTH_LOG_FILE} ]]; then
    log_error "auth.log file not found"
    return 1
  fi
  
  # Display active audit rules
  log_info "Active audit rules:"
  auditctl -l | head -20 | tee -a "${LOG_FILE}"
  
  log_info "Audit logging configuration verified successfully"
  return 0
}

# audit_logging_execute
# Main execution function for audit logging module
#
# Returns:
#   0 - Execution successful
#   1 - Execution failed
audit_logging_execute() {
  log_info "Starting audit logging configuration"
  
  # Check for existing checkpoint
  if checkpoint_exists "$AUDIT_PHASE"; then
    log_info "Audit logging already configured, skipping"
    return 0
  fi
  
  # Check prerequisites
  if ! audit_logging_check_prerequisites; then
    return 1
  fi
  
  # Install auditd
  if ! audit_logging_install_auditd; then
    return 1
  fi
  
  # Configure sudo monitoring
  if ! audit_logging_configure_sudo_monitoring; then
    return 1
  fi
  
  # Configure log retention
  if ! audit_logging_configure_retention; then
    return 1
  fi
  
  # Enable audit logging
  if ! audit_logging_enable; then
    return 1
  fi
  
  # Verify configuration
  if ! audit_logging_verify; then
    return 1
  fi
  
  # Create checkpoint
  checkpoint_create "$AUDIT_PHASE"
  
  progress_update "Audit logging configuration complete" 100
  log_info "Audit logging configuration completed successfully"
  
  return 0
}
