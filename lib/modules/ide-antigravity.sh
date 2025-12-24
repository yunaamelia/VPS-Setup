#!/bin/bash
# IDE Antigravity Installation Module
# Purpose: Install Antigravity IDE via AppImage from GitHub releases
# Requirements: FR-019, FR-037, SC-009

set -euo pipefail

# Source dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(dirname "$SCRIPT_DIR")"

source "${LIB_DIR}/core/logger.sh"
source "${LIB_DIR}/core/checkpoint.sh"
source "${LIB_DIR}/core/transaction.sh"

# Constants
readonly ANTIGRAVITY_CHECKPOINT="${ANTIGRAVITY_CHECKPOINT:-ide-antigravity}"
readonly ANTIGRAVITY_GITHUB_API="https://api.github.com/repos/antigravity-code/antigravity/releases/latest"
readonly ANTIGRAVITY_INSTALL_DIR="${ANTIGRAVITY_INSTALL_DIR:-/opt/antigravity}"
readonly ANTIGRAVITY_DESKTOP="${ANTIGRAVITY_DESKTOP:-/usr/share/applications/antigravity.desktop}"
readonly ANTIGRAVITY_APPIMAGE="${ANTIGRAVITY_APPIMAGE:-$ANTIGRAVITY_INSTALL_DIR/antigravity.AppImage}"
readonly ANTIGRAVITY_ICON_URL="https://raw.githubusercontent.com/antigravity-code/antigravity/main/resources/icon.png"
readonly ANTIGRAVITY_ICON_PATH="${ANTIGRAVITY_ICON_PATH:-/usr/share/pixmaps/antigravity.png}"

#######################################
# Check prerequisites for Antigravity installation
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   0 if prerequisites met, 1 otherwise
#######################################
ide_antigravity_check_prerequisites() {
    log_info "Checking Antigravity prerequisites..."
    
    # Verify desktop environment is installed
    if ! checkpoint_exists "desktop-install"; then
        log_error "Desktop environment not installed (checkpoint missing: desktop-install)"
        return 1
    fi
    
    # Verify required commands
    local required_cmds=("wget" "curl" "jq")
    for cmd in "${required_cmds[@]}"; do
        if ! command -v "$cmd" &>/dev/null; then
            log_error "Required command not found: $cmd"
            return 1
        fi
    done
    
    log_info "Antigravity prerequisites check passed"
    return 0
}

#######################################
# Install FUSE for AppImage support
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   0 on success, 1 on failure
#######################################
ide_antigravity_install_fuse() {
    log_info "Ensuring FUSE is installed for AppImage support..."
    
    if dpkg -l fuse 2>/dev/null | grep -q "^ii"; then
        log_info "FUSE already installed"
        return 0
    fi
    
    if ! DEBIAN_FRONTEND=noninteractive apt-get install -y fuse libfuse2 2>&1 | \
         tee -a "${LOG_FILE:-/dev/null}"; then
        log_error "Failed to install FUSE"
        return 1
    fi
    
    log_info "FUSE installed successfully"
    return 0
}

#######################################
# Fetch latest Antigravity AppImage URL from GitHub
# Globals:
#   ANTIGRAVITY_GITHUB_API
# Arguments:
#   None
# Outputs:
#   AppImage download URL to stdout
# Returns:
#   0 on success, 1 on failure
#######################################
ide_antigravity_fetch_url() {
    log_info "Fetching latest Antigravity AppImage URL from GitHub..."
    
    # Fetch release info with retry
    local max_retries=3
    local retry_count=0
    local release_json
    
    while (( retry_count < max_retries )); do
        release_json=$(curl -s "$ANTIGRAVITY_GITHUB_API" 2>&1)
        
        if [[ -n "$release_json" ]] && echo "$release_json" | jq -e . &>/dev/null; then
            break
        fi
        
        retry_count=$((retry_count + 1))
        if (( retry_count < max_retries )); then
            log_warning "Failed to fetch GitHub API (attempt $retry_count/$max_retries), retrying..."
            sleep 2
        else
            log_error "Failed to fetch Antigravity release info from GitHub after $max_retries attempts"
            return 1
        fi
    done
    
    # Extract AppImage URL
    local appimage_url
    appimage_url=$(echo "$release_json" | \
                   jq -r '.assets[] | select(.name | endswith(".AppImage")) | .browser_download_url' | \
                   head -n1)
    
    if [[ -z "$appimage_url" || "$appimage_url" == "null" ]]; then
        log_error "Failed to extract Antigravity AppImage URL from GitHub API response"
        return 1
    fi
    
    echo "$appimage_url"
    return 0
}

