#!/bin/bash
# ux.sh - User experience utilities for CLI interactions
# Implements confirmation prompts, success banners, input validation per UX requirements
#
# Usage:
#   source lib/core/ux.sh
#   if confirm_action "Delete all files?" "This is destructive"; then
#     # proceed
#   fi
#
# Dependencies:
#   - lib/core/logger.sh

set -euo pipefail

# Prevent multiple sourcing
if [[ -n "${_UX_SH_LOADED:-}" ]]; then
  return 0
fi
readonly _UX_SH_LOADED=1

# Source dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/core/logger.sh
source "${SCRIPT_DIR}/logger.sh"

# Global UX settings
UX_YES_MODE="${UX_YES_MODE:-false}"  # --yes flag bypasses prompts
UX_INTERACTIVE="${UX_INTERACTIVE:-true}"  # UX-017: detect non-interactive shells
UX_TERMINAL_WIDTH="${UX_TERMINAL_WIDTH:-80}"  # UX-018: default to 80 chars

# Detect if running in non-interactive shell (CI/CD)
ux_detect_interactive() {
  if [[ ! -t 0 ]] || [[ ! -t 1 ]]; then
    UX_INTERACTIVE=false
    log_debug "Non-interactive shell detected, disabling prompts"
  fi
}

# Detect terminal width (UX-018: restrict output to 80 chars or detect width)
ux_detect_terminal_width() {
  if [[ -t 1 ]]; then
    # Terminal is a TTY, detect width
    if command -v tput &> /dev/null; then
      UX_TERMINAL_WIDTH=$(tput cols 2>/dev/null || echo "${COLUMNS:-80}")
    elif [[ -n "${COLUMNS:-}" ]]; then
      UX_TERMINAL_WIDTH="${COLUMNS}"
    else
      UX_TERMINAL_WIDTH=80
    fi
  else
    # Not a TTY, check COLUMNS or use default
    if [[ -n "${COLUMNS:-}" ]]; then
      UX_TERMINAL_WIDTH="${COLUMNS}"
    else
      UX_TERMINAL_WIDTH=80
    fi
  fi
  
  # Ensure minimum width
  if [[ ${UX_TERMINAL_WIDTH} -lt 40 ]]; then
    UX_TERMINAL_WIDTH=80
  fi
  
  log_debug "Terminal width detected: ${UX_TERMINAL_WIDTH} columns"
}

# Wrap text to terminal width (UX-018)
# Args: $1 - text to wrap, $2 - indent level (optional, default 0)
# Output: wrapped text to stdout
ux_wrap_text() {
  local text="$1"
  local indent="${2:-0}"
  local width=$((UX_TERMINAL_WIDTH - indent))
  
  if [[ ${width} -lt 20 ]]; then
    width=40  # Minimum readable width
  fi
  
  # Use fold or fmt if available, otherwise just output as-is
  if command -v fold &> /dev/null; then
    local indent_str
    indent_str=$(printf '%*s' "$indent" '')
    echo "$text" | fold -w "$width" -s | sed "s/^/${indent_str}/"
  elif command -v fmt &> /dev/null; then
    local indent_str
    indent_str=$(printf '%*s' "$indent" '')
    echo "$text" | fmt -w "$width" | sed "s/^/${indent_str}/"
  else
    echo "$text"
  fi
}

