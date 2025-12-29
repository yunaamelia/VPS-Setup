#!/bin/bash
# validator.sh - Pre-flight validation for VPS provisioning
# Checks OS version, resources, network connectivity, and package repositories

set -euo pipefail

# Source dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/core/logger.sh
source "${SCRIPT_DIR}/logger.sh"

# Validation results
VALIDATION_ERRORS=0
VALIDATION_WARNINGS=0

# Initialize validator
validator_init() {
  log_debug "Validator initialized"
  VALIDATION_ERRORS=0
  VALIDATION_WARNINGS=0
}

# Check OS version (must be Debian 13)
# Returns: 0 if valid, 1 if invalid
validator_check_os() {
  log_info "Checking OS version..."

  if [[ ! -f /etc/os-release ]]; then
    log_error "Cannot determine OS: /etc/os-release not found"
    VALIDATION_ERRORS=$((VALIDATION_ERRORS + 1))
    return 1
  fi

  # Parse os-release without sourcing to avoid readonly variable conflicts
  local os_id os_version_id os_version_codename
  
  # Extract values using grep and cut to avoid sourcing
  os_id=$(grep -oP '^ID=\K.*' /etc/os-release | tr -d '"')
  os_version_id=$(grep -oP '^VERSION_ID=\K.*' /etc/os-release | tr -d '"')
  os_version_codename=$(grep -oP '^VERSION_CODENAME=\K.*' /etc/os-release | tr -d '"' || echo "unknown")

  if [[ "${os_id}" != "debian" ]]; then
    log_error "Unsupported OS: ${os_id:-unknown} (expected: debian)"
    VALIDATION_ERRORS=$((VALIDATION_ERRORS + 1))
    return 1
  fi

  if [[ "${os_version_id}" != "13" ]]; then
    log_error "Unsupported Debian version: ${os_version_id:-unknown} (expected: 13)"
    VALIDATION_ERRORS=$((VALIDATION_ERRORS + 1))
    return 1
  fi

  log_info "OS check passed: Debian ${os_version_id} (${os_version_codename})"
  return 0
}

# Check RAM availability
# Args: $1 - minimum RAM in GB (default: 2)
# Returns: 0 if sufficient, 1 if insufficient
validator_check_ram() {
  local min_ram_gb="${1:-2}"
  log_info "Checking RAM availability (minimum: ${min_ram_gb}GB)..."

  local total_ram_kb
  total_ram_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
  local total_ram_gb
  total_ram_gb=$(awk "BEGIN {printf \"%.2f\", $total_ram_kb / 1024 / 1024}")

  log_info "Available RAM: ${total_ram_gb}GB"

  # Convert to integer comparison (multiply by 100 to handle decimals)
  local total_ram_int
  total_ram_int=$(awk "BEGIN {printf \"%.0f\", $total_ram_gb * 100}")
  local min_ram_int
  min_ram_int=$(awk "BEGIN {printf \"%.0f\", $min_ram_gb * 100}")

  if ((total_ram_int < min_ram_int)); then
    log_error "Insufficient RAM: ${total_ram_gb}GB < ${min_ram_gb}GB"
    VALIDATION_ERRORS=$((VALIDATION_ERRORS + 1))
    return 1
  fi

  log_info "RAM check passed"
  return 0
}

# Check CPU cores
# Args: $1 - minimum CPU cores (default: 1)
# Returns: 0 if sufficient, 1 if insufficient
validator_check_cpu() {
  local min_cpu="${1:-1}"
  log_info "Checking CPU cores (minimum: $min_cpu)..."

  local cpu_count
  cpu_count=$(nproc)

  log_info "CPU cores: $cpu_count"

  if [[ $cpu_count -lt $min_cpu ]]; then
    log_error "Insufficient CPU cores: $cpu_count < $min_cpu"
    VALIDATION_ERRORS=$((VALIDATION_ERRORS + 1))
    return 1
  fi

  log_info "CPU check passed"
  return 0
}

