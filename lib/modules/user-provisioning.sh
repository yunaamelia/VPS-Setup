#!/bin/bash
# User Provisioning Module
# Creates developer user account with passwordless sudo privileges
# Includes group membership, password generation, and .xsession configuration
#
# Usage:
#   source lib/modules/user-provisioning.sh
#   user_provisioning_execute
#
# Dependencies:
#   - lib/core/logger.sh
#   - lib/core/checkpoint.sh
#   - lib/core/transaction.sh
#   - lib/core/progress.sh
#   - lib/utils/credential-gen.py

set -euo pipefail

# Prevent multiple sourcing
if [[ -n "${_USER_PROVISIONING_SH_LOADED:-}" ]]; then
  return 0
fi
readonly _USER_PROVISIONING_SH_LOADED=1

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
readonly USER_PROV_PHASE="${USER_PROV_PHASE:-user-creation}"
readonly DEFAULT_USERNAME="${DEFAULT_USERNAME:-devuser}"
readonly DEVUSERS_GROUP="${DEVUSERS_GROUP:-devusers}"
readonly REQUIRED_GROUPS=(sudo audio video dialout plugdev)

# user_provisioning_check_prerequisites
# Validates system is ready for user provisioning
#
# Returns:
#   0 - Prerequisites met
#   1 - Prerequisites failed
user_provisioning_check_prerequisites() {
  log_info "Checking user provisioning prerequisites"

  # Verify system-prep phase completed
  if ! checkpoint_exists "system-prep"; then
    log_error "System preparation must be completed before user provisioning"
    return 1
  fi

  # Verify Python credential generator exists
  if [[ ! -f "${LIB_DIR}/utils/credential-gen.py" ]]; then
    log_error "Credential generator utility not found"
    return 1
  fi

  # Verify Python 3 is available
  if ! command -v python3 &>/dev/null; then
    log_error "Python 3 not found (required for credential generation)"
    return 1
  fi

  log_info "Prerequisites check passed"
  return 0
}

# user_provisioning_create_group
# Creates the devusers group if it doesn't exist
#
# Returns:
#   0 - Group created or exists
#   1 - Group creation failed
user_provisioning_create_group() {
  log_info "Creating devusers group"

  if getent group "${DEVUSERS_GROUP}" &>/dev/null; then
    log_info "Group ${DEVUSERS_GROUP} already exists"
    return 0
  fi

  if ! groupadd "${DEVUSERS_GROUP}" 2>&1 | tee -a "${LOG_FILE}"; then
    log_error "Failed to create group: ${DEVUSERS_GROUP}"
    return 1
  fi

  transaction_log "groupdel ${DEVUSERS_GROUP}"
  log_info "Group ${DEVUSERS_GROUP} created successfully"
  return 0
}

# user_provisioning_create_user
# Creates developer user account with home directory
#
# Args:
#   $1 - Username (default: devuser)
#
# Returns:
#   0 - User created or exists
#   1 - User creation failed
user_provisioning_create_user() {
  local username="${1:-${DEFAULT_USERNAME}}"
  log_info "Creating developer user: ${username}"

  if id "${username}" &>/dev/null; then
    log_info "User ${username} already exists"
    return 0
  fi

  # Create user with home directory and bash shell
  if ! useradd -m -s /bin/bash -g "${DEVUSERS_GROUP}" "${username}" 2>&1 | tee -a "${LOG_FILE}"; then
    log_error "Failed to create user: ${username}"
    return 1
  fi

  transaction_log "userdel -r ${username}"
  log_info "User ${username} created successfully"
  return 0
}

# user_provisioning_add_to_groups
# Adds user to required groups for development work
#
# Args:
#   $1 - Username
#
# Returns:
#   0 - Groups added successfully
#   1 - Failed to add groups
user_provisioning_add_to_groups() {
  local username="$1"
  log_info "Adding ${username} to required groups"

  for group in "${REQUIRED_GROUPS[@]}"; do
    # Create group if it doesn't exist
    if ! getent group "${group}" &>/dev/null; then
      log_warning "Group ${group} does not exist, creating it"
      if ! groupadd "${group}" 2>&1 | tee -a "${LOG_FILE}"; then
        log_error "Failed to create group: ${group}"
        return 1
      fi
      transaction_log "groupdel ${group}"
    fi

    # Add user to group
    if ! usermod -a -G "${group}" "${username}" 2>&1 | tee -a "${LOG_FILE}"; then
      log_error "Failed to add ${username} to group: ${group}"
      return 1
    fi

    log_debug "Added ${username} to group: ${group}"
  done

  log_info "User added to all required groups"
  return 0
}

