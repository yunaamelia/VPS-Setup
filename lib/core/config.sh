#!/bin/bash
# config.sh - Configuration management for VPS provisioning
# Reads config files, validates values, provides config access functions

set -euo pipefail

# Prevent multiple sourcing
if [[ -n "${_CONFIG_SH_LOADED:-}" ]]; then
  return 0
fi
readonly _CONFIG_SH_LOADED=1

# Source logger for output
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/core/logger.sh
# shellcheck disable=SC1091  # Intentional sourcing - path resolved at runtime
source "${SCRIPT_DIR}/logger.sh"

# Configuration file paths (only set if not already set)
if [[ -z "${SYSTEM_CONFIG:-}" ]]; then
  readonly SYSTEM_CONFIG="/etc/vps-provision/default.conf"
fi
if [[ -z "${USER_CONFIG:-}" ]]; then
  readonly USER_CONFIG="${HOME}/.vps-provision.conf"
fi
if [[ -z "${PROJECT_CONFIG:-}" ]]; then
  PROJECT_CONFIG="$(dirname "$SCRIPT_DIR")/../config/default.conf"
  readonly PROJECT_CONFIG
fi

# Configuration variables (will be populated from config files)
declare -A CONFIG

# Initialize configuration system
# Loads configuration from files in priority order
config_init() {
  log_debug "Initializing configuration system"
  
  # Load in priority order (later files override earlier ones)
  local config_files=("$PROJECT_CONFIG" "$SYSTEM_CONFIG" "$USER_CONFIG")
  local file
  local loaded=0
  
  for file in "${config_files[@]}"; do
    if [[ -f "$file" ]]; then
      config_load_file "$file"
      loaded=$((loaded + 1))
    fi
  done
  
  if [[ $loaded -eq 0 ]]; then
    log_warning "No configuration files found"
    return 1
  fi
  
  log_debug "Configuration loaded from $loaded file(s)"
  log_debug "Configuration loaded from $loaded file(s)"
  return 0
}

# Alias for config_init to match vps-provision calls
config_load_default() {
  config_init
}

# Alias for config_load_file to match vps-provision calls
config_load() {
  config_load_file "$1"
}

