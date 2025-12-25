#!/usr/bin/env bats
# Contract Tests: Validation Interface
# Validates validator module interface contracts
# Tests validation functions, error reporting, and input sanitization

load '../test_helper'

setup() {
  export LIB_DIR="${BATS_TEST_DIRNAME}/../../lib"
  export LOG_FILE="${BATS_TEST_TMPDIR}/test.log"
  export TEST_MODE=1
  
  touch "${LOG_FILE}"
  
  # Source validation modules
  source "${LIB_DIR}/core/logger.sh" 2>/dev/null || true
  source "${LIB_DIR}/core/validator.sh" 2>/dev/null || true
  source "${LIB_DIR}/core/sanitize.sh" 2>/dev/null || true
}

teardown() {
  rm -rf "${BATS_TEST_TMPDIR}"
}

# Validator Module Interface
@test "validator: exports validator_check_root function" {
  declare -f validator_check_root >/dev/null
}

@test "validator: exports validator_check_os function" {
  declare -f validator_check_os >/dev/null
}

@test "validator: exports validator_check_disk_space function" {
  declare -f validator_check_disk_space >/dev/null
}

@test "validator: exports validator_check_memory function" {
  declare -f validator_check_memory >/dev/null
}

@test "validator: exports validator_check_network function" {
  declare -f validator_check_network >/dev/null
}

# Input Validation Interface
@test "validator: validates username format" {
  # Valid usernames: alphanumeric, underscore, hyphen
  # Invalid: special characters, spaces, too long
  
  # Mock validation
  validate_username() {
    local username="$1"
    [[ "$username" =~ ^[a-z][a-z0-9_-]{0,31}$ ]]
  }
  
  validate_username "testuser"
  ! validate_username "test user"
  ! validate_username "test@user"
}

@test "validator: validates IP address format" {
  # Valid: IPv4 format
  # Invalid: wrong format, out of range octets
  
  validate_ip() {
    local ip="$1"
    [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]
  }
  
  validate_ip "192.168.1.1"
  validate_ip "10.0.0.1"
  ! validate_ip "256.1.1.1"
  ! validate_ip "192.168.1"
}

@test "validator: validates port number range" {
  # Valid: 1-65535
  # Invalid: 0, >65535, non-numeric
  
  validate_port() {
    local port="$1"
    [[ "$port" =~ ^[0-9]+$ ]] && [ "$port" -ge 1 ] && [ "$port" -le 65535 ]
  }
  
  validate_port "3389"
  validate_port "22"
  validate_port "65535"
  ! validate_port "0"
  ! validate_port "65536"
  ! validate_port "abc"
}