#######################################
# Download and install Antigravity AppImage
# Globals:
#   ANTIGRAVITY_INSTALL_DIR, ANTIGRAVITY_APPIMAGE
# Arguments:
#   $1 - AppImage download URL
# Returns:
#   0 on success, 1 on failure
#######################################
ide_antigravity_install_appimage() {
    local appimage_url="$1"
    log_info "Installing Antigravity AppImage from: $appimage_url"
    
    # Create installation directory
    mkdir -p "$ANTIGRAVITY_INSTALL_DIR"
    transaction_log "antigravity_dir_create" "rm -rf '$ANTIGRAVITY_INSTALL_DIR'"
    
    # Download AppImage with retry
    local max_retries=3
    local retry_count=0
    
    while (( retry_count < max_retries )); do
        if wget -O "$ANTIGRAVITY_APPIMAGE" "$appimage_url" 2>&1 | \
           tee -a "${LOG_FILE:-/dev/null}"; then
            log_info "Antigravity AppImage downloaded successfully"
            break
        fi
        
        retry_count=$((retry_count + 1))
        if (( retry_count < max_retries )); then
            log_warning "Failed to download Antigravity AppImage (attempt $retry_count/$max_retries), retrying..."
            sleep 2
        else
            log_error "Failed to download Antigravity AppImage after $max_retries attempts"
            return 1
        fi
    done
    
    # Make AppImage executable
    chmod +x "$ANTIGRAVITY_APPIMAGE"
    
    log_info "Antigravity AppImage installed successfully"
    return 0
}

#######################################
# Download Antigravity icon
# Globals:
#   ANTIGRAVITY_ICON_URL, ANTIGRAVITY_ICON_PATH
# Arguments:
#   None
# Returns:
#   0 on success, 1 on failure (non-critical)
#######################################
ide_antigravity_download_icon() {
    log_info "Downloading Antigravity icon..."
    
    # Try to download icon (non-critical)
    if wget -q -O "$ANTIGRAVITY_ICON_PATH" "$ANTIGRAVITY_ICON_URL" 2>&1 | \
       tee -a "${LOG_FILE:-/dev/null}"; then
        transaction_log "antigravity_icon" "rm -f '$ANTIGRAVITY_ICON_PATH'"
        log_info "Antigravity icon downloaded successfully"
        return 0
    else
        log_warning "Failed to download Antigravity icon (non-critical)"
        return 1
    fi
}

#######################################
# Create desktop launcher for Antigravity
# Globals:
#   ANTIGRAVITY_APPIMAGE, ANTIGRAVITY_DESKTOP, ANTIGRAVITY_ICON_PATH
# Arguments:
#   None
# Returns:
#   0 on success, 1 on failure
#######################################
ide_antigravity_create_launcher() {
    log_info "Creating desktop launcher for Antigravity..."
    
    # Determine icon path (use downloaded or fallback)
    local icon_value="antigravity"
    if [[ -f "$ANTIGRAVITY_ICON_PATH" ]]; then
        icon_value="$ANTIGRAVITY_ICON_PATH"
    fi
    
    cat > "$ANTIGRAVITY_DESKTOP" << EOF
[Desktop Entry]
Name=Antigravity
Comment=Advanced code editor with AI assistance
Exec=$ANTIGRAVITY_APPIMAGE
Icon=$icon_value
Type=Application
Categories=Development;IDE;TextEditor;
Terminal=false
StartupNotify=true
EOF
    
    transaction_log "antigravity_launcher" "rm -f '$ANTIGRAVITY_DESKTOP'"
    log_info "Desktop launcher created for Antigravity"
    return 0
}

#######################################
# Create CLI alias/symlink for Antigravity
# Globals:
#   ANTIGRAVITY_APPIMAGE
# Arguments:
#   None
# Returns:
#   0 on success, 1 on failure
#######################################
ide_antigravity_create_cli_alias() {
    log_info "Creating CLI alias for Antigravity..."
    
    # Create symlink in /usr/local/bin
    if ln -sf "$ANTIGRAVITY_APPIMAGE" /usr/local/bin/antigravity; then
        transaction_log "antigravity_symlink" "rm -f /usr/local/bin/antigravity"
        log_info "CLI alias 'antigravity' created successfully"
        return 0
    else
        log_error "Failed to create CLI alias for Antigravity"
        return 1
    fi
}

