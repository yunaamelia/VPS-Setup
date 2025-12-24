#!/bin/bash
# file-ops.sh - Safe file operations with atomic writes, backups, and cleanup
# Implements atomic file operations, backup creation, and temporary file management
#
# Usage:
#   source lib/core/file-ops.sh
#   atomic_write "/etc/config.conf" "content"
#   backup_file "/etc/important.conf"
#   cleanup_temp_files
#
# Dependencies:
#   - lib/core/logger.sh

set -euo pipefail

# Prevent multiple sourcing
if [[ -n "${_FILE_OPS_SH_LOADED:-}" ]]; then
  return 0
fi
readonly _FILE_OPS_SH_LOADED=1

# Source dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/core/logger.sh
source "${SCRIPT_DIR}/logger.sh"

# Temporary directory for atomic operations
readonly TEMP_DIR="/tmp/vps-provision"
readonly TEMP_DIR="${TEMP_DIR:-/tmp/vps-provision}"
readonly BACKUP_DIR="${BACKUP_DIR:-/var/vps-provision/backups}"

# Temp file tracking
declare -a TEMP_FILES=()

# Initialize file operations
fileops_init() {
  mkdir -p "$TEMP_DIR" || {
    log_error "Failed to create temp directory: $TEMP_DIR"
    return 1
  }
  
  mkdir -p "$BACKUP_DIR" || {
    log_warning "Failed to create backup directory: $BACKUP_DIR"
  }
  
  log_debug "File operations initialized"
  log_debug "Temp directory: $TEMP_DIR"
  log_debug "Backup directory: $BACKUP_DIR"
}

# Atomic file write operation
# Args: $1 - target file path, $2 - content (via stdin or string)
# Returns: 0 on success, 1 on failure
atomic_write() {
  local target_file="$1"
  local content="${2:-}"
  
  if [[ -z "$target_file" ]]; then
    log_error "atomic_write: target file path required"
    return 1
  fi
  
  local temp_file
  temp_file=$(mktemp "${TEMP_DIR}/atomic.XXXXXX")
  TEMP_FILES+=("$temp_file")
  
  log_debug "Atomic write to: $target_file (via temp: $temp_file)"
  
  # Write content to temp file
  if [[ -n "$content" ]]; then
    echo "$content" > "$temp_file" || {
      log_error "Failed to write to temp file: $temp_file"
      return 1
    }
  else
    # Read from stdin
    cat > "$temp_file" || {
      log_error "Failed to write to temp file from stdin: $temp_file"
      return 1
    }
  fi
  
  # Verify temp file was created
  if [[ ! -f "$temp_file" ]]; then
    log_error "Temp file not created: $temp_file"
    return 1
  fi
  
  # Create target directory if needed
  local target_dir
  target_dir=$(dirname "$target_file")
  if [[ ! -d "$target_dir" ]]; then
    mkdir -p "$target_dir" || {
      log_error "Failed to create target directory: $target_dir"
      return 1
    }
  fi
  
  # Backup existing file if it exists
  if [[ -f "$target_file" ]]; then
    backup_file "$target_file" || {
      log_warning "Failed to backup existing file: $target_file"
    }
  fi
  
  # Atomic move (rename is atomic on same filesystem)
  mv "$temp_file" "$target_file" || {
    log_error "Failed to move temp file to target: $temp_file -> $target_file"
    return 1
  }
  
  log_debug "Atomic write completed: $target_file"
  return 0
}

# Create backup of file with .bak extension
# Args: $1 - file path
# Returns: 0 on success, 1 on failure
backup_file() {
  local file_path="$1"
  
  if [[ -z "$file_path" ]]; then
    log_error "backup_file: file path required"
    return 1
  fi
  
  if [[ ! -f "$file_path" ]]; then
    log_warning "File does not exist, cannot backup: $file_path"
    return 1
  fi
  
  local backup_path="${file_path}.bak"
  local backup_name
  backup_name=$(basename "$file_path")
  local timestamp
  timestamp=$(date +%Y%m%d_%H%M%S)
  local versioned_backup="${BACKUP_DIR}/${backup_name}.${timestamp}.bak"
  
  log_debug "Creating backup: $file_path -> $backup_path"
  
  # Create local .bak file
  cp "$file_path" "$backup_path" || {
    log_error "Failed to create backup: $backup_path"
    return 1
  }
  
  # Also create versioned backup in backup directory
  if [[ -d "$BACKUP_DIR" ]]; then
    cp "$file_path" "$versioned_backup" 2>/dev/null || {
      log_debug "Could not create versioned backup (non-critical)"
    }
  fi
  
  log_info "Backup created: $backup_path"
  return 0
}

# Restore file from backup
# Args: $1 - original file path
# Returns: 0 on success, 1 on failure
restore_from_backup() {
  local file_path="$1"
  local backup_path="${file_path}.bak"
  
  if [[ ! -f "$backup_path" ]]; then
    log_error "Backup file not found: $backup_path"
    return 1
  fi
  
  log_info "Restoring from backup: $backup_path -> $file_path"
  
  cp "$backup_path" "$file_path" || {
    log_error "Failed to restore from backup"
    return 1
  }
  
  log_info "File restored successfully"
  return 0
}