# Prompt for interactive input (UX-014: interactive prompts for missing arguments)
# Args: $1 - prompt message, $2 - default value (optional), $3 - validation function (optional)
# Output: user input to stdout
# Returns: 0 on success, 1 on failure
ux_prompt_input() {
  local prompt="$1"
  local default="${2:-}"
  local validation_func="${3:-}"
  local response
  
  # UX-017: Cannot prompt in non-interactive mode
  if [[ "${UX_INTERACTIVE}" == "false" ]]; then
    log_error "Cannot prompt for input in non-interactive shell"
    if [[ -n "$default" ]]; then
      echo "$default"
      return 0
    else
      return 1
    fi
  fi
  
  # Display prompt
  if [[ -n "$default" ]]; then
    echo -n "${prompt} [${default}]: " >&2
  else
    echo -n "${prompt}: " >&2
  fi
  
  # Read user input
  read -r response
  
  # Use default if empty
  if [[ -z "$response" && -n "$default" ]]; then
    response="$default"
  fi
  
  # Validate if function provided
  if [[ -n "$validation_func" ]]; then
    if ! "$validation_func" "$response"; then
      log_error "Invalid input, please try again"
      return 1
    fi
  fi
  
  echo "$response"
  return 0
}

# Prompt for password with hidden input (UX-014)
# Args: $1 - prompt message
# Output: password to stdout
# Returns: 0 on success, 1 on failure
ux_prompt_password() {
  local prompt="$1"
  local password
  
  # UX-017: Cannot prompt in non-interactive mode
  if [[ "${UX_INTERACTIVE}" == "false" ]]; then
    log_error "Cannot prompt for password in non-interactive shell"
    return 1
  fi
  
  # Display prompt and read password (hidden)
  echo -n "${prompt}: " >&2
  read -rs password
  echo "" >&2  # newline after hidden input
  
  if [[ -z "$password" ]]; then
    log_error "Password cannot be empty"
    return 1
  fi
  
  echo "$password"
  return 0
}

# Prompt for confirmation yes/no (UX-014)
# Args: $1 - prompt message, $2 - default (y/n, optional)
# Returns: 0 for yes, 1 for no
ux_prompt_confirm() {
  local prompt="$1"
  local default="${2:-}"
  local response
  
  # UX-017: Cannot prompt in non-interactive mode or with --yes flag
  if [[ "${UX_YES_MODE}" == "true" ]]; then
    log_debug "Auto-confirming (--yes mode): $prompt"
    return 0
  fi
  
  if [[ "${UX_INTERACTIVE}" == "false" ]]; then
    log_error "Cannot prompt for confirmation in non-interactive shell"
    return 1
  fi
  
  # Display prompt with default indication
  if [[ "$default" == "y" ]]; then
    echo -n "${prompt} [Y/n]: " >&2
  elif [[ "$default" == "n" ]]; then
    echo -n "${prompt} [y/N]: " >&2
  else
    echo -n "${prompt} [y/n]: " >&2
  fi
  
  read -r response
  
  # Use default if empty
  if [[ -z "$response" && -n "$default" ]]; then
    response="$default"
  fi
  
  # Parse response
  case "${response,,}" in
    y|yes)
      return 0
      ;;
    n|no)
      return 1
      ;;
    *)
      if [[ "$default" == "y" ]]; then
        return 0
      elif [[ "$default" == "n" ]]; then
        return 1
      else
        log_error "Invalid response, please enter 'y' or 'n'"
        return 1
      fi
      ;;
  esac
}

# Confirm action with user (UX-009: confirmation prompts for destructive operations)
# Args: $1 - prompt message, $2 - warning message (optional)
# Returns: 0 if user confirms (or --yes mode), 1 otherwise
confirm_action() {
  local prompt="$1"
  local warning="${2:-}"
  
  # UX-017: Bypass in non-interactive mode or with --yes flag
  if [[ "${UX_YES_MODE}" == "true" ]]; then
    log_debug "Skipping confirmation (--yes mode): $prompt"
    return 0
  fi
  
  if [[ "${UX_INTERACTIVE}" == "false" ]]; then
    log_error "Cannot prompt for confirmation in non-interactive shell"
    log_error "Use --yes flag to bypass confirmation prompts"
    return 1
  fi
  
  # Display warning if provided
  if [[ -n "$warning" ]]; then
    log_warning "$warning"
  fi
  
  # Prompt user
  echo ""
  echo -n "$prompt [y/N]: "
  read -r response
  
  case "${response,,}" in
    y|yes)
      log_debug "User confirmed: $prompt"
      return 0
      ;;
    *)
      log_info "User declined: $prompt"
      return 1
      ;;
  esac
}