# Check disk space
# Args: $1 - minimum disk space in GB (default: 25)
# Returns: 0 if sufficient, 1 if insufficient
validator_check_disk_space() {
  validator_check_disk "$@"
}

# Check memory (RAM)
# Args: $1 - minimum RAM in GB (default: 2)
# Returns: 0 if sufficient, 1 if insufficient
validator_check_memory() {
  validator_check_ram "$@"
}

# Check disk space
# Args: $1 - minimum disk space in GB (default: 25)
# Returns: 0 if sufficient, 1 if insufficient
validator_check_disk() {
  local min_disk_gb="${1:-25}"
  log_info "Checking disk space (minimum: ${min_disk_gb}GB)..."

  local available_gb
  available_gb=$(df -BG / | tail -1 | awk '{print $4}' | sed 's/G//')

  log_info "Available disk space: ${available_gb}GB"

  if [[ $available_gb -lt $min_disk_gb ]]; then
    log_error "Insufficient disk space: ${available_gb}GB < ${min_disk_gb}GB"
    VALIDATION_ERRORS=$((VALIDATION_ERRORS + 1))
    return 1
  fi

  log_info "Disk space check passed"
  return 0
}

# Check network connectivity
# Returns: 0 if connected, 1 if not
validator_check_network() {
  log_info "Checking network connectivity..."

  local test_hosts=("8.8.8.8" "1.1.1.1")
  local connected=false

  for host in "${test_hosts[@]}"; do
    # Try ping with strict timeout (1 second, 1 packet)
    if timeout 3 ping -c 1 -W 1 "$host" &>/dev/null; then
      log_info "Network check passed: reachable $host"
      connected=true
      break
    fi
    
    # Fallback: try curl if ping fails
    if command -v curl &>/dev/null; then
      if timeout 3 curl -s --connect-timeout 2 "http://$host" &>/dev/null; then
        log_info "Network check passed: reachable $host (via curl)"
        connected=true
        break
      fi
    fi
  done

  if [[ "$connected" == "false" ]]; then
    log_error "Network connectivity check failed"
    log_error "Unable to reach 8.8.8.8 or 1.1.1.1"
    VALIDATION_ERRORS=$((VALIDATION_ERRORS + 1))
    return 1
  fi

  return 0
}

# Check DNS resolution
# Returns: 0 if working, 1 if not
validator_check_dns() {
  log_info "Checking DNS resolution..."

  if host google.com &>/dev/null; then
    log_info "DNS check passed"
    return 0
  fi

  log_error "DNS resolution failed"
  VALIDATION_ERRORS=$((VALIDATION_ERRORS + 1))
  return 1
}

# Check package repository accessibility
# Returns: 0 if accessible, 1 if not
validator_check_repositories() {
  log_info "Checking package repositories..."

  if ! command -v apt-get &>/dev/null; then
    log_error "apt-get command not found"
    VALIDATION_ERRORS=$((VALIDATION_ERRORS + 1))
    return 1
  fi

  log_info "Updating package lists..."
  if apt-get update &>/dev/null; then
    log_info "Repository check passed"
    return 0
  fi

  log_error "Failed to update package lists"
  log_error "Please check repository configuration in /etc/apt/sources.list"
  VALIDATION_ERRORS=$((VALIDATION_ERRORS + 1))
  return 1
}

# Check if running as root
# Returns: 0 if root, 1 if not
validator_check_root() {
  log_info "Checking user privileges..."

  if [[ $EUID -ne 0 ]]; then
    log_error "This script must be run as root"
    VALIDATION_ERRORS=$((VALIDATION_ERRORS + 1))
    return 1
  fi

  log_info "Root privileges confirmed"
  return 0
}