# Safe file append (atomic)
# Args: $1 - target file, $2 - content to append
# Returns: 0 on success, 1 on failure
atomic_append() {
  local target_file="$1"
  local content="$2"
  
  if [[ -z "$target_file" ]] || [[ -z "$content" ]]; then
    log_error "atomic_append: target file and content required"
    return 1
  fi
  
  # Create temp file with existing content + new content
  local temp_file
  temp_file=$(mktemp "${TEMP_DIR}/append.XXXXXX")
  TEMP_FILES+=("$temp_file")
  
  # Copy existing content
  if [[ -f "$target_file" ]]; then
    cat "$target_file" > "$temp_file"
  fi
  
  # Append new content
  echo "$content" >> "$temp_file"
  
  # Atomic replace
  atomic_write "$target_file" < "$temp_file"
  
  return $?
}

# Download file with resume support
# Args: $1 - URL, $2 - output file path, $3 - max retries (default: 3)
# Returns: 0 on success, 1 on failure
download_with_resume() {
  local url="$1"
  local output_file="$2"
  local max_retries="${3:-3}"
  local attempt=0
  
  if [[ -z "$url" ]] || [[ -z "$output_file" ]]; then
    log_error "download_with_resume: URL and output file required"
    return 1
  fi
  
  log_info "Downloading: $url -> $output_file"
  
  while [[ $attempt -lt $max_retries ]]; do
    attempt=$((attempt + 1))
    
    log_debug "Download attempt $attempt/$max_retries"
    
    # Try to resume download with wget -c
    if wget -c -q --show-progress -O "$output_file" "$url" 2>&1; then
      log_info "Download completed successfully"
      return 0
    fi
    
    local exit_code=$?
    log_warning "Download attempt $attempt failed with exit code: $exit_code"
    
    # If partial file exists and resume failed, try clean download
    if [[ $attempt -lt $max_retries ]]; then
      if [[ -f "$output_file" ]]; then
        log_info "Removing partial download for clean retry"
        rm -f "$output_file"
      fi
      
      log_info "Retrying in 2 seconds..."
      sleep 2
    fi
  done
  
  log_error "Download failed after $max_retries attempts: $url"
  return 1
}

# Track temporary file for cleanup
# Args: $1 - temp file path
track_temp_file() {
  local temp_file="$1"
  TEMP_FILES+=("$temp_file")
  log_debug "Tracking temp file: $temp_file"
}

# Cleanup all temporary files
# Returns: 0 always (best effort)
cleanup_temp_files() {
  log_info "Cleaning up temporary files..."
  
  local cleaned=0
  local failed=0
  
  # Clean tracked temp files
  for temp_file in "${TEMP_FILES[@]}"; do
    if [[ -f "$temp_file" ]]; then
      if rm -f "$temp_file" 2>/dev/null; then
        cleaned=$((cleaned + 1))
      else
        failed=$((failed + 1))
        log_warning "Failed to remove temp file: $temp_file"
      fi
    fi
  done
  
  # Clean temp directory
  if [[ -d "$TEMP_DIR" ]]; then
    local count
    count=$(find "$TEMP_DIR" -type f 2>/dev/null | wc -l)
    
    if [[ $count -gt 0 ]]; then
      log_info "Cleaning $count file(s) from temp directory"
      find "$TEMP_DIR" -type f -mtime +1 -delete 2>/dev/null || true
    fi
  fi
  
  # Clean APT cache if disk space is low
  local available_gb
  available_gb=$(df -BG / | tail -1 | awk '{print $4}' | sed 's/G//')
  
  if [[ $available_gb -lt 10 ]]; then
    log_info "Low disk space detected, cleaning APT cache..."
    apt-get clean 2>/dev/null || true
  fi
  
  log_info "Cleanup completed: $cleaned removed, $failed failed"
  
  # Reset tracked files array
  TEMP_FILES=()
  
  return 0
}

# Cleanup on exit (can be registered with trap)
cleanup_on_exit() {
  log_debug "Exit cleanup triggered"
  cleanup_temp_files
}

# Get backup directory
fileops_get_backup_dir() {
  echo "$BACKUP_DIR"
}

# Clean old backups (older than N days)
# Args: $1 - days to keep (default: 7)
fileops_clean_old_backups() {
  local days="${1:-7}"
  
  if [[ ! -d "$BACKUP_DIR" ]]; then
    return 0
  fi
  
  log_info "Cleaning backups older than $days days..."
  
  local count
  count=$(find "$BACKUP_DIR" -type f -mtime +"$days" 2>/dev/null | wc -l)
  
  if [[ $count -gt 0 ]]; then
    find "$BACKUP_DIR" -type f -mtime +"$days" -delete 2>/dev/null || true
    log_info "Removed $count old backup(s)"
  else
    log_debug "No old backups to clean"
  fi
  
  return 0
}
