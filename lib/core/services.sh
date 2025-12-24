#!/bin/bash
# services.sh - Service management with retry logic and port conflict detection
# Implements robust service restart, status checking, and port conflict resolution
#
# Usage:
#   source lib/core/services.sh
#   service_restart_with_retry "xrdp" 3 5
#   check_port_conflict 3389 "xrdp"
#
# Dependencies:
#   - lib/core/logger.sh

set -euo pipefail

# Prevent multiple sourcing
if [[ -n "${_SERVICES_SH_LOADED:-}" ]]; then
  return 0
fi
readonly _SERVICES_SH_LOADED=1

# Source dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/core/logger.sh
source "${SCRIPT_DIR}/logger.sh"

# Service restart with retry logic
# Args: $1 - service name, $2 - max retries (default: 3), $3 - delay (default: 5)
# Returns: 0 on success, 1 on failure
service_restart_with_retry() {
  local service_name="$1"
  local max_retries="${2:-3}"
  local delay="${3:-5}"
  local attempt=0
  
  if [[ -z "$service_name" ]]; then
    log_error "service_restart_with_retry: service name required"
    return 1
  fi
  
  log_info "Restarting service: $service_name"
  
  while [[ $attempt -lt $max_retries ]]; do
    attempt=$((attempt + 1))
    
    log_debug "Restart attempt $attempt/$max_retries"
    
    # Attempt restart
    if systemctl restart "$service_name" 2>&1; then
      # Wait a moment for service to stabilize
      sleep 2
      
      # Verify service is active
      if systemctl is-active --quiet "$service_name"; then
        log_info "Service $service_name restarted successfully"
        return 0
      else
        log_warning "Service $service_name not active after restart"
      fi
    else
      log_warning "Restart command failed for $service_name"
    fi
    
    # Check if we should retry
    if [[ $attempt -lt $max_retries ]]; then
      log_info "Retrying in ${delay}s..."
      sleep "$delay"
    fi
  done
  
  log_error "Failed to restart $service_name after $max_retries attempts"
  
  # Show service status for debugging
  log_error "Service status:"
  systemctl status "$service_name" --no-pager -l || true
  
  return 1
}

# Start service with retry logic
# Args: $1 - service name, $2 - max retries (default: 3), $3 - delay (default: 5)
# Returns: 0 on success, 1 on failure
service_start_with_retry() {
  local service_name="$1"
  local max_retries="${2:-3}"
  local delay="${3:-5}"
  local attempt=0
  
  if [[ -z "$service_name" ]]; then
    log_error "service_start_with_retry: service name required"
    return 1
  fi
  
  # Check if already running
  if systemctl is-active --quiet "$service_name"; then
    log_info "Service $service_name is already running"
    return 0
  fi
  
  log_info "Starting service: $service_name"
  
  while [[ $attempt -lt $max_retries ]]; do
    attempt=$((attempt + 1))
    
    log_debug "Start attempt $attempt/$max_retries"
    
    if systemctl start "$service_name" 2>&1; then
      sleep 2
      
      if systemctl is-active --quiet "$service_name"; then
        log_info "Service $service_name started successfully"
        return 0
      fi
    fi
    
    if [[ $attempt -lt $max_retries ]]; then
      log_info "Retrying in ${delay}s..."
      sleep "$delay"
    fi
  done
  
  log_error "Failed to start $service_name after $max_retries attempts"
  systemctl status "$service_name" --no-pager -l || true
  
  return 1
}

# Check if port is in use
# Args: $1 - port number
# Returns: 0 if in use, 1 if available
check_port_in_use() {
  local port="$1"
  
  if [[ -z "$port" ]]; then
    log_error "check_port_in_use: port number required"
    return 1
  fi
  
  if ss -tuln | grep -q ":${port} "; then
    return 0  # In use
  fi
  
  return 1  # Available
}

# Get process using a port
# Args: $1 - port number
# Returns: PID and process name
get_port_owner() {
  local port="$1"
  
  if [[ -z "$port" ]]; then
    log_error "get_port_owner: port number required"
    return 1
  fi
  
  local owner_info
  owner_info=$(ss -tulnp | grep ":${port} " | head -1)
  
  if [[ -z "$owner_info" ]]; then
    echo "None"
    return 0
  fi
  
  # Extract process info from ss output
  local pid_info
  pid_info=$(echo "$owner_info" | grep -oP 'pid=\K[0-9]+' || echo "unknown")
  
  if [[ "$pid_info" != "unknown" ]]; then
    local process_name
    process_name=$(ps -p "$pid_info" -o comm= 2>/dev/null || echo "unknown")
    echo "PID: $pid_info, Process: $process_name"
  else
    echo "$owner_info"
  fi
  
  return 0
}