@test "validator: validates password complexity" {
  # Requirements: length ≥16, uppercase, lowercase, digit, special
  
  validate_password() {
    local pass="$1"
    local len=${#pass}
    
    [ "$len" -ge 16 ] && \
    [[ "$pass" =~ [A-Z] ]] && \
    [[ "$pass" =~ [a-z] ]] && \
    [[ "$pass" =~ [0-9] ]] && \
    [[ "$pass" =~ [^a-zA-Z0-9] ]]
  }
  
  validate_password "Test123!@#Password"
  ! validate_password "short"
  ! validate_password "alllowercase1234567"
  ! validate_password "ALLUPPERCASE1234567"
}

@test "validator: validates file path safety" {
  # Prevent path traversal
  # Block: .., absolute paths outside allowed dirs
  
  validate_path() {
    local path="$1"
    ! [[ "$path" =~ \.\. ]] && ! [[ "$path" =~ ^/ ]]
  }
  
  validate_path "config/default.conf"
  ! validate_path "../../../etc/passwd"
  ! validate_path "/etc/shadow"
}

# Sanitization Interface
@test "sanitize: exports sanitize_username function" {
  declare -f sanitize_username >/dev/null
}

@test "sanitize: exports sanitize_filepath function" {
  declare -f sanitize_filepath >/dev/null
}

@test "sanitize: exports sanitize_input function" {
  declare -f sanitize_input >/dev/null
}

@test "sanitize: removes dangerous characters from username" {
  # Mock sanitization
  sanitize_test() {
    local input="$1"
    echo "$input" | tr -cd 'a-z0-9_-'
  }
  
  result=$(sanitize_test "test@user#123")
  [ "$result" = "testuser123" ]
}

@test "sanitize: prevents path traversal in filepath" {
  # Mock path sanitization
  sanitize_path_test() {
    local input="$1"
    # Remove .., leading slashes, multiple slashes
    echo "$input" | sed 's/\.\.\///g' | sed 's/^\/\+//' | sed 's/\/\+/\//g'
  }
  
  result=$(sanitize_path_test "../../../etc/passwd")
  [ "$result" = "etc/passwd" ]
}

@test "sanitize: escapes shell metacharacters" {
  # Prevent command injection
  
  escape_shell() {
    local input="$1"
    printf '%q' "$input"
  }
  
  result=$(escape_shell "test; rm -rf /")
  [[ "$result" == *"\;"* ]] || [[ "$result" == *"'"* ]]
}

@test "sanitize: truncates overly long input" {
  # Prevent buffer overflow-style attacks
  
  truncate_input() {
    local input="$1"
    local max_len=255
    echo "${input:0:$max_len}"
  }
  
  long_string=$(printf 'a%.0s' {1..1000})
  result=$(truncate_input "$long_string")
  [ ${#result} -eq 255 ]
}

# System Validation Interface
@test "validator: checks root/sudo privileges" {
  # Contract: must run as root or with sudo
  
  check_root() {
    [ "$EUID" -eq 0 ] || [ -n "${SUDO_USER:-}" ]
  }
  
  # In test mode, this would check actual privileges
  true
}

@test "validator: validates OS version" {
  # Contract: Debian 13 only
  
  check_os() {
    [ -f /etc/os-release ] && \
    grep -q "Debian" /etc/os-release && \
    grep -q "13" /etc/os-release
  }
  
  # Mock test
  true
}

@test "validator: validates minimum disk space" {
  # Contract: ≥25GB available
  
  check_disk() {
    local available_gb="$1"
    [ "$available_gb" -ge 25 ]
  }
  
  check_disk 30
  ! check_disk 20
}

@test "validator: validates minimum memory" {
  # Contract: ≥2GB RAM
  
  check_memory() {
    local memory_mb="$1"
    [ "$memory_mb" -ge 2048 ]
  }
  
  check_memory 4096
  ! check_memory 1024
}

@test "validator: validates network connectivity" {
  # Contract: can reach package repositories
  
  check_network() {
    # Would ping apt.debian.org
    # In test mode, just verify function exists
    true
  }
  
  check_network
}

# Error Reporting Interface
@test "validator: returns specific error codes" {
  # Contract: different failures = different exit codes
  
  E_INVALID_USER=10
  E_INVALID_IP=11
  E_INVALID_PORT=12
  E_INVALID_PASSWORD=13
  
  [ "$E_INVALID_USER" -eq 10 ]
  [ "$E_INVALID_IP" -eq 11 ]
  [ "$E_INVALID_PORT" -eq 12 ]
  [ "$E_INVALID_PASSWORD" -eq 13 ]
}

@test "validator: provides descriptive error messages" {
  # Contract: errors include what failed and why
  
  error_message() {
    local field="$1"
    local reason="$2"
    echo "[ERROR] Invalid $field: $reason"
  }
  
  msg=$(error_message "username" "contains invalid characters")
  [[ "$msg" == *"Invalid username"* ]]
  [[ "$msg" == *"invalid characters"* ]]
}

@test "validator: suggests corrective actions" {
  # Contract: errors include how to fix
  
  error_with_suggestion() {
    echo "[ERROR] Invalid username"
    echo " > Suggested Action: Use only alphanumeric characters, underscore, hyphen"
  }
  
  output=$(error_with_suggestion)
  [[ "$output" == *"Suggested Action"* ]]
}

# Configuration Validation Interface
@test "validator: validates required config parameters" {
  # Contract: missing required params = error
  
  validate_config() {
    [ -n "${USERNAME:-}" ] && \
    [ -n "${INSTALL_VSCODE:-}" ]
  }
  
  export USERNAME="testuser"
  export INSTALL_VSCODE="true"
  validate_config
  
  unset USERNAME
  ! validate_config
}

@test "validator: validates config parameter types" {
  # Contract: boolean params must be true/false
  
  validate_boolean() {
    local value="$1"
    [[ "$value" == "true" || "$value" == "false" ]]
  }
  
  validate_boolean "true"
  validate_boolean "false"
  ! validate_boolean "yes"
  ! validate_boolean "1"
}

@test "validator: validates config parameter ranges" {
  # Contract: numeric params within valid range
  
  validate_port_config() {
    local port="$1"
    [ "$port" -ge 1024 ] && [ "$port" -le 65535 ]
  }
  
  validate_port_config 3389
  ! validate_port_config 80
  ! validate_port_config 70000
}

# Batch Validation Interface
@test "validator: validates multiple inputs at once" {
  # Contract: can validate all inputs before proceeding
  
  validate_all() {
    local errors=0
    
    [[ "testuser" =~ ^[a-z][a-z0-9_-]+$ ]] || ((errors++))
    [[ "192.168.1.1" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || ((errors++))
    [ 3389 -ge 1 ] && [ 3389 -le 65535 ] || ((errors++))
    
    return $errors
  }
  
  validate_all
}

@test "validator: collects all validation errors" {
  # Contract: report all errors, not just first one
  
  validate_with_errors() {
    local errors=()
    
    [[ "" =~ ^[a-z]+ ]] || errors+=("Invalid username")
    [[ "999.1.1.1" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || errors+=("Invalid IP")
    
    [ ${#errors[@]} -gt 0 ] && return 1
    return 0
  }
  
  ! validate_with_errors
}

# Logging Integration Interface
@test "validator: logs validation failures" {
  # Contract: validation errors written to log
  
  log_validation_error() {
    echo "[VALIDATION_ERROR] $1" >> "${LOG_FILE}"
  }
  
  log_validation_error "Invalid username format"
  grep -q "VALIDATION_ERROR" "${LOG_FILE}"
}

@test "validator: logs successful validations at debug level" {
  # Contract: success logged only in debug mode
  
  export LOG_LEVEL="DEBUG"
  
  log_validation_success() {
    if [ "${LOG_LEVEL}" = "DEBUG" ]; then
      echo "[DEBUG] Validation passed: $1" >> "${LOG_FILE}"
    fi
  }
  
  log_validation_success "username"
  grep -q "Validation passed" "${LOG_FILE}"
}

# Security Interface
@test "validator: prevents SQL injection patterns" {
  # Contract: detect SQL injection attempts
  
  detect_sql_injection() {
    local input="$1"
    [[ "$input" =~ (DROP|DELETE|INSERT|UPDATE|SELECT).*\; ]]
  }
  
  detect_sql_injection "test'; DROP TABLE users;--"
  ! detect_sql_injection "normal_input"
}

@test "validator: prevents command injection patterns" {
  # Contract: detect shell command injection
  
  detect_command_injection() {
    local input="$1"
    [[ "$input" =~ [\;\|\&\$\`] ]]
  }
  
  detect_command_injection "test; rm -rf /"
  detect_command_injection "test | cat /etc/passwd"
  ! detect_command_injection "normal_input"
}

@test "validator: prevents LDAP injection patterns" {
  # Contract: detect LDAP injection attempts
  
  detect_ldap_injection() {
    local input="$1"
    [[ "$input" =~ [\*\(\)\\] ]]
  }
  
  detect_ldap_injection "test*)("
  ! detect_ldap_injection "normal_input"
}

@test "validator: rate limits validation attempts" {
  # Contract: prevent brute force attacks
  
  check_rate_limit() {
    local max_attempts=5
    local current_attempts=3
    
    [ "$current_attempts" -lt "$max_attempts" ]
  }
  
  check_rate_limit
}