# user_provisioning_configure_sudo
# Configures passwordless sudo with security lecture, timeout, and audit logging
#
# Args:
#   $1 - Username
#
# Returns:
#   0 - Sudo configured successfully
#   1 - Sudo configuration failed
user_provisioning_configure_sudo() {
  local username="$1"
  local sudoers_dir="${SUDOERS_DIR:-/etc/sudoers.d}"
  local sudoers_file="${sudoers_dir}/80-${username}"
  local sudo_timeout="${SUDO_TIMEOUT:-15}"

  log_info "Configuring passwordless sudo for ${username}"

  # Backup existing file if it exists
  if [[ -f "${sudoers_file}" ]]; then
    cp "${sudoers_file}" "${sudoers_file}.bak"
    transaction_log "mv ${sudoers_file}.bak ${sudoers_file}"
  fi

  # Create sudoers entry with enhanced security settings
  cat >"${sudoers_file}" <<EOF
# Sudoers configuration for developer user: ${username}
# Created by VPS provisioning system
# SEC-010: Enable sudo lecture for security awareness on first use
Defaults:${username} lecture="always"

# T054: Set reasonable sudo timeout (minutes) for session persistence
Defaults:${username} timestamp_timeout=${sudo_timeout}

# SEC-014: Enable audit logging for all sudo commands
# Audit rules configured separately via auditd (see user_provisioning_configure_audit)
# Log file: /var/log/sudo/sudo.log
Defaults:${username} logfile="/var/log/sudo/sudo.log"
Defaults:${username} log_input, log_output

# Passwordless sudo for all commands (developer convenience)
${username} ALL=(ALL) NOPASSWD: ALL
EOF

  # Validate sudoers syntax
  if ! visudo -cf "${sudoers_file}"; then
    log_error "Invalid sudoers syntax, removing file"
    rm -f "${sudoers_file}"
    # Restore backup if it exists
    if [[ -f "${sudoers_file}.bak" ]]; then
      mv "${sudoers_file}.bak" "${sudoers_file}"
    fi
    return 1
  fi

  # Remove backup after successful validation
  rm -f "${sudoers_file}.bak"

  # Set correct permissions (440 = read-only for owner and group)
  chmod 0440 "${sudoers_file}"

  # Create sudo log directory
  mkdir -p /var/log/sudo
  chmod 0750 /var/log/sudo
  transaction_log "rm -rf /var/log/sudo"

  transaction_log "rm -f ${sudoers_file}"
  log_info "Passwordless sudo configured with enhanced security (lecture, timeout=${sudo_timeout}min, audit logging)"
  return 0
}

# user_provisioning_configure_audit
# Configures auditd to log all sudo executions per SEC-014
#
# Returns:
#   0 - Audit configured successfully
#   1 - Audit configuration failed
user_provisioning_configure_audit() {
  log_info "Configuring auditd for sudo command logging (SEC-014)"

  # Install auditd if not present
  if ! dpkg -s auditd &>/dev/null; then
    log_info "Installing auditd package"
    if ! apt-get update &>/dev/null && apt-get install -y auditd 2>&1 | tee -a "${LOG_FILE}"; then
      log_error "Failed to install auditd"
      return 1
    fi
    transaction_log "apt-get remove -y auditd"
  fi

  # Enable auditd service
  if ! systemctl is-enabled auditd &>/dev/null; then
    systemctl enable auditd 2>&1 | tee -a "${LOG_FILE}"
    transaction_log "systemctl disable auditd"
  fi

  # Start auditd if not running
  if ! systemctl is-active auditd &>/dev/null; then
    systemctl start auditd 2>&1 | tee -a "${LOG_FILE}"
  fi

  # Configure audit rule to watch sudo executions
  local audit_rules_file="/etc/audit/rules.d/sudo-logging.rules"

  # Backup existing rules if present
  if [[ -f "${audit_rules_file}" ]]; then
    cp "${audit_rules_file}" "${audit_rules_file}.bak"
    transaction_log "mv ${audit_rules_file}.bak ${audit_rules_file}"
  fi

  # Create audit rules for sudo commands
  cat >"${audit_rules_file}" <<'EOF'
# Audit rules for sudo command logging (SEC-014)
# Monitor all executions of sudo binary
-w /usr/bin/sudo -p x -k sudo_commands

# Monitor sudoers file modifications
-w /etc/sudoers -p wa -k sudoers_changes
-w /etc/sudoers.d/ -p wa -k sudoers_changes

# Monitor user privilege escalation
-a always,exit -F arch=b64 -S execve -F euid=0 -F auid>=1000 -F auid!=4294967295 -k privileged_execution
-a always,exit -F arch=b32 -S execve -F euid=0 -F auid>=1000 -F auid!=4294967295 -k privileged_execution
EOF

  transaction_log "rm -f ${audit_rules_file}"

  # Load audit rules
  if ! auditctl -R "${audit_rules_file}" 2>&1 | tee -a "${LOG_FILE}"; then
    log_warning "Failed to load audit rules immediately (will load on next boot)"
  fi

  # Configure log retention (30 days per SEC-014)
  local auditd_conf="/etc/audit/auditd.conf"

  if [[ -f "${auditd_conf}" ]]; then
    # Backup configuration
    cp "${auditd_conf}" "${auditd_conf}.bak"
    transaction_log "mv ${auditd_conf}.bak ${auditd_conf}"

    # Set log retention parameters
    sed -i 's/^max_log_file_action = .*/max_log_file_action = ROTATE/' "${auditd_conf}"
    sed -i 's/^num_logs = .*/num_logs = 30/' "${auditd_conf}"
    sed -i 's/^max_log_file = .*/max_log_file = 50/' "${auditd_conf}"

    # Reload auditd configuration
    if systemctl is-active auditd &>/dev/null; then
      systemctl restart auditd 2>&1 | tee -a "${LOG_FILE}"
    fi
  fi

  log_info "Auditd configured successfully with 30-day log retention"
  return 0
}