# Check for port conflict and attempt resolution
# Args: $1 - port number, $2 - intended service name, $3 - auto-stop conflicting service (default: false)
# Returns: 0 if no conflict or resolved, 1 if conflict exists
check_port_conflict() {
  local port="$1"
  local service_name="$2"
  local auto_stop="${3:-false}"
  
  if [[ -z "$port" ]] || [[ -z "$service_name" ]]; then
    log_error "check_port_conflict: port and service name required"
    return 1
  fi
  
  log_debug "Checking port conflict for port $port (service: $service_name)"
  
  if ! check_port_in_use "$port"; then
    log_debug "Port $port is available"
    return 0
  fi
  
  # Port is in use, get owner
  local owner
  owner=$(get_port_owner "$port")
  
  log_warning "Port $port is already in use by: $owner"
  log_warning "This port is required for service: $service_name"
  
  # Check if the owner is the service we're trying to start
  if echo "$owner" | grep -q "$service_name"; then
    log_info "Port is used by the target service ($service_name), this is expected"
    return 0
  fi
  
  # Port is used by a different process
  if [[ "$auto_stop" == "true" ]]; then
    log_warning "Attempting to stop conflicting service..."
    
    # Extract PID if possible
    local pid
    pid=$(echo "$owner" | grep -oP 'PID:\s*\K[0-9]+' || echo "")
    
    if [[ -n "$pid" ]] && [[ "$pid" =~ ^[0-9]+$ ]]; then
      # Try to identify systemd service
      local unit
      unit=$(systemctl status "$pid" 2>/dev/null | grep -oP '●\s+\K\S+\.service' | head -1 || echo "")
      
      if [[ -n "$unit" ]]; then
        log_info "Stopping conflicting service: $unit"
        systemctl stop "$unit" || {
          log_error "Failed to stop conflicting service: $unit"
          return 1
        }
        
        # Wait for port to be released
        sleep 2
        
        if ! check_port_in_use "$port"; then
          log_info "Port $port is now available"
          return 0
        fi
      else
        log_warning "Could not determine systemd unit for PID $pid"
      fi
    fi
  fi
  
  log_error "Port $port conflict unresolved"
  log_error "Manual intervention required: stop the process using port $port"
  log_error "Owner: $owner"
  
  return 1
}

# Enable service at boot
# Args: $1 - service name
# Returns: 0 on success, 1 on failure
service_enable() {
  local service_name="$1"
  
  if [[ -z "$service_name" ]]; then
    log_error "service_enable: service name required"
    return 1
  fi
  
  log_info "Enabling service at boot: $service_name"
  
  if systemctl enable "$service_name" 2>&1; then
    log_info "Service $service_name enabled"
    return 0
  else
    log_error "Failed to enable service: $service_name"
    return 1
  fi
}

# Get service status
# Args: $1 - service name
# Returns: active, inactive, failed, or unknown
service_get_status() {
  local service_name="$1"
  
  if [[ -z "$service_name" ]]; then
    echo "unknown"
    return 0
  fi
  
  local status
  status=$(systemctl is-active "$service_name" 2>/dev/null || echo "unknown")
  
  echo "$status"
}

# Check if service is running
# Args: $1 - service name
# Returns: 0 if running, 1 if not
service_is_running() {
  local service_name="$1"
  
  if systemctl is-active --quiet "$service_name" 2>/dev/null; then
    return 0
  fi
  
  return 1
}

# Wait for service to become active
# Args: $1 - service name, $2 - timeout in seconds (default: 30)
# Returns: 0 if active, 1 if timeout
service_wait_active() {
  local service_name="$1"
  local timeout="${2:-30}"
  local waited=0
  
  if [[ -z "$service_name" ]]; then
    log_error "service_wait_active: service name required"
    return 1
  fi
  
  log_debug "Waiting for service to become active: $service_name (timeout: ${timeout}s)"
  
  while [[ $waited -lt $timeout ]]; do
    if systemctl is-active --quiet "$service_name"; then
      log_debug "Service $service_name is active after ${waited}s"
      return 0
    fi
    
    sleep 1
    waited=$((waited + 1))
  done
  
  log_error "Timeout waiting for service $service_name to become active (${timeout}s)"
  return 1
}

# Get service port bindings
# Args: $1 - service name
# Returns: list of ports
service_get_ports() {
  local service_name="$1"
  
  if [[ -z "$service_name" ]]; then
    return 1
  fi
  
  # Get main PID
  local main_pid
  main_pid=$(systemctl show -p MainPID --value "$service_name" 2>/dev/null)
  
  if [[ -z "$main_pid" ]] || [[ "$main_pid" == "0" ]]; then
    return 1
  fi
  
  # Find ports used by this process
  ss -tulnp | grep "pid=$main_pid" | grep -oP ':\K[0-9]+' | sort -u
}
