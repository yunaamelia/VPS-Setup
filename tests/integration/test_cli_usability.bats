#!/usr/bin/env bats
# test_cli_usability.bats - Tests for Command-Line Usability features (T115-T120)

load '../test_helper'

setup() {
  # Create temp directory for test artifacts
  TEST_DIR="${BATS_TEST_TMPDIR}/cli_test"
  mkdir -p "${TEST_DIR}"
  
  # Set test environment
  export PROJECT_ROOT="${BATS_TEST_DIRNAME}/../.."
  export LIB_DIR="${PROJECT_ROOT}/lib"
  export LOG_FILE="${TEST_DIR}/test.log"
  export CHECKPOINT_DIR="${TEST_DIR}/checkpoints"
  export STATE_DIR="${TEST_DIR}/state"
  
  # Source required modules
  source "${LIB_DIR}/core/logger.sh"
  source "${LIB_DIR}/core/ux.sh"
}

teardown() {
  # Cleanup test directory
  rm -rf "${TEST_DIR}"
}

# T115: Enhanced --help output with 3+ examples
@test "T115: --help displays usage syntax and options" {
  run "${PROJECT_ROOT}/bin/vps-provision" --help
  
  assert_success
  assert_output --partial "USAGE:"
  assert_output --partial "DESCRIPTION:"
  assert_output --partial "OPTIONS:"
  assert_output --partial "EXAMPLES:"
  assert_output --partial "EXIT CODES:"
}

@test "T115: --help includes at least 3 examples" {
  run "${PROJECT_ROOT}/bin/vps-provision" --help
  
  assert_success
  
  # Count example lines (lines starting with vps-provision in EXAMPLES section)
  local example_count=$(echo "$output" | grep -c "^\s*vps-provision" || true)
  
  [[ ${example_count} -ge 3 ]]
}

@test "T115: --help includes Quick Start section" {
  run "${PROJECT_ROOT}/bin/vps-provision" --help
  
  assert_success
  assert_output --partial "QUICK START:"
}

# T116: Interactive prompts for missing arguments
@test "T116: ux_prompt_input returns user input" {
  # Simulate user input - need to source all dependencies
  run bash -c 'echo "testvalue" | (source '"${LIB_DIR}"'/core/logger.sh && source '"${LIB_DIR}"'/core/ux.sh && ux_prompt_input "Enter value" 2>/dev/null)'
  
  assert_success
  assert_success
  assert_output --partial "testvalue"
}

@test "T116: ux_prompt_input uses default when empty input" {
  # Simulate empty input (just press enter)
  run bash -c 'echo "" | (source '"${LIB_DIR}"'/core/logger.sh && source '"${LIB_DIR}"'/core/ux.sh && ux_prompt_input "Enter value" "default_val" 2>/dev/null)'
  
  assert_success
  assert_output --partial "default_val"
}

@test "T116: ux_prompt_input fails in non-interactive mode without default" {
  # Disable interactive mode
  run bash -c 'export UX_INTERACTIVE=false && source '"${LIB_DIR}"'/core/logger.sh && source '"${LIB_DIR}"'/core/ux.sh && ux_prompt_input "Enter value" 2>/dev/null </dev/null'
  
  assert_failure
}

@test "T116: ux_prompt_confirm returns 0 for yes" {
  # Simulate "y" input
  run bash -c 'echo "y" | (source '"${LIB_DIR}"'/core/logger.sh && source '"${LIB_DIR}"'/core/ux.sh && ux_prompt_confirm "Confirm?" 2>/dev/null)'
  
  assert_success
}

@test "T116: ux_prompt_confirm returns 1 for no" {
  # Simulate "n" input
  run bash -c 'echo "n" | (source '"${LIB_DIR}"'/core/logger.sh && source '"${LIB_DIR}"'/core/ux.sh && ux_prompt_confirm "Confirm?" 2>/dev/null)'
  
  assert_failure
}

# T117: Standard shortcuts (-y, -v, -h)
@test "T117: -h is alias for --help" {
  run "${PROJECT_ROOT}/bin/vps-provision" -h
  
  assert_success
  assert_output --partial "USAGE:"
}