# user_provisioning_generate_password
# Generates strong random password and sets it for user
# Implements SEC-001 (16+ chars), SEC-002 (CSPRNG), SEC-003 (redaction)
#
# Args:
#   $1 - Username
#
# Returns:
#   0 - Password generated and set
#   1 - Password generation failed
#
# Outputs:
#   Generated password to stdout
user_provisioning_generate_password() {
  local username="$1"
  local password
  local stderr_output

  log_info "Generating secure password for ${username} (16+ chars, CSPRNG)"

  # Generate password using Python utility (captures stderr separately)
  # SEC-002: Uses CSPRNG via secrets module
  # SEC-001: Enforces minimum 16 characters
  stderr_output=$(mktemp)
  password=$(python3 "${LIB_DIR}/utils/credential-gen.py" --length 20 --complexity high 2>"${stderr_output}")
  local gen_exit_code=$?

  if [[ ${gen_exit_code} -ne 0 ]]; then
    log_error "Password generation failed: $(cat "${stderr_output}")"
    rm -f "${stderr_output}"
    return 1
  fi

  if [[ -z "${password}" ]]; then
    log_error "Password generation returned empty result"
    rm -f "${stderr_output}"
    return 1
  fi

  rm -f "${stderr_output}"

  # SEC-003: Set password WITHOUT logging it (use 2>&1 redirection to /dev/null for chpasswd)
  # We only log success/failure, never the actual password
  if ! echo "${username}:${password}" | chpasswd 2>/dev/null; then
    log_error "Failed to set password for ${username} (chpasswd failed)"
    return 1
  fi

  log_info "Password set successfully for ${username} (password: [REDACTED])"

  # SEC-004: Force password change on first login per requirement
  # Note: 'chage' is the correct command name (change age)
  if ! chage -d 0 "${username}" 2>&1 | grep -v "password" | tee -a "${LOG_FILE}" >/dev/null; then
    log_error "Failed to set password expiration for ${username}"
    return 1
  fi

  log_info "Password expiry configured: user must change on first login (SEC-004)"

  # Return password for display in final summary ONLY (security note: intentional per FR-027)
  # Calling function is responsible for secure display (not logging to file)
  echo "${password}"
  return 0
}

# user_provisioning_create_xsession
# Creates .xsession file for XFCE compatibility with xrdp
#
# Args:
#   $1 - Username
#
# Returns:
#   0 - .xsession created successfully
#   1 - .xsession creation failed
user_provisioning_create_xsession() {
  local username="$1"
  local home_dir

  log_info "Creating .xsession file for ${username}"

  # Get user's home directory
  home_dir=$(getent passwd "${username}" | cut -d: -f6)

  if [[ -z "${home_dir}" || ! -d "${home_dir}" ]]; then
    log_error "Home directory not found for ${username}"
    return 1
  fi

  local xsession_file="${home_dir}/.xsession"

  # Create .xsession file for XFCE
  cat >"${xsession_file}" <<'EOF'
#!/bin/bash
# XFCE session configuration for xrdp
# Auto-generated by VPS provisioning system

# Load system profile
if [ -f /etc/profile ]; then
  . /etc/profile
fi

# Load user profile
if [ -f ~/.profile ]; then
  . ~/.profile
fi

# Start XFCE desktop
exec startxfce4
EOF

  # Set executable permissions
  chmod +x "${xsession_file}"

  # Set ownership
  chown "${username}:${username}" "${xsession_file}"

  transaction_log "rm -f ${xsession_file}"
  log_info ".xsession file created successfully"
  return 0
}