# Load configuration from a file
# Args: $1 - config file path
config_load_file() {
  local config_file="$1"
  
  if [[ ! -f "$config_file" ]]; then
    log_debug "Config file not found: $config_file"
    return 1
  fi
  
  if [[ ! -r "$config_file" ]]; then
    log_error "Config file not readable: $config_file"
    return 1
  fi
  
  log_debug "Loading config from: $config_file"
  
  # Temporarily disable unbound variable check for CONFIG array assignments
  set +u
  
  # Read config file line by line
  while IFS='=' read -r key value; do
    # Skip comments and empty lines
    [[ "$key" =~ ^[[:space:]]*# ]] && continue
    [[ -z "$key" ]] && continue
    
    # Trim whitespace
    key=$(echo "$key" | xargs)
    value=$(echo "$value" | xargs)
    
    # Remove quotes from value if present
    value="${value%\"}"
    value="${value#\"}"
    
    # Store in CONFIG associative array (only if key is not empty)
    if [[ -n "$key" ]]; then
      CONFIG["$key"]="$value"
    fi
    
  done < "$config_file"
  
  # Re-enable unbound variable check
  set -u
  
  log_debug "Loaded configuration from: $config_file"
  return 0
}

# Get configuration value
# Args: $1 - key, $2 - default value (optional)
# Returns: configuration value or default
config_get() {
  local key="$1"
  local default="${2:-}"
  
  if [[ -n "${CONFIG[$key]:-}" ]]; then
    echo "${CONFIG[$key]}"
  else
    echo "$default"
  fi
}

# Set configuration value
# Args: $1 - key, $2 - value
config_set() {
  local key="$1"
  local value="$2"
  
  if [[ -z "$key" ]]; then
    log_error "Config key cannot be empty"
    return 1
  fi
  
  set +u
  CONFIG["$key"]="$value"
  set -u
  
  log_debug "Config set: $key=$value"
}

# Check if configuration key exists
# Args: $1 - key
# Returns: 0 if exists, 1 if not
config_has() {
  local key="$1"
  
  if [[ -n "${CONFIG[$key]:-}" ]]; then
    return 0
  fi
  
  return 1
}

# Validate configuration values
# Returns: 0 if valid, 1 if invalid
config_validate() {
  log_debug "Validating configuration"
  
  local errors=0
  
  # Validate username format
  local username
  username=$(config_get "DEVELOPER_USERNAME" "devuser")
  if [[ ! "$username" =~ ^[a-z][a-z0-9_-]{2,31}$ ]]; then
    log_error "Invalid username format: $username"
    errors=$((errors + 1))
  fi
  
  # Validate ports
  local ports=("RDP_PORT" "SSH_PORT")
  local port_key
  for port_key in "${ports[@]}"; do
    local port
    port=$(config_get "$port_key" "0")
    if [[ ! "$port" =~ ^[0-9]+$ ]] || [[ $port -lt 1 ]] || [[ $port -gt 65535 ]]; then
      log_error "Invalid port number for $port_key: $port"
      errors=$((errors + 1))
    fi
  done
  
  # Validate log level
  local log_level
  log_level=$(config_get "LOG_LEVEL" "INFO")
  if [[ ! "$log_level" =~ ^(DEBUG|INFO|WARNING|ERROR)$ ]]; then
    log_error "Invalid log level: $log_level"
    errors=$((errors + 1))
  fi
  
  # Validate boolean values
  local bool_keys=("ENABLE_FIREWALL" "ENABLE_COLORS" "FORCE_MODE" "DRY_RUN")
  local bool_key
  for bool_key in "${bool_keys[@]}"; do
    local bool_value
    bool_value=$(config_get "$bool_key" "true")
    if [[ ! "$bool_value" =~ ^(true|false)$ ]]; then
      log_error "Invalid boolean value for $bool_key: $bool_value"
      errors=$((errors + 1))
    fi
  done
  
  # Validate numeric values
  local min_ram
  min_ram=$(config_get "MIN_RAM_GB" "2")
  if [[ ! "$min_ram" =~ ^[0-9]+$ ]] || [[ $min_ram -lt 1 ]]; then
    log_error "Invalid minimum RAM: $min_ram"
    errors=$((errors + 1))
  fi
  
  if [[ $errors -gt 0 ]]; then
    log_error "Configuration validation failed with $errors error(s)"
    return 1
  fi
  
  log_debug "Configuration validation passed"
  return 0
}

# Display current configuration
config_show() {
  log_info "Current Configuration:"
  
  local key
  for key in "${!CONFIG[@]}"; do
    # Don't show sensitive values in logs
    if [[ "$key" =~ PASSWORD|SECRET|KEY|TOKEN ]]; then
      log_info "  $key=[REDACTED]"
    else
      log_info "  $key=${CONFIG[$key]}"
    fi
  done
}

# Load configuration from command-line arguments
# Args: $@ - command-line arguments
config_load_from_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --username)
        config_set "DEVELOPER_USERNAME" "$2"
        shift 2
        ;;
      --log-level)
        config_set "LOG_LEVEL" "$2"
        shift 2
        ;;
      --config)
        config_load_file "$2"
        shift 2
        ;;
      --dry-run)
        config_set "DRY_RUN" "true"
        shift
        ;;
      --force)
        config_set "FORCE_MODE" "true"
        shift
        ;;
      --resume)
        config_set "RESUME_MODE" "true"
        shift
        ;;
      -y|--yes)
        config_set "AUTO_YES" "true"
        shift
        ;;
      -v|--verbose)
        config_set "VERBOSE" "true"
        config_set "LOG_LEVEL" "DEBUG"
        shift
        ;;
      *)
        # Unknown option, skip
        shift
        ;;
    esac
  done
}