@test "T117: -v is alias for --version" {
  run "${PROJECT_ROOT}/bin/vps-provision" -v
  
  assert_success
  assert_output --partial "vps-provision version"
}

@test "T117: -y is alias for --yes" {
  # Copy script and link lib to test dir
  mkdir -p "${TEST_DIR}/bin"
  cp "${PROJECT_ROOT}/bin/vps-provision" "${TEST_DIR}/bin/vps-provision"
  chmod +x "${TEST_DIR}/bin/vps-provision"
  ln -sf "${PROJECT_ROOT}/lib" "${TEST_DIR}/lib"
  
  # Configure state dir override
  export VPS_PROVISION_STATE_DIR="${TEST_DIR}/state"
  
  # Patch EUID check to allow non-root execution for testing
  sed -i 's/if \[\[ $EUID -ne 0 \]\]/if [[ 0 -ne 0 ]]/' "${TEST_DIR}/bin/vps-provision"
  
  # Run with -y and --dry-run and --skip-validation (to bypass system checks)
  # We expect success and no prompt output
  run "${TEST_DIR}/bin/vps-provision" -y --dry-run --skip-validation
  
  assert_success
  # Verify yes mode was active (logs might show it or behavior)
  assert_output --partial "DRY RUN MODE"
}

@test "T117: -c is alias for --config" {
  # Create a test config file
  echo "TEST_CONFIG=true" > "${TEST_DIR}/test.conf"
  
  # This would fail in actual execution but we're testing argument parsing
  run "${PROJECT_ROOT}/bin/vps-provision" -c "${TEST_DIR}/test.conf" --dry-run 2>&1 || true
  
  # Should not error on config argument parsing
  [[ ! "$output" =~ "Unknown option: -c" ]]
}

# T118: Bash completion script
@test "T118: bash completion script exists" {
  [[ -f "${PROJECT_ROOT}/etc/bash-completion.d/vps-provision" ]]
}

@test "T118: bash completion script defines completion function" {
  run grep -q "_vps_provision_completions" "${PROJECT_ROOT}/etc/bash-completion.d/vps-provision"
  
  assert_success
}

@test "T118: bash completion script registers completion" {
  run grep -q "complete -F _vps_provision_completions vps-provision" \
    "${PROJECT_ROOT}/etc/bash-completion.d/vps-provision"
  
  assert_success
}

@test "T118: bash completion script includes all options" {
  local completion_file="${PROJECT_ROOT}/etc/bash-completion.d/vps-provision"
  
  # Check for key options
  grep -q -- "--help" "${completion_file}"
  grep -q -- "--version" "${completion_file}"
  grep -q -- "--yes" "${completion_file}"
  grep -q -- "--dry-run" "${completion_file}"
  grep -q -- "--config" "${completion_file}"
  grep -q -- "--log-level" "${completion_file}"
}

@test "T118: bash completion script includes all phases" {
  local completion_file="${PROJECT_ROOT}/etc/bash-completion.d/vps-provision"
  
  # Check for key phases
  grep -q "system-prep" "${completion_file}"
  grep -q "desktop-install" "${completion_file}"
  grep -q "ide-vscode" "${completion_file}"
  grep -q "verification" "${completion_file}"
}

# T119: Non-interactive shell detection
@test "T119: ux_detect_interactive detects TTY" {
  # This test runs in interactive mode (bats provides TTY)
  run bash -c 'source '"${LIB_DIR}"'/core/ux.sh && ux_detect_interactive && echo "TTY: ${UX_INTERACTIVE}"'
  
  assert_success
}

@test "T119: ux_detect_interactive detects non-TTY" {
  # Run without TTY
  run bash -c 'source '"${LIB_DIR}"'/core/ux.sh && ux_detect_interactive && echo "TTY: ${UX_INTERACTIVE}" </dev/null'
  
  assert_success
  assert_output --partial "false"
}

