#!/bin/bash
# IDE Cursor Installation Module
# Purpose: Install Cursor IDE via .deb package or AppImage fallback
# Requirements: FR-019, FR-037, SC-009

set -euo pipefail

# Source dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(dirname "$SCRIPT_DIR")"

source "${LIB_DIR}/core/logger.sh"
source "${LIB_DIR}/core/checkpoint.sh"
source "${LIB_DIR}/core/transaction.sh"

# Constants
readonly CURSOR_CHECKPOINT="${CURSOR_CHECKPOINT:-ide-cursor}"
readonly CURSOR_DEB_URL="https://download.cursor.sh/linux/cursor-latest.deb"
readonly CURSOR_APPIMAGE_API="https://api.github.com/repos/getcursor/cursor/releases/latest"
readonly CURSOR_INSTALL_DIR="${CURSOR_INSTALL_DIR:-/opt/cursor}"
readonly CURSOR_DESKTOP="${CURSOR_DESKTOP:-/usr/share/applications/cursor.desktop}"
readonly CURSOR_TMP_DEB="${CURSOR_TMP_DEB:-/tmp/cursor.deb}"
readonly CURSOR_APPIMAGE="${CURSOR_APPIMAGE:-$CURSOR_INSTALL_DIR/cursor.AppImage}"

#######################################
# Check prerequisites for Cursor installation
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   0 if prerequisites met, 1 otherwise
#######################################
ide_cursor_check_prerequisites() {
    log_info "Checking Cursor prerequisites..."
    
    # Verify desktop environment is installed
    if ! checkpoint_exists "desktop-install"; then
        log_error "Desktop environment not installed (checkpoint missing: desktop-install)"
        return 1
    fi
    
    # Verify required commands
    local required_cmds=("wget" "dpkg" "curl")
    for cmd in "${required_cmds[@]}"; do
        if ! command -v "$cmd" &>/dev/null; then
            log_error "Required command not found: $cmd"
            return 1
        fi
    done
    
    log_info "Cursor prerequisites check passed"
    return 0
}

#######################################
# Install Cursor via .deb package (preferred method)
# Globals:
#   CURSOR_DEB_URL, CURSOR_TMP_DEB
# Arguments:
#   None
# Returns:
#   0 on success, 1 on failure
#######################################
ide_cursor_install_deb() {
    log_info "Attempting to install Cursor via .deb package..."
    
    # Download .deb package with retry
    local max_retries=3
    local retry_count=0
    
    while (( retry_count < max_retries )); do
        if wget -O "$CURSOR_TMP_DEB" "$CURSOR_DEB_URL" 2>&1 | \
           tee -a "${LOG_FILE:-/dev/null}"; then
            log_info "Cursor .deb package downloaded successfully"
            break
        fi
        
        retry_count=$((retry_count + 1))
        if (( retry_count < max_retries )); then
            log_warning "Failed to download Cursor .deb (attempt $retry_count/$max_retries), retrying..."
            sleep 2
        else
            log_error "Failed to download Cursor .deb after $max_retries attempts"
            return 1
        fi
    done
    
    # Install .deb package
    log_info "Installing Cursor .deb package..."
    if dpkg -i "$CURSOR_TMP_DEB" 2>&1 | tee -a "${LOG_FILE:-/dev/null}"; then
        transaction_log "cursor_deb_install" "apt-get remove -y cursor || true"
        rm -f "$CURSOR_TMP_DEB"
        log_info "Cursor installed successfully via .deb"
        return 0
    fi
    
    # Try fixing dependencies
    log_warning "Cursor .deb installation failed, attempting dependency fix..."
    if apt-get install -f -y 2>&1 | tee -a "${LOG_FILE:-/dev/null}"; then
        transaction_log "cursor_deb_install" "apt-get remove -y cursor || true"
        rm -f "$CURSOR_TMP_DEB"
        log_info "Cursor installed successfully after dependency fix"
        return 0
    fi
    
    # Cleanup failed deb
    rm -f "$CURSOR_TMP_DEB"
    log_error "Failed to install Cursor via .deb package"
    return 1
}

