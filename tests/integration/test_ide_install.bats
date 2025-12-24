#!/usr/bin/env bats
# Integration tests for IDE installations (VSCode, Cursor, Antigravity)
# Requirements: FR-019, FR-037, SC-009, NFR-003

load '../test_helper'

setup() {
    # Setup test environment with temporary directories
    export LOG_FILE="${BATS_TEST_TMPDIR}/test.log"
    export CHECKPOINT_DIR="${BATS_TEST_TMPDIR}/checkpoints"
    export TRANSACTION_LOG="${BATS_TEST_TMPDIR}/transactions.log"
    export MOCK_BIN_DIR="${BATS_TEST_TMPDIR}/bin"
    
    # VSCode Overrides
    export VSCODE_CHECKPOINT="ide-vscode"
    export VSCODE_LIST="${BATS_TEST_TMPDIR}/vscode.list"
    export VSCODE_GPG_KEY="${BATS_TEST_TMPDIR}/microsoft.gpg"
    export VSCODE_DESKTOP="${BATS_TEST_TMPDIR}/code.desktop"
    
    # Cursor Overrides
    export CURSOR_CHECKPOINT="ide-cursor"
    export CURSOR_INSTALL_DIR="${BATS_TEST_TMPDIR}/cursor"
    export CURSOR_DESKTOP="${BATS_TEST_TMPDIR}/cursor.desktop"
    export CURSOR_TMP_DEB="${BATS_TEST_TMPDIR}/cursor.deb"
    export CURSOR_APPIMAGE="${CURSOR_INSTALL_DIR}/cursor.AppImage"
    
    # Antigravity Overrides
    export ANTIGRAVITY_CHECKPOINT="ide-antigravity"
    export ANTIGRAVITY_INSTALL_DIR="${BATS_TEST_TMPDIR}/antigravity"
    export ANTIGRAVITY_DESKTOP="${BATS_TEST_TMPDIR}/antigravity.desktop"
    export ANTIGRAVITY_APPIMAGE="${ANTIGRAVITY_INSTALL_DIR}/antigravity.AppImage"
    export ANTIGRAVITY_ICON_PATH="${BATS_TEST_TMPDIR}/antigravity.png"

    # Create directories
    mkdir -p "${CHECKPOINT_DIR}"
    mkdir -p "$(dirname "${VSCODE_LIST}")"
    mkdir -p "$(dirname "${VSCODE_GPG_KEY}")"
    mkdir -p "$(dirname "${VSCODE_DESKTOP}")"
    mkdir -p "${CURSOR_INSTALL_DIR}"
    mkdir -p "${ANTIGRAVITY_INSTALL_DIR}"
    mkdir -p "${MOCK_BIN_DIR}"
    touch "${LOG_FILE}"
    touch "${TRANSACTION_LOG}"

    # Mock Core Dependencies
    source "${BATS_TEST_DIRNAME}/../../lib/core/logger.sh"
    source "${BATS_TEST_DIRNAME}/../../lib/core/checkpoint.sh"
    source "${BATS_TEST_DIRNAME}/../../lib/core/transaction.sh"

    # --- MOCKS ---
    
    # Mock apt-get
    function apt-get() { echo "apt-get $*" >> "${LOG_FILE}"; return 0; }
    export -f apt-get
    
    # Mock dpkg (Stateful)
    function dpkg() {
        if [[ "$1" == "-s" ]]; then # For verification checks if used
             if [[ -f "${BATS_TEST_TMPDIR}/installed_pkg_$2" ]]; then
                 echo "Package: $2"
                 echo "Status: install ok installed"
                 return 0
             fi
             return 1
        fi
        
        # Check installed packages (mocked via file existence for generality)
        if [[ "$1" == "-l" ]]; then
             local pkg="$2"
             if [[ -f "${BATS_TEST_TMPDIR}/installed_pkg_${pkg}" ]]; then
                 echo "ii  ${pkg}  1.0.0  amd64"
                 return 0
             fi
             # Special case for FUSE if needed by tests
             if [[ "$pkg" == "fuse" && -f "${BATS_TEST_TMPDIR}/fuse_installed" ]]; then
                  echo "ii  fuse  1.0.0 amd64"
                  return 0
             fi
             return 1
        fi

        # Install package (mocked via -i)
        if [[ "$1" == "-i" ]]; then
             echo "dpkg -i $2" >> "${LOG_FILE}"
             return 0
        fi
        
        echo "dpkg $*" >> "${LOG_FILE}"
        return 0
    }
    export -f dpkg

    # Mock wget
    function wget() {
        echo "wget $*" >> "${LOG_FILE}"
        # If output file specified, create it
        local output_file=""
        while [[ $# -gt 0 ]]; do
            if [[ "$1" == "-O" ]]; then
                output_file="$2"
                break
            fi
            if [[ "$1" == "-qO-" ]]; then
                # Output to stdout
                echo "mock-content"
                return 0
            fi
            shift
        done
        if [[ -n "$output_file" ]]; then
            touch "$output_file"
        fi
        return 0
    }
    export -f wget
    
    # Mock curl
    function curl() {
        echo "curl $*" >> "${LOG_FILE}"
        # Return mock JSON for GitHub API
        if [[ "$*" =~ "api.github.com" ]]; then
             echo '{ "assets": [ { "name": "app.AppImage", "browser_download_url": "https://example.com/app.AppImage" } ] }'
        fi
        return 0
    }
    export -f curl
    
    # Mock gpg
    function gpg() { echo "gpg $*" >> "${LOG_FILE}"; cat > "${VSCODE_GPG_KEY}"; return 0; }
    export -f gpg
    
    # Mock command
    function command() {
        if [[ "$1" == "-v" ]]; then
             if [[ "$2" == "code" ]]; then echo "${MOCK_BIN_DIR}/code"; return 0; fi
             if [[ "$2" == "cursor" ]]; then echo "${MOCK_BIN_DIR}/cursor"; return 0; fi
             if [[ "$2" == "antigravity" ]]; then echo "${MOCK_BIN_DIR}/antigravity"; return 0; fi
             if [[ "$2" == "wget" || "$2" == "curl" || "$2" == "gpg" || "$2" == "jq" ]]; then echo "/usr/bin/$2"; return 0; fi
             return 0
        fi
        return 0 
    }
    export -f command
    
    # Create mock binaries
    touch "${MOCK_BIN_DIR}/code" && chmod +x "${MOCK_BIN_DIR}/code"
    touch "${MOCK_BIN_DIR}/cursor" && chmod +x "${MOCK_BIN_DIR}/cursor"
    touch "${MOCK_BIN_DIR}/antigravity" && chmod +x "${MOCK_BIN_DIR}/antigravity"
    
    # Mock timeout
    function timeout() { shift; "$@"; } # Shift duration, run command
    export -f timeout
    
    # Mock id
    function id() { return 0; }
    export -f id
    
    # Mock useradd/userdel
    function useradd() { echo "useradd $*" >> "${LOG_FILE}"; return 0; }
    export -f useradd
    function userdel() { echo "userdel $*" >> "${LOG_FILE}"; return 0; }
    export -f userdel
    
    # Mock getent
    function getent() { echo "testuser:x:1000:1000:test:${BATS_TEST_TMPDIR}/home/testuser:/bin/bash"; }
    export -f getent
    
    # Mock chown
    function chown() { echo "chown $*" >> "${LOG_FILE}"; return 0; }
    export -f chown
    
    # Mock Checkpoint functions to avoid root requirement
    checkpoint_exists() {
        local phase="$1"
        [ -f "${CHECKPOINT_DIR}/${phase}" ]
    }
    export -f checkpoint_exists

    checkpoint_create() {
        local phase="$1"
        mkdir -p "${CHECKPOINT_DIR}"
        touch "${CHECKPOINT_DIR}/${phase}"
        return 0
    }
    export -f checkpoint_create
    
    # Mock desktop install checkpoint
    mkdir -p "${CHECKPOINT_DIR}"
    touch "${CHECKPOINT_DIR}/desktop-install"

    # Source all IDE modules
    source "${BATS_TEST_DIRNAME}/../../lib/modules/ide-vscode.sh"
    source "${BATS_TEST_DIRNAME}/../../lib/modules/ide-cursor.sh"
    source "${BATS_TEST_DIRNAME}/../../lib/modules/ide-antigravity.sh"
}

teardown() {
    rm -rf "${BATS_TEST_TMPDIR}"
}

# --- VSCode Tests ---

@test "ide_vscode_check_prerequisites: passes when desktop-install checkpoint exists" {
    # Ensure checkpoint matches what the module expects (overridden or default)
    # The module uses "desktop-install". We created it in setup.
    run ide_vscode_check_prerequisites
    [ "$status" -eq 0 ]
}

@test "ide_vscode_check_prerequisites: fails when desktop-install checkpoint missing" {
    rm -f "${CHECKPOINT_DIR}/desktop-install"
    run ide_vscode_check_prerequisites
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Desktop environment not installed" ]]
}

@test "ide_vscode_add_gpg_key: adds Microsoft GPG key" {
    run ide_vscode_add_gpg_key
    [ "$status" -eq 0 ]
    [ -f "${VSCODE_GPG_KEY}" ]
}

@test "ide_vscode_add_repository: adds VSCode repository" {
    run ide_vscode_add_repository
    [ "$status" -eq 0 ]
    [ -f "${VSCODE_LIST}" ]
}

@test "ide_vscode_configure: creates VSCode config with telemetry disabled" {
    # Mock home dir creation
    local user_home="${BATS_TEST_TMPDIR}/home/testuser"
    mkdir -p "${user_home}"
    
    run ide_vscode_configure "testuser"
    [ "$status" -eq 0 ]
    
    # Verify config path
    [ -f "${user_home}/.config/Code/User/settings.json" ]
    grep -q '"telemetry.enableTelemetry": false' "${user_home}/.config/Code/User/settings.json"
}

@test "ide_vscode_verify: passes when VSCode is installed" {
    # Mock code command
    function code() { return 0; }
    export -f code
    
    # Mock files
    touch "${VSCODE_DESKTOP}"
    touch "${BATS_TEST_TMPDIR}/installed_pkg_code"
    
    # Mock timeout again specifically for this test if needed, but global mock should work
    
    run ide_vscode_verify
    [ "$status" -eq 0 ]
}

# --- Cursor Tests ---

@test "ide_cursor_check_prerequisites: passes when desktop-install checkpoint exists" {
    run ide_cursor_check_prerequisites
    [ "$status" -eq 0 ]
}

@test "ide_cursor_create_launcher_appimage: creates desktop launcher" {
    run ide_cursor_create_launcher_appimage
    [ "$status" -eq 0 ]
    [ -f "${CURSOR_DESKTOP}" ]
    grep -q "Name=Cursor" "${CURSOR_DESKTOP}"
}

@test "ide_cursor_verify: passes when Cursor is installed" {
     # Mock cursor command
     function cursor() { return 0; }
     export -f cursor
     
     # Mock launcher
     touch "${CURSOR_DESKTOP}"
     
     # Mock installation (AppImage)
     touch "${CURSOR_APPIMAGE}"
     chmod +x "${CURSOR_APPIMAGE}"
     
     run ide_cursor_verify
     [ "$status" -eq 0 ]
}

# --- Antigravity Tests ---

@test "ide_antigravity_check_prerequisites: passes when desktop-install checkpoint exists" {
    run ide_antigravity_check_prerequisites
    [ "$status" -eq 0 ]
}

@test "ide_antigravity_install_fuse: installs FUSE for AppImage support" {
    # Mock apt-get to simulate install
    function apt-get() {
        if [[ "$1" == "install" ]]; then
            touch "${BATS_TEST_TMPDIR}/fuse_installed"
        fi
        return 0
    }
    export -f apt-get
    
    run ide_antigravity_install_fuse
    [ "$status" -eq 0 ]
}

@test "ide_antigravity_create_launcher: creates desktop launcher" {
    run ide_antigravity_create_launcher
    [ "$status" -eq 0 ]
    [ -f "${ANTIGRAVITY_DESKTOP}" ]
    grep -q "Name=Antigravity" "${ANTIGRAVITY_DESKTOP}"
}

@test "ide_antigravity_verify: passes when Antigravity is installed" {
    # Mock command
    function antigravity() { return 0; }
    export -f antigravity
    
    # Mock files
    touch "${ANTIGRAVITY_APPIMAGE}"
    chmod +x "${ANTIGRAVITY_APPIMAGE}"
    touch "${ANTIGRAVITY_DESKTOP}"
    
    # Mock symlink location check (validate_installation checks /usr/local/bin path specifically)
    # The module checks: if [[ "$antigravity_path" != "/usr/local/bin/antigravity" ]]; then
    # We can't easily mock `command -v` to return a specific path unless we alias it or put it in PATH.
    # But it is just a warning, so it shouldn't fail the test.
    
    run ide_antigravity_verify
    [ "$status" -eq 0 ]
}

# --- Full Workflows ---

@test "integration: VSCode execute completes successfully" {
    # Mock successful steps
    function ide_vscode_check_prerequisites() { return 0; }
    export -f ide_vscode_check_prerequisites
    function ide_vscode_add_gpg_key() { return 0; }
    export -f ide_vscode_add_gpg_key
    function ide_vscode_add_repository() { return 0; }
    export -f ide_vscode_add_repository
    function ide_vscode_update_apt() { return 0; }
    export -f ide_vscode_update_apt
    function ide_vscode_install_package() { return 0; }
    export -f ide_vscode_install_package
    function ide_vscode_verify() { return 0; }
    export -f ide_vscode_verify
    function ide_vscode_configure() { return 0; }
    export -f ide_vscode_configure

    run ide_vscode_execute
    [ "$status" -eq 0 ]
    [ -f "${CHECKPOINT_DIR}/${VSCODE_CHECKPOINT}" ]
}

@test "integration: Cursor execute completes successfully" {
    # Mock successful steps
    function ide_cursor_check_prerequisites() { return 0; }
    export -f ide_cursor_check_prerequisites
    function ide_cursor_install_deb() { return 0; } # Prefer DEB
    export -f ide_cursor_install_deb
    function ide_cursor_verify() { return 0; }
    export -f ide_cursor_verify

    run ide_cursor_execute
    [ "$status" -eq 0 ]
    [ -f "${CHECKPOINT_DIR}/${CURSOR_CHECKPOINT}" ]
}

@test "integration: Antigravity execute completes successfully" {
    # Mock successful steps
    function ide_antigravity_check_prerequisites() { return 0; }
    export -f ide_antigravity_check_prerequisites
    function ide_antigravity_install_fuse() { return 0; }
    export -f ide_antigravity_install_fuse
    function ide_antigravity_fetch_url() { echo "http://example.com/app.AppImage"; }
    export -f ide_antigravity_fetch_url
    function ide_antigravity_install_appimage() { return 0; }
    export -f ide_antigravity_install_appimage
    function ide_antigravity_create_launcher() { return 0; }
    export -f ide_antigravity_create_launcher
    function ide_antigravity_create_cli_alias() { return 0; }
    export -f ide_antigravity_create_cli_alias
    function ide_antigravity_verify() { return 0; }
    export -f ide_antigravity_verify
    
    run ide_antigravity_execute
    [ "$status" -eq 0 ]
    [ -f "${CHECKPOINT_DIR}/${ANTIGRAVITY_CHECKPOINT}" ]
}