# Check for conflicting processes
# Returns: 0 if no conflicts, 1 if conflicts found
validator_check_conflicts() {
  log_info "Checking for conflicting processes..."

  # Check if another provisioning process is running
  if [[ -f /var/lock/vps-provision.lock ]]; then
    local lock_pid
    lock_pid=$(cat /var/lock/vps-provision.lock 2>/dev/null || echo "")

    if [[ -n "$lock_pid" ]] && kill -0 "$lock_pid" 2>/dev/null; then
      log_error "Another provisioning process is running (PID: $lock_pid)"
      VALIDATION_ERRORS=$((VALIDATION_ERRORS + 1))
      return 1
    else
      log_warning "Stale lock file found, removing"
      rm -f /var/lock/vps-provision.lock
    fi
  fi

  log_info "No conflicting processes found"
  return 0
}

# Run all validation checks
# Returns: 0 if all passed, 1 if any failed
validator_run_all() {
  log_section "Pre-Flight Validation"

  validator_init

  # Critical checks (must pass)
  validator_check_root
  validator_check_os
  validator_check_ram 2
  validator_check_cpu 1
  validator_check_disk 25
  validator_check_network
  validator_check_dns
  validator_check_repositories
  validator_check_conflicts

  log_separator "="

  if [[ $VALIDATION_ERRORS -gt 0 ]]; then
    log_error "Validation failed with $VALIDATION_ERRORS error(s)"
    log_error "Please resolve the issues above before proceeding"
    return 1
  fi

  if [[ $VALIDATION_WARNINGS -gt 0 ]]; then
    log_warning "Validation passed with $VALIDATION_WARNINGS warning(s)"
  else
    log_info "All validation checks passed"
  fi

  return 0
}

# Get validation error count
validator_get_errors() {
  echo "$VALIDATION_ERRORS"
}

# Get validation warning count
validator_get_warnings() {
  echo "$VALIDATION_WARNINGS"
}

# Check network bandwidth (basic test)
# Returns: 0 if adequate, 1 if too slow
validator_check_bandwidth() {
  log_info "Checking network bandwidth..."

  local test_url="http://speedtest.tele2.net/1MB.zip"
  local download_time
  local download_speed

  # Download 1MB test file and measure time
  download_time=$(curl -o /dev/null -s -w '%{time_total}' "$test_url" 2>/dev/null || echo "0")

  if [[ "$download_time" == "0" ]]; then
    log_warning "Bandwidth test failed (unable to reach test server)"
    VALIDATION_WARNINGS=$((VALIDATION_WARNINGS + 1))
    return 0 # Non-critical, continue anyway
  fi

  # Calculate speed in KB/s (1MB / time)
  download_speed=$(awk "BEGIN {printf \"%.2f\", 1024 / $download_time}")

  log_info "Download speed: ${download_speed} KB/s"

  # Warn if slower than 100 KB/s
  if (($(echo "$download_speed < 100" | bc -l))); then
    log_warning "Network bandwidth is slow (<100 KB/s), provisioning may take longer"
    VALIDATION_WARNINGS=$((VALIDATION_WARNINGS + 1))
  fi

  return 0
}

# Monitor disk space during provisioning
# Args: $1 - critical threshold in GB (default: 5)
# Returns: 0 if OK, 1 if critical
validator_monitor_disk_space() {
  local critical_gb="${1:-5}"

  local available_gb
  available_gb=$(df -BG / | tail -1 | awk '{print $4}' | sed 's/G//')

  if [[ $available_gb -lt $critical_gb ]]; then
    log_error "Critical disk space: ${available_gb}GB remaining"
    log_error "Attempting to free space with apt-get clean..."

    if apt-get clean &>/dev/null; then
      # Check again after cleanup
      available_gb=$(df -BG / | tail -1 | awk '{print $4}' | sed 's/G//')
      log_info "After cleanup: ${available_gb}GB available"

      if [[ $available_gb -lt $critical_gb ]]; then
        log_error "Still insufficient disk space after cleanup"
        return 1
      fi
    else
      log_error "Failed to run apt-get clean"
      return 1
    fi
  fi

  return 0
}

# Get current memory usage percentage
validator_get_memory_usage() {
  local total
  local used
  local percentage

  total=$(grep MemTotal /proc/meminfo | awk '{print $2}')
  used=$(grep -E 'MemTotal|MemAvailable' /proc/meminfo | awk '{total+=$2} END {print total}')

  percentage=$(awk "BEGIN {printf \"%.1f\", ($used / $total) * 100}")

  echo "$percentage"
}