#######################################
# Install Cursor via AppImage (fallback method)
# Globals:
#   CURSOR_APPIMAGE_API, CURSOR_INSTALL_DIR, CURSOR_APPIMAGE
# Arguments:
#   None
# Returns:
#   0 on success, 1 on failure
#######################################
ide_cursor_install_appimage() {
    log_info "Attempting to install Cursor via AppImage (fallback)..."
    
    # Ensure FUSE is installed for AppImage support
    if ! dpkg -l fuse 2>/dev/null | grep -q "^ii"; then
        log_info "Installing FUSE for AppImage support..."
        apt-get install -y fuse libfuse2 2>&1 | tee -a "${LOG_FILE:-/dev/null}" || true
    fi
    
    # Fetch latest AppImage URL from GitHub API
    log_info "Fetching latest Cursor AppImage URL..."
    local appimage_url
    appimage_url=$(curl -s "$CURSOR_APPIMAGE_API" | \
                   grep -o 'https://.*\.AppImage' | head -n1)
    
    if [[ -z "$appimage_url" ]]; then
        log_error "Failed to fetch Cursor AppImage URL from GitHub"
        return 1
    fi
    
    log_info "Cursor AppImage URL: $appimage_url"
    
    # Create installation directory
    mkdir -p "$CURSOR_INSTALL_DIR"
    transaction_log "cursor_dir_create" "rm -rf '$CURSOR_INSTALL_DIR'"
    
    # Download AppImage with retry
    local max_retries=3
    local retry_count=0
    
    while (( retry_count < max_retries )); do
        if wget -O "$CURSOR_APPIMAGE" "$appimage_url" 2>&1 | \
           tee -a "${LOG_FILE:-/dev/null}"; then
            log_info "Cursor AppImage downloaded successfully"
            break
        fi
        
        retry_count=$((retry_count + 1))
        if (( retry_count < max_retries )); then
            log_warning "Failed to download Cursor AppImage (attempt $retry_count/$max_retries), retrying..."
            sleep 2
        else
            log_error "Failed to download Cursor AppImage after $max_retries attempts"
            return 1
        fi
    done
    
    # Make AppImage executable
    chmod +x "$CURSOR_APPIMAGE"
    
    # Create desktop launcher
    if ! ide_cursor_create_launcher_appimage; then
        log_warning "Failed to create desktop launcher for Cursor AppImage"
    fi
    
    # Create CLI symlink
    ln -sf "$CURSOR_APPIMAGE" /usr/local/bin/cursor
    transaction_log "cursor_symlink" "rm -f /usr/local/bin/cursor"
    
    log_info "Cursor installed successfully via AppImage"
    return 0
}

#######################################
# Create desktop launcher for AppImage
# Globals:
#   CURSOR_APPIMAGE, CURSOR_DESKTOP
# Arguments:
#   None
# Returns:
#   0 on success, 1 on failure
#######################################
ide_cursor_create_launcher_appimage() {
    log_info "Creating desktop launcher for Cursor AppImage..."
    
    cat > "$CURSOR_DESKTOP" << EOF
[Desktop Entry]
Name=Cursor
Comment=AI-powered code editor
Exec=$CURSOR_APPIMAGE
Icon=cursor
Type=Application
Categories=Development;IDE;TextEditor;
Terminal=false
StartupNotify=true
EOF
    
    transaction_log "cursor_launcher" "rm -f '$CURSOR_DESKTOP'"
    log_info "Desktop launcher created for Cursor AppImage"
    return 0
}

#######################################
# Verify Cursor installation
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   0 if verification passes, 1 otherwise
#######################################
ide_cursor_verify() {
    log_info "Verifying Cursor installation..."
    
    # Check executable exists
    if ! command -v cursor &>/dev/null; then
        log_error "Cursor command 'cursor' not found in PATH"
        return 1
    fi
    
    # Check version (brief launch) - cursor may not support --version
    # Just check if command exists and is executable
    local cursor_path
    cursor_path=$(command -v cursor)
    
    if [[ ! -x "$cursor_path" ]]; then
        log_error "Cursor executable is not executable: $cursor_path"
        return 1
    fi
    
    # Check desktop launcher exists
    if [[ ! -f "$CURSOR_DESKTOP" ]]; then
        log_warning "Cursor desktop launcher not found at $CURSOR_DESKTOP"
    fi
    
    # Verify it's either a package or AppImage
    if dpkg -l cursor 2>/dev/null | grep -q "^ii"; then
        log_info "Cursor installed via .deb package"
    elif [[ -f "$CURSOR_APPIMAGE" ]]; then
        log_info "Cursor installed via AppImage"
    else
        log_error "Cursor installation method unknown"
        return 1
    fi
    
    log_info "Cursor verification passed"
    return 0
}

#######################################
# Main execution function for Cursor installation
# Globals:
#   CURSOR_CHECKPOINT
# Arguments:
#   None
# Returns:
#   0 on success, 1 on failure
#######################################
ide_cursor_execute() {
    log_info "=== Starting Cursor Installation ==="
    
    # Check if already completed
    if checkpoint_exists "$CURSOR_CHECKPOINT"; then
        log_info "Cursor installation already completed (checkpoint exists)"
        return 0
    fi
    
    # Check prerequisites
    if ! ide_cursor_check_prerequisites; then
        log_error "Cursor prerequisites check failed"
        return 1
    fi
    
    # Try .deb installation first (preferred)
    if ide_cursor_install_deb; then
        log_info "Cursor installed via .deb package (preferred method)"
    else
        log_warning "Cursor .deb installation failed, trying AppImage fallback..."
        
        # Try AppImage installation (fallback)
        if ! ide_cursor_install_appimage; then
            log_error "All Cursor installation methods failed"
            return 1
        fi
    fi
    
    # Verify installation
    if ! ide_cursor_verify; then
        log_error "Cursor verification failed"
        return 1
    fi
    
    # Create checkpoint
    checkpoint_create "$CURSOR_CHECKPOINT"
    
    log_info "=== Cursor Installation Completed Successfully ==="
    return 0
}

# Export functions for testing
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    export -f ide_cursor_check_prerequisites
    export -f ide_cursor_install_deb
    export -f ide_cursor_install_appimage
    export -f ide_cursor_create_launcher_appimage
    export -f ide_cursor_verify
    export -f ide_cursor_execute
fi