# Get boolean config value
# Args: $1 - key, $2 - default (true/false)
# Returns: true or false
config_get_bool() {
  local key="$1"
  local default="${2:-false}"
  local value
  
  value=$(config_get "$key" "$default")
  
  case "${value,,}" in
    true|yes|1|on)
      echo "true"
      ;;
    *)
      echo "false"
      ;;
  esac
}

# Get integer config value
# Args: $1 - key, $2 - default
# Returns: integer value
config_get_int() {
  local key="$1"
  local default="${2:-0}"
  local value
  
  value=$(config_get "$key" "$default")
  
  if [[ "$value" =~ ^[0-9]+$ ]]; then
    echo "$value"
  else
    echo "$default"
  fi
}

# Export configuration as environment variables
config_export_env() {
  local key
  for key in "${!CONFIG[@]}"; do
    export "$key=${CONFIG[$key]}"
  done
  
  log_debug "Configuration exported to environment"
}

# Alias for config_has
config_has_key() {
  config_has "$1"
}

# Validate required configuration keys exist
# Args: $@ - list of required keys
config_validate_required() {
  local errors=0
  local key
  
  for key in "$@"; do
    if ! config_has_key "$key"; then
      log_error "Required configuration key missing: $key"
      errors=$((errors + 1))
    fi
  done
  
  if [[ $errors -gt 0 ]]; then
    return 1
  fi
  
  return 0
}

# Validate boolean configuration value
# Args: $1 - key
config_validate_boolean() {
  local key="$1"
  local value
  
  value=$(config_get "$key")
  
  if [[ ! "$value" =~ ^(true|false|yes|no|1|0|on|off)$ ]]; then
    log_error "Invalid boolean value for $key: $value"
    return 1
  fi
  
  return 0
}

# Validate integer configuration value
# Args: $1 - key
config_validate_integer() {
  local key="$1"
  local value
  
  value=$(config_get "$key")
  
  if [[ ! "$value" =~ ^[0-9]+$ ]]; then
    log_error "Invalid integer value for $key: $value"
    return 1
  fi
  
  return 0
}

# Validate value is within range
# Args: $1 - key, $2 - min, $3 - max
config_validate_range() {
  local key="$1"
  local min="$2"
  local max="$3"
  local value
  
  value=$(config_get "$key")
  
  if [[ ! "$value" =~ ^[0-9]+$ ]]; then
    log_error "Value for $key is not a number: $value"
    return 1
  fi
  
  if [[ $value -lt $min ]] || [[ $value -gt $max ]]; then
    log_error "Value for $key out of range [$min-$max]: $value"
    return 1
  fi
  
  return 0
}

# Export configuration as key=value format
config_export() {
  local key
  for key in "${!CONFIG[@]}"; do
    echo "$key=\"${CONFIG[$key]}\""
  done
}

# Export configuration as JSON
config_export_json() {
  local first=true
  
  echo "{"
  for key in "${!CONFIG[@]}"; do
    if [[ "$first" == "true" ]]; then
      first=false
    else
      echo ","
    fi
    
    # Escape quotes in value
    local value="${CONFIG[$key]}"
    value="${value//\"/\\\"}"
    
    echo -n "  \"$key\": \"$value\""
  done
  echo ""
  echo "}"
}

# Save configuration to file
# Args: $1 - output file path
config_save() {
  local output_file="$1"
  
  config_export > "$output_file" || {
    log_error "Failed to save configuration to: $output_file"
    return 1
  }
  
  log_info "Configuration saved to: $output_file"
  return 0
}

# Reload configuration from files
config_reload() {
  # Clear existing configuration
  unset CONFIG
  declare -gA CONFIG
  
  # Reload from files
  config_init
}

# List all configuration keys
config_list_keys() {
  for key in "${!CONFIG[@]}"; do
    echo "$key"
  done
}

# Clear all configuration
config_clear() {
  unset CONFIG
  declare -gA CONFIG
  log_debug "Configuration cleared"
}
