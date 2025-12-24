#!/usr/bin/env bash
# Bats Test Helper
# Common functions and assertions for all test suites

# Load bats support libraries if available
if [[ -d "${BATS_TEST_DIRNAME}/../node_modules/bats-support" ]]; then
  load "${BATS_TEST_DIRNAME}/../node_modules/bats-support/load"
  load "${BATS_TEST_DIRNAME}/../node_modules/bats-assert/load"
else
  # Provide minimal assert functions if bats-assert not available
  assert_success() {
    if [[ "${status}" -ne 0 ]]; then
      echo "Expected success but got status: ${status}" >&2
      echo "Output: ${output}" >&2
      return 1
    fi
  }

  assert() {
    if ! "$@"; then
      echo "Assertion failed: $*" >&2
      return 1
    fi
  }
  
  assert_failure() {
    if [[ "${status}" -eq 0 ]]; then
      echo "Expected failure but got success" >&2
      echo "Output: ${output}" >&2
      return 1
    fi
    
    # If specific exit code provided
    if [[ -n "${1:-}" ]]; then
      if [[ "${status}" -ne "$1" ]]; then
        echo "Expected exit code $1 but got: ${status}" >&2
        return 1
      fi
    fi
  }
  
  assert_output() {
    local expected=""
    local mode="exact"
    
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --partial)
          mode="partial"
          shift
          ;;
        --regexp)
          mode="regexp"
          shift
          ;;
        *)
          expected="$1"
          shift
          ;;
      esac
    done
    
    case "${mode}" in
      exact)
        if [[ "${output}" != "${expected}" ]]; then
          echo "Output mismatch:" >&2
          echo "Expected: ${expected}" >&2
          echo "Got: ${output}" >&2
          return 1
        fi
        ;;
      partial)
        if [[ "${output}" != *"${expected}"* ]]; then
          echo "Output does not contain expected text:" >&2
          echo "Expected substring: ${expected}" >&2
          echo "Got: ${output}" >&2
          return 1
        fi
        ;;
      regexp)
        if ! [[ "${output}" =~ ${expected} ]]; then
          echo "Output does not match regex:" >&2
          echo "Expected pattern: ${expected}" >&2
          echo "Got: ${output}" >&2
          return 1
        fi
        ;;
    esac
  }
  
  assert_line() {
    local line_match=""
    local mode="exact"
    
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --partial)
          mode="partial"
          shift
          ;;
        --regexp)
          mode="regexp"
          shift
          ;;
        *)
          line_match="$1"
          shift
          ;;
      esac
    done
    
    # Check if any line matches
    local found=false
    while IFS= read -r line; do
      case "${mode}" in
        exact)
          if [[ "${line}" == "${line_match}" ]]; then
            found=true
            break
          fi
          ;;
        partial)
          if [[ "${line}" == *"${line_match}"* ]]; then
            found=true
            break
          fi
          ;;
        regexp)
          if [[ "${line}" =~ ${line_match} ]]; then
            found=true
            break
          fi
          ;;
      esac
    done <<< "${output}"
    
    if [[ "${found}" == "false" ]]; then
      echo "No line matches:" >&2
      echo "Expected: ${line_match}" >&2
      echo "Output lines:" >&2
      echo "${output}" >&2
      return 1
    fi
  }
fi

# Common test setup
common_setup() {
  # Set up temporary directory for tests
  export TEST_TEMP_DIR="$(mktemp -d)"
  
  # Ensure cleanup on exit
  trap "rm -rf '${TEST_TEMP_DIR}'" EXIT
}

# Common test teardown
common_teardown() {
  # Cleanup temporary directory
  if [[ -n "${TEST_TEMP_DIR:-}" ]] && [[ -d "${TEST_TEMP_DIR}" ]]; then
    rm -rf "${TEST_TEMP_DIR}"
  fi
}

# Helper: Create mock file
create_mock_file() {
  local filepath="$1"
  local content="${2:-}"
  
  mkdir -p "$(dirname "${filepath}")"
  echo "${content}" > "${filepath}"
}

# Helper: Mock command
mock_command() {
  local cmd_name="$1"
  local mock_output="${2:-}"
  local mock_exit_code="${3:-0}"
  
  local mock_script="${TEST_TEMP_DIR}/bin/${cmd_name}"
  mkdir -p "${TEST_TEMP_DIR}/bin"
  
  cat > "${mock_script}" <<EOF
#!/bin/bash
echo "${mock_output}"
exit ${mock_exit_code}
EOF
  
  chmod +x "${mock_script}"
  export PATH="${TEST_TEMP_DIR}/bin:${PATH}"
}

# Export functions
export -f common_setup
export -f common_teardown
export -f create_mock_file
export -f mock_command