#######################################
# Verify Antigravity installation
# Globals:
#   ANTIGRAVITY_APPIMAGE, ANTIGRAVITY_DESKTOP
# Arguments:
#   None
# Returns:
#   0 if verification passes, 1 otherwise
#######################################
ide_antigravity_verify() {
    log_info "Verifying Antigravity installation..."
    
    # Check AppImage exists and is executable
    if [[ ! -f "$ANTIGRAVITY_APPIMAGE" ]]; then
        log_error "Antigravity AppImage not found at: $ANTIGRAVITY_APPIMAGE"
        return 1
    fi
    
    if [[ ! -x "$ANTIGRAVITY_APPIMAGE" ]]; then
        log_error "Antigravity AppImage is not executable: $ANTIGRAVITY_APPIMAGE"
        return 1
    fi
    
    # Check CLI command exists
    if ! command -v antigravity &>/dev/null; then
        log_error "Antigravity command 'antigravity' not found in PATH"
        return 1
    fi
    
    # Check desktop launcher exists
    if [[ ! -f "$ANTIGRAVITY_DESKTOP" ]]; then
        log_warning "Antigravity desktop launcher not found at $ANTIGRAVITY_DESKTOP"
    fi
    
    # Verify symlink points to correct location
    local antigravity_path
    antigravity_path=$(command -v antigravity)
    
    if [[ "$antigravity_path" != "/usr/local/bin/antigravity" ]]; then
        log_warning "Antigravity CLI alias not at expected location: $antigravity_path"
    fi
    
    log_info "Antigravity verification passed"
    return 0
}

#######################################
# Main execution function for Antigravity installation
# Globals:
#   ANTIGRAVITY_CHECKPOINT
# Arguments:
#   None
# Returns:
#   0 on success, 1 on failure
#######################################
ide_antigravity_execute() {
    log_info "=== Starting Antigravity Installation ==="
    
    # Check if already completed
    if checkpoint_exists "$ANTIGRAVITY_CHECKPOINT"; then
        log_info "Antigravity installation already completed (checkpoint exists)"
        return 0
    fi
    
    # Check prerequisites
    if ! ide_antigravity_check_prerequisites; then
        log_error "Antigravity prerequisites check failed"
        return 1
    fi
    
    # Install FUSE for AppImage support
    if ! ide_antigravity_install_fuse; then
        log_error "Failed to install FUSE (required for AppImage)"
        return 1
    fi
    
    # Fetch latest AppImage URL
    local appimage_url
    if ! appimage_url=$(ide_antigravity_fetch_url); then
        log_error "Failed to fetch Antigravity AppImage URL"
        return 1
    fi
    
    log_info "Antigravity AppImage URL: $appimage_url"
    
    # Install AppImage
    if ! ide_antigravity_install_appimage "$appimage_url"; then
        log_error "Failed to install Antigravity AppImage"
        return 1
    fi
    
    # Download icon (non-critical)
    ide_antigravity_download_icon || true
    
    # Create desktop launcher
    if ! ide_antigravity_create_launcher; then
        log_warning "Failed to create desktop launcher (non-critical)"
    fi
    
    # Create CLI alias
    if ! ide_antigravity_create_cli_alias; then
        log_error "Failed to create CLI alias"
        return 1
    fi
    
    # Verify installation
    if ! ide_antigravity_verify; then
        log_error "Antigravity verification failed"
        return 1
    fi
    
    # Create checkpoint
    checkpoint_create "$ANTIGRAVITY_CHECKPOINT"
    
    log_info "=== Antigravity Installation Completed Successfully ==="
    return 0
}

# Export functions for testing
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    export -f ide_antigravity_check_prerequisites
    export -f ide_antigravity_install_fuse
    export -f ide_antigravity_fetch_url
    export -f ide_antigravity_install_appimage
    export -f ide_antigravity_download_icon
    export -f ide_antigravity_create_launcher
    export -f ide_antigravity_create_cli_alias
    export -f ide_antigravity_verify
    export -f ide_antigravity_execute
fi