@test "T119: ux_prompt_input fails in non-interactive without default" {
  # Disable TTY and interactive mode
  export UX_INTERACTIVE=false
  
  run bash -c 'source '"${LIB_DIR}"'/core/ux.sh && ux_prompt_input "Test" </dev/null'
  
  assert_failure
}

@test "T119: --yes mode bypasses prompts" {
  export UX_YES_MODE=true
  
  run bash -c 'source '"${LIB_DIR}"'/core/ux.sh && ux_prompt_confirm "Confirm?"'
  
  # Should auto-confirm (return 0) without prompting
  assert_success
}

# T120: Terminal width detection
@test "T120: ux_detect_terminal_width sets default width" {
  run bash -c 'source '"${LIB_DIR}"'/core/ux.sh && ux_detect_terminal_width && echo "${UX_TERMINAL_WIDTH}"'
  
  assert_success
  
  # Should have some positive width value
  [[ ${output} -gt 0 ]]
}

@test "T120: ux_detect_terminal_width respects COLUMNS" {
  run bash -c 'export COLUMNS=120 && source '"${LIB_DIR}"'/core/logger.sh && source '"${LIB_DIR}"'/core/ux.sh && ux_detect_terminal_width && echo "${UX_TERMINAL_WIDTH}"'
  
  assert_success
  assert_output "120"
}

@test "T120: ux_detect_terminal_width enforces minimum width" {
  export COLUMNS=10  # Too narrow
  
  run bash -c 'source '"${LIB_DIR}"'/core/ux.sh && ux_detect_terminal_width && echo "${UX_TERMINAL_WIDTH}"'
  
  assert_success
  
  # Should use default (80) instead of too-narrow value
  [[ ${output} -eq 80 ]]
}

@test "T120: ux_wrap_text wraps long text" {
  export UX_TERMINAL_WIDTH=40
  local long_text="This is a very long line of text that should be wrapped to fit within the terminal width limit"
  
  run bash -c 'source '"${LIB_DIR}"'/core/ux.sh && ux_detect_terminal_width && ux_wrap_text "'"${long_text}"'"'
  
  assert_success
  
  # Output should have multiple lines
  local line_count=$(echo "$output" | wc -l)
  [[ ${line_count} -gt 1 ]]
}

@test "T120: ux_wrap_text handles indentation" {
  export UX_TERMINAL_WIDTH=60
  local text="This text should be indented"
  
  run bash -c 'source '"${LIB_DIR}"'/core/ux.sh && ux_detect_terminal_width && ux_wrap_text "'"${text}"'" 4'
  
  assert_success
  
  # Output should start with spaces
  [[ "$output" =~ ^[[:space:]] ]]
}

# Integration test: UX init
@test "UX system initialization" {
  run bash -c 'source '"${LIB_DIR}"'/core/ux.sh && ux_init && echo "OK"'
  
  assert_success
  assert_output --partial "OK"
}

@test "UX system sets terminal width on init" {
  run bash -c 'source '"${LIB_DIR}"'/core/ux.sh && ux_init && echo "${UX_TERMINAL_WIDTH}"'
  
  assert_success
  
  # Should have positive width
  [[ ${output} -gt 0 ]]
}

# Accessibility features
@test "ux_prompt functions work with --no-color" {
  run bash -c 'export NO_COLOR=1 && export UX_INTERACTIVE=true && echo "y" | (source '"${LIB_DIR}"'/core/logger.sh && source '"${LIB_DIR}"'/core/ux.sh && ux_init && ux_prompt_confirm "Test")' 2>/dev/null'
  
  assert_success
}

# Error handling
@test "ux_prompt_input validates with custom function" {
  # Define validation function that rejects "bad"
  validate_test() {
    [[ "$1" != "bad" ]]
  }
  export -f validate_test
  
  run bash -c 'echo "bad" | source '"${LIB_DIR}"'/core/ux.sh && ux_prompt_input "Enter" "" validate_test'
  
  assert_failure
}

@test "ux_prompt_password hides input" {
  # This test is limited as we can't easily test hidden input in bats
  skip "Password hiding requires TTY interaction testing"
}