# user_provisioning_verify
# Verifies user account configuration
#
# Args:
#   $1 - Username
#
# Returns:
#   0 - Verification successful
#   1 - Verification failed
user_provisioning_verify() {
  local username="$1"
  log_info "Verifying user provisioning for ${username}"

  # Check user exists with UID >= 1000
  local uid
  uid=$(id -u "${username}" 2>/dev/null || echo 0)

  if [[ ${uid} -lt 1000 ]]; then
    log_error "User ${username} has invalid UID: ${uid} (expected >= 1000)"
    return 1
  fi

  # Check user is in all required groups
  local user_groups
  user_groups=$(id -Gn "${username}" 2>/dev/null || echo "")

  for group in "${REQUIRED_GROUPS[@]}"; do
    if ! echo "${user_groups}" | grep -qw "${group}"; then
      log_error "User ${username} not in required group: ${group}"
      return 1
    fi
  done

  # Check sudo configuration exists
  local sudoers_dir="${SUDOERS_DIR:-/etc/sudoers.d}"
  if [[ ! -f "${sudoers_dir}/80-${username}" ]]; then
    log_error "Sudo configuration not found for ${username}"
    return 1
  fi

  # Check home directory permissions
  local home_dir
  home_dir=$(getent passwd "${username}" | cut -d: -f6)

  if [[ ! -d "${home_dir}" ]]; then
    log_error "Home directory not found: ${home_dir}"
    return 1
  fi

  # Check .xsession file exists and is executable
  if [[ ! -x "${home_dir}/.xsession" ]]; then
    log_error ".xsession file not found or not executable"
    return 1
  fi

  log_info "User provisioning verification passed"
  return 0
}

# user_provisioning_execute
# Main entry point for user provisioning module
#
# Args:
#   $1 - Username (optional, default: devuser)
#
# Returns:
#   0 - Provisioning successful
#   1 - Provisioning failed
user_provisioning_execute() {
  local username="${1:-${DEFAULT_USERNAME}}"
  local password

  log_info "Starting user provisioning module"
  progress_update "Creating developer user" 40

  # Check if already completed
  if checkpoint_exists "${USER_PROV_PHASE}"; then
    log_info "User provisioning already completed (checkpoint exists)"
    return 0
  fi

  # Prerequisites check
  if ! user_provisioning_check_prerequisites; then
    log_error "Prerequisites check failed"
    return 1
  fi

  # Create devusers group
  if ! user_provisioning_create_group; then
    log_error "Failed to create devusers group"
    return 1
  fi

  # Create user account
  if ! user_provisioning_create_user "${username}"; then
    log_error "Failed to create user account"
    return 1
  fi

  # Add to required groups
  if ! user_provisioning_add_to_groups "${username}"; then
    log_error "Failed to add user to groups"
    return 1
  fi

  # Configure passwordless sudo
  if ! user_provisioning_configure_sudo "${username}"; then
    log_error "Failed to configure sudo"
    return 1
  fi

  # Configure audit logging for sudo commands (T056)
  if ! user_provisioning_configure_audit; then
    log_error "Failed to configure audit logging"
    return 1
  fi

  # Generate and set password
  password=$(user_provisioning_generate_password "${username}")
  if [[ $? -ne 0 || -z "${password}" ]]; then
    log_error "Failed to generate password"
    return 1
  fi

  # Create .xsession file
  if ! user_provisioning_create_xsession "${username}"; then
    log_error "Failed to create .xsession file"
    return 1
  fi

  # Verify configuration
  if ! user_provisioning_verify "${username}"; then
    log_error "User provisioning verification failed"
    return 1
  fi

  # Create checkpoint
  if ! checkpoint_create "${USER_PROV_PHASE}"; then
    log_warning "Failed to create checkpoint (non-fatal)"
  fi

  # Display credentials (FR-027: credentials must be displayed)
  log_info "=================================="
  log_info "Developer Account Created"
  log_info "=================================="
  log_info "Username: ${username}"
  log_info "Password: ${password}"
  log_info "Sudo: Passwordless (all commands)"
  log_info "Groups: ${REQUIRED_GROUPS[*]}"
  log_info ""
  log_info "IMPORTANT: You will be required to change this password on first login"
  log_info "=================================="

  progress_update "Developer user created" 45
  log_info "User provisioning completed successfully"

  return 0
}

# If script is executed directly (not sourced), run main function
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  user_provisioning_execute "$@"
fi