# Display success banner with connection details (UX-010)
# Args: $1 - IP address, $2 - RDP port, $3 - username, $4 - password
show_success_banner() {
  local ip_address="$1"
  local rdp_port="${2:-3389}"
  local username="$3"
  local password="$4"
  
  log_separator "="
  log_info ""
  log_info "=============================================================================="
  log_info "                                                                              "
  log_info "                       [OK] PROVISIONING SUCCESSFUL                           "
  log_info "                                                                              "
  log_info "=============================================================================="
  log_info ""
  log_info "Your VPS developer workstation is ready!"
  log_info ""
  log_info "CONNECTION DETAILS (copy-paste ready):"
  log_info "------------------------------------------------------------------------------"
  log_info ""
  log_info "  RDP Connection:"
  log_info "    Host:     ${ip_address}"
  log_info "    Port:     ${rdp_port}"
  log_info "    Username: ${username}"
  log_info "    Password: [REDACTED]"
  log_info ""
  log_info "  [WARN] IMPORTANT: Change your password on first login!"
  log_info ""
  log_info "  Connection String (for RDP clients):"
  log_info "    ${username}@${ip_address}:${rdp_port}"
  log_info ""
  log_info "------------------------------------------------------------------------------"
  log_info ""
  log_info "INSTALLED IDEs:"
  log_info "  • Visual Studio Code"
  log_info "  • Cursor"
  log_info "  • Antigravity"
  log_info ""
  log_info "NEXT STEPS:"
  log_info "  1. Connect via RDP using the credentials above"
  log_info "  2. Change your password when prompted"
  log_info "  3. Launch any IDE from the Applications menu"
  log_info "  4. Start coding!"
  log_info ""
  log_info "For support, see: /usr/share/doc/vps-provision/README.md"
  log_info ""
  log_separator "="
  
  # UX-024: Redact password in logs but display to terminal once
  if [[ -t 1 ]]; then
    echo ""
    echo "Your temporary password (SAVE THIS NOW, will not be shown again):"
    echo "  ${password}"
    echo ""
  fi
}

# Validate input with specific feedback (UX-012)
# Args: $1 - input value, $2 - validation pattern, $3 - field name, $4 - requirements
# Returns: 0 if valid, 1 with specific feedback otherwise
validate_input() {
  local value="$1"
  local pattern="$2"
  local field_name="$3"
  local requirements="$4"
  
  if [[ ! "$value" =~ $pattern ]]; then
    log_error "[ERROR] Invalid ${field_name}: ${value}"
    log_error " > ${requirements}"
    return 1
  fi
  
  log_debug "${field_name} validated successfully"
  return 0
}

# Validate username format (UX-012)
# Args: $1 - username
# Returns: 0 if valid, 1 with feedback otherwise
validate_username() {
  local username="$1"
  validate_input \
    "$username" \
    '^[a-z][a-z0-9_-]{2,31}$' \
    "username" \
    "Must start with lowercase letter, contain only lowercase letters, numbers, underscore, hyphen (3-32 characters)"
}