# Check if system resources are under stress
# Returns: 0 if OK, 1 if stressed
validator_check_system_load() {
  log_debug "Checking system load..."

  local load_avg
  load_avg=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | sed 's/,//')

  local cpu_count
  cpu_count=$(nproc)

  # Warn if load average exceeds CPU count
  if (($(echo "$load_avg > $cpu_count" | bc -l))); then
    log_warning "High system load: $load_avg (CPUs: $cpu_count)"
    VALIDATION_WARNINGS=$((VALIDATION_WARNINGS + 1))
    return 1
  fi

  log_debug "System load: $load_avg"
  return 0
}

# Check if running inside a container (Docker, LXC, etc.)
# Returns: 0 if in container, 1 if not
validator_is_container() {
  log_debug "Checking for container environment..."

  # 1. Check for /.dockerenv
  if [[ -f /.dockerenv ]]; then
    log_debug "Detected Docker via /.dockerenv"
    return 0
  fi

  # 2. Check for container environment variable
  if [[ -n "${container:-}" ]]; then
    log_debug "Detected container via \$container variable: ${container}"
    return 0
  fi

  # 3. Check /proc/1/cgroup for docker/lxc/kubepods patterns
  if [[ -f /proc/1/cgroup ]] && grep -qE "docker|lxc|kubepods" /proc/1/cgroup; then
    log_debug "Detected container via /proc/1/cgroup"
    return 0
  fi

  # 4. Check for /run/.containerenv (Podman)
  if [[ -f /run/.containerenv ]]; then
    log_debug "Detected Podman via /run/.containerenv"
    return 0
  fi

  # 5. Use systemd-detect-virt if available
  if command -v systemd-detect-virt &>/dev/null; then
    if systemd-detect-virt --container --quiet; then
      log_debug "Detected container via systemd-detect-virt"
      return 0
    fi
  fi

  log_debug "No container environment detected"
  return 1
}

# Enhanced pre-flight check with resource validation
# Args: $1 - min RAM GB, $2 - min disk GB
# Returns: 0 if passed, 1 if failed
validator_preflight_resources() {
  local min_ram="${1:-2}"
  local min_disk="${2:-25}"

  log_info "Performing resource pre-flight checks..."

  local errors=0

  # Check RAM
  if ! validator_check_ram "$min_ram"; then
    errors=$((errors + 1))
  fi

  # Check disk
  if ! validator_check_disk "$min_disk"; then
    errors=$((errors + 1))
  fi

  # Check bandwidth
  validator_check_bandwidth || true # Non-critical

  # Check system load
  validator_check_system_load || true # Non-critical

  if [[ $errors -gt 0 ]]; then
    log_error "Resource pre-flight check failed with $errors error(s)"
    return 1
  fi

  log_info "Resource pre-flight check passed"
  return 0
}

# Run all validation checks
# Returns: 0 if all checks pass, 1 if any check fails
validator_check_all() {
  log_info "Running comprehensive pre-flight validation..."
  
  validator_init
  
  local errors=0
  
  # Check OS
  if ! validator_check_os; then
    errors=$((errors + 1))
  fi
  
  # Check RAM (minimum 2GB)
  if ! validator_check_ram 2; then
    errors=$((errors + 1))
  fi
  
  # Check CPU (minimum 1 core)
  if ! validator_check_cpu 1; then
    errors=$((errors + 1))
  fi
  
  # Check disk (minimum 25GB)
  if ! validator_check_disk 25; then
    errors=$((errors + 1))
  fi
  
  # Check network connectivity
  if ! validator_check_network; then
    errors=$((errors + 1))
  fi
  
  # Check root privileges
  if ! validator_check_root; then
    errors=$((errors + 1))
  fi
  
  # Report results
  if [[ $errors -gt 0 ]]; then
    log_error "Validation failed with $errors error(s)"
    return 1
  fi
  
  log_info "All validation checks passed"
  return 0
}