# Validate password complexity (UX-012, SEC-001)
# Args: $1 - password
# Returns: 0 if valid, 1 with feedback otherwise
validate_password() {
  local password="$1"
  local min_length=16
  
  if [[ ${#password} -lt $min_length ]]; then
    log_error "[ERROR] Password too short: ${#password} characters"
    log_error " > Password must be at least ${min_length} characters long"
    return 1
  fi
  
  if ! [[ "$password" =~ [A-Z] ]]; then
    log_error "[ERROR] Password missing uppercase letter"
    log_error " > Password must contain at least one uppercase letter (A-Z)"
    return 1
  fi
  
  if ! [[ "$password" =~ [a-z] ]]; then
    log_error "[ERROR] Password missing lowercase letter"
    log_error " > Password must contain at least one lowercase letter (a-z)"
    return 1
  fi
  
  if ! [[ "$password" =~ [0-9] ]]; then
    log_error "[ERROR] Password missing digit"
    log_error " > Password must contain at least one digit (0-9)"
    return 1
  fi
  
  if ! [[ "$password" =~ [^a-zA-Z0-9] ]]; then
    log_error "[ERROR] Password missing special character"
    log_error " > Password must contain at least one special character (!@#$%^&*)"
    return 1
  fi
  
  log_debug "Password meets complexity requirements"
  return 0
}

# Validate IP address format (UX-012)
# Args: $1 - IP address
# Returns: 0 if valid, 1 with feedback otherwise
validate_ip_address() {
  local ip="$1"
  local ip_pattern='^([0-9]{1,3}\.){3}[0-9]{1,3}$'
  
  if ! [[ "$ip" =~ $ip_pattern ]]; then
    log_error "[ERROR] Invalid IP address format: ${ip}"
    log_error " > Must be in format: xxx.xxx.xxx.xxx (e.g., 192.168.1.1)"
    return 1
  fi
  
  # Validate octets are 0-255
  local IFS='.'
  read -ra octets <<< "$ip"
  for octet in "${octets[@]}"; do
    if [[ $octet -lt 0 || $octet -gt 255 ]]; then
      log_error "[ERROR] Invalid IP address octet: ${octet}"
      log_error " > Each octet must be between 0 and 255"
      return 1
    fi
  done
  
  log_debug "IP address validated successfully"
  return 0
}

# Validate port number (UX-012)
# Args: $1 - port number
# Returns: 0 if valid, 1 with feedback otherwise
validate_port() {
  local port="$1"
  
  if ! [[ "$port" =~ ^[0-9]+$ ]]; then
    log_error "[ERROR] Invalid port number: ${port}"
    log_error " > Port must be a number"
    return 1
  fi
  
  if [[ $port -lt 1 || $port -gt 65535 ]]; then
    log_error "[ERROR] Port number out of range: ${port}"
    log_error " > Port must be between 1 and 65535"
    return 1
  fi
  
  log_debug "Port validated successfully"
  return 0
}

# Show progress indicator for long-running operations
# Args: $1 - message, $2 - duration estimate (optional)
show_progress_start() {
  local message="$1"
  local duration="${2:-}"
  
  if [[ -n "$duration" ]]; then
    log_info "$message (estimated: ${duration}s)"
  else
    log_info "$message"
  fi
}

# Show progress completion
# Args: $1 - message, $2 - actual duration (optional)
show_progress_complete() {
  local message="$1"
  local duration="${2:-}"
  
  if [[ -n "$duration" ]]; then
    log_info "✓ $message (completed in ${duration}s)"
  else
    log_info "✓ $message"
  fi
}

# Show error with actionable suggestion (UX-007, UX-008)
# Args: $1 - severity, $2 - message, $3 - suggestion
show_error() {
  local severity="$1"
  local message="$2"
  local suggestion="$3"
  
  if [[ "$severity" == "FATAL" ]]; then
    log_fatal "[$severity] $message"
  elif [[ "$severity" == "ERROR" ]]; then
    log_error "[$severity] $message"
  else
    log_warning "[$severity] $message"
  fi
  
  if [[ -n "$suggestion" ]]; then
    log_error " > $suggestion"
  fi
}

# Initialize UX system
ux_init() {
  ux_detect_interactive
  ux_detect_terminal_width
  log_debug "UX system initialized (interactive: ${UX_INTERACTIVE}, width: ${UX_TERMINAL_WIDTH})"
}

# Export functions
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "This script should be sourced, not executed directly" >&2
  exit 1
fi
