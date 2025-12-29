# Code Exemplars Blueprint - VPS Provisioning Tool

## Purpose

This document identifies high-quality, representative code examples in the VPS Provisioning Tool codebase. These exemplars demonstrate our coding standards, architectural patterns, and best practices. Use these examples as references when implementing new features or maintaining existing code.

**Project Type**: Shell Scripting (Bash) with Python Utilities  
**Last Updated**: December 29, 2025

---

## Table of Contents

1. [Shell Script Exemplars](#shell-script-exemplars)
   - [Core Library Modules](#core-library-modules)
   - [Provisioning Modules](#provisioning-modules)
   - [CLI Interface](#cli-interface)
2. [Python Utility Exemplars](#python-utility-exemplars)
3. [Testing Exemplars](#testing-exemplars)
4. [Architecture Patterns](#architecture-patterns)
5. [Recommendations](#recommendations)

---

## Shell Script Exemplars

### Core Library Modules

#### 1. **lib/core/logger.sh** - Structured Logging Framework

**Why Exemplary**:

- Perfect double-sourcing prevention with guard pattern
- Comprehensive documentation with inline comments
- Flexible configuration (test vs production environments)
- Multiple output targets (console + file with different formats)
- Accessibility considerations (color coding with text labels)
- Proper use of readonly variables with test environment exceptions

**Key Patterns Demonstrated**:

```bash
# Guard pattern prevents multiple sourcing
if [[ -n "${_LOGGER_SH_LOADED:-}" ]]; then
  return 0
fi
readonly _LOGGER_SH_LOADED=1

# Test-aware configuration (non-readonly in test environments)
if [[ -z "${BATS_TEST_TMPDIR:-}" ]]; then
  readonly LOG_DIR="${LOG_DIR:-/var/log/vps-provision}"
else
  LOG_DIR="${LOG_DIR:-/var/log/vps-provision}"
fi

# Accessibility: Color with text labels (UX-021)
readonly LABEL_INFO="[OK]"      # Success indicator
readonly LABEL_WARNING="[WARN]" # Warning indicator
readonly COLOR_INFO='\033[32m'  # Green
```

**Use This Pattern When**:

- Creating new core library modules
- Implementing logging in any module
- Handling test vs production environment differences
- Building accessible terminal output

---

#### 2. **lib/core/transaction.sh** - LIFO Rollback System

**Why Exemplary**:

- Clean separation of concerns (logging, recording, parsing)
- Transaction format enables automated rollback
- Timestamp tracking for audit trail
- Robust error handling with validation
- Uses logger for output consistency

**Key Patterns Demonstrated**:

```bash
# Record action with rollback command
transaction_record() {
  local action="$1"
  local rollback_cmd="$2"
  local timestamp

  if [[ -z "$action" ]] || [[ -z "$rollback_cmd" ]]; then
    log_error "Transaction record requires both action and rollback command"
    return 1
  fi

  timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  # Format: TIMESTAMP|ACTION|ROLLBACK_COMMAND
  echo "${timestamp}|${action}|${rollback_cmd}" >>"$TRANSACTION_LOG"

  log_debug "Transaction recorded: $action"
  return 0
}

# LIFO retrieval using tac (reverse order)
transaction_get_all_reverse() {
  if [[ ! -f "$TRANSACTION_LOG" ]]; then
    return 0
  fi
  tac "$TRANSACTION_LOG"
}
```

**Use This Pattern When**:

- Implementing state-changing operations that need rollback
- Building automated recovery systems
- Creating audit trails
- Ensuring idempotency

---

#### 3. **lib/core/checkpoint.sh** - Idempotency Mechanism

**Why Exemplary**:

- Enables safe re-runs after failures
- Simple file-based checkpoint storage
- Validation ensures checkpoint integrity
- Metadata capture (timestamp, host, user)
- Clear public API (create, exists, validate, clear)

**Key Patterns Demonstrated**:

```bash
# Check if already completed
if checkpoint_exists "system-prep"; then
  log_info "System prep already completed (checkpoint found)"
  return 0
fi

# Do work...

# Mark complete
checkpoint_create "system-prep"

# Checkpoint file format with metadata
cat >"$checkpoint_file" <<EOF
CHECKPOINT_NAME="$checkpoint_name"
CREATED_AT="$timestamp"
HOSTNAME="$(hostname)"
USER="$(whoami)"
EOF
```

**Use This Pattern When**:

- Implementing long-running operations
- Building resumable processes
- Creating phase-based workflows
- Ensuring operations run exactly once

---

#### 4. **lib/core/progress.sh** - Weighted Progress Tracking

**Why Exemplary**:

- Weighted phases for accurate time estimation
- Performance instrumentation with timing data
- Multiple progress indicators (percentage, time, spinner)
- State persistence for session continuity
- Visual hierarchy with accessibility support
- Comprehensive progress reporting

**Key Patterns Demonstrated**:

```bash
# Phase weight configuration for accurate estimation
declare -gA PHASE_WEIGHTS=(
  [system-prep]=10
  [desktop-install]=15
  [rdp-config]=8
  [user-creation]=5
  [ide-vscode]=12
  [ide-cursor]=12
  [ide-antigravity]=10
  [terminal-setup]=6
  [dev-tools]=8
  [verification]=14
)

# Phase timing tracking (associative arrays)
declare -gA PHASE_START_TIMES
declare -gA PHASE_END_TIMES
declare -gA PHASE_DURATIONS

# Visual indicators with accessibility
readonly SPINNER_CHARS='-\\|/'  # Simple, screen-reader friendly
```

**Use This Pattern When**:

- Building long-running operations with user feedback
- Implementing progress bars or indicators
- Creating time estimation systems
- Tracking performance metrics

---

#### 5. **lib/core/error-handler.sh** - Error Classification & Recovery

**Why Exemplary**:

- Error classification system with specific types
- Circuit breaker pattern for cascading failure prevention
- Retry logic with exponential backoff
- Exit code whitelisting
- Actionable error suggestions for users
- Clean error type constants

**Key Patterns Demonstrated**:

```bash
# Error type constants
readonly E_NETWORK="E_NETWORK"
readonly E_DISK="E_DISK"
readonly E_LOCK="E_LOCK"
readonly E_PKG_CORRUPT="E_PKG_CORRUPT"

# Error classification based on exit code and output
error_classify() {
  local exit_code="$1"
  local stderr="${2:-}"
  local stdout="${3:-}"
  local combined="${stderr} ${stdout}"

  # Check specific patterns
  if [[ "$exit_code" -eq 124 ]]; then
    echo "$E_TIMEOUT"
    return 0
  fi
  # ... more classification logic
}

# Actionable suggestions (UX-008)
readonly -A ERROR_SUGGESTIONS=(
  ["$E_NETWORK"]="Check internet connection and DNS resolution."
  ["$E_DISK"]="Free up disk space by removing unnecessary files."
)
```

**Use This Pattern When**:

- Implementing error handling in any module
- Building retry logic for network operations
- Creating user-friendly error messages
- Implementing circuit breaker patterns

---

### Provisioning Modules

#### 6. **lib/modules/system-prep.sh** - Complete Module Implementation

**Why Exemplary**:

- Demonstrates ALL core patterns in one module
- Clear module structure with constants section
- Checkpoint-based idempotency
- Transaction logging for rollback
- Progress reporting integration
- Comprehensive documentation
- Array usage for package lists
- Retry logic for network operations
- Configuration file generation with heredoc

**Key Patterns Demonstrated**:

```bash
#!/bin/bash
# Module header with purpose and dependencies
set -euo pipefail

# Guard pattern
if [[ -n "${_SYSTEM_PREP_SH_LOADED:-}" ]]; then
  return 0
fi
readonly _SYSTEM_PREP_SH_LOADED=1

# Source all dependencies
source "${LIB_DIR}/core/logger.sh"
source "${LIB_DIR}/core/checkpoint.sh"
source "${LIB_DIR}/core/transaction.sh"
source "${LIB_DIR}/core/progress.sh"

# Module constants
readonly SYSTEM_PREP_PHASE="system-prep"
readonly -a CORE_PACKAGES=(
  "build-essential"
  "curl"
  "wget"
  # ...
)

# Main execution function with checkpoint
system_prep_execute() {
  if checkpoint_exists "$SYSTEM_PREP_PHASE"; then
    log_info "System prep already completed"
    return 0
  fi

  # Work...
  system_prep_configure_apt
  system_prep_update_apt
  system_prep_install_core_packages

  # Mark complete
  checkpoint_create "$SYSTEM_PREP_PHASE"
}

# APT configuration with heredoc
system_prep_configure_apt() {
  cat >"${APT_CUSTOM_CONF}" <<'EOF'
# Parallel downloads for performance
APT::Acquire::Max-Parallel "3";
EOF

  transaction_log "create_file" "${APT_CUSTOM_CONF}" "rm -f '${APT_CUSTOM_CONF}'"
}

# Retry logic
system_prep_update_apt() {
  local max_retries=3
  local retry_delay=5

  for attempt in $(seq 1 ${max_retries}); do
    if apt-get update 2>&1 | tee -a "${LOG_FILE}"; then
      log_info "APT updated successfully"
      return 0
    fi

    if [[ ${attempt} -lt ${max_retries} ]]; then
      log_warning "Retry ${attempt}/${max_retries}..."
      sleep ${retry_delay}
    fi
  done

  log_error "Failed after ${max_retries} attempts"
  return 1
}
```

**Use This Pattern When**:

- Creating new provisioning modules
- Implementing any module with state changes
- Building resumable operations
- Integrating with core libraries

---

### CLI Interface

#### 7. **bin/vps-provision** - Main CLI Entry Point

**Why Exemplary**:

- Comprehensive help documentation
- Argument parsing with validation
- Configuration loading
- Error handling at top level
- Version information
- Multiple output formats
- Dry-run mode support
- Resume and force modes

**Key Patterns Demonstrated**:

```bash
#!/bin/bash
set -euo pipefail

# Version constants
readonly VERSION="1.0.0"
readonly BUILD_DATE="2025-12-24"

# Source all core libraries
source "${LIB_DIR}/core/logger.sh"
source "${LIB_DIR}/core/config.sh"
# ... more sources

# Help function with heredoc
show_help() {
  cat <<'EOF'
USAGE:
    vps-provision [OPTIONS]

DESCRIPTION:
    Automates provisioning of Debian 13 VPS...

OPTIONS:
    -h, --help              Display this help
    --dry-run               Show planned actions
    --resume                Resume from checkpoint
EOF
}

# Argument parsing
parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help) show_help; exit 0 ;;
      --dry-run) DRY_RUN=true ;;
      --resume) RESUME_MODE=true ;;
      *) log_error "Unknown option: $1"; exit 1 ;;
    esac
    shift
  done
}

# Main execution
main() {
  parse_args "$@"

  # Initialize systems
  logger_init
  checkpoint_init

  # Execute phases...

  # Report results
  show_summary
}

main "$@"
```

**Use This Pattern When**:

- Creating new CLI tools
- Implementing argument parsing
- Building help documentation
- Structuring main entry points

---

## Python Utility Exemplars

### 8. **lib/utils/health-check.py** - Structured Validation

**Why Exemplary**:

- Comprehensive docstring with usage examples
- Type hints for clarity
- Multiple output formats (text, JSON)
- Structured result format (tri-state: pass/fail/error)
- Clean class-based design
- Proper exception handling
- Command execution wrapper with result tuples

**Key Patterns Demonstrated**:

```python
#!/usr/bin/env python3
"""
Health Check Utility
Post-installation validation of all provisioned components

Usage:
    python3 health-check.py [--output FORMAT] [--verbose]

Checks:
    - System validation (OS, resources)
    - Desktop environment (XFCE, LightDM)
    - RDP server (xrdp service, port availability)
"""

class HealthCheck:
    """Post-installation validation checks"""

    def __init__(self, verbose: bool = False):
        self.verbose = verbose
        self.results: List[Dict[str, Any]] = []

    def run_command(self, cmd: List[str]) -> Tuple[bool, str, str]:
        """
        Run a command and return result

        Returns:
            Tuple of (success: bool, stdout: str, stderr: str)
        """
        try:
            result = subprocess.run(
                cmd, capture_output=True, text=True, check=False
            )
            return (result.returncode == 0, result.stdout, result.stderr)
        except FileNotFoundError:
            return (False, "", f"Command not found: {cmd[0]}")

    def check_os_version(self) -> Dict[str, Any]:
        """Validate OS is Debian 13"""
        check: Dict[str, Any] = {
            "name": "Operating System",
            "category": "system",
            "status": "unknown",  # Tri-state: pass/fail/error
            "message": "",
            "details": {},
        }

        try:
            with open("/etc/os-release", "r", encoding="utf-8") as f:
                # Parse OS info...

            if "Debian" in os_info.get("NAME", ""):
                check["status"] = "pass"
            else:
                check["status"] = "fail"

        except Exception as e:
            check["status"] = "error"
            check["message"] = f"Failed to check OS: {str(e)}"

        self.results.append(check)
        return check
```

**Use This Pattern When**:

- Creating validation utilities
- Building health check systems
- Implementing structured output formats
- Wrapping system commands in Python

---

### 9. **lib/utils/credential-gen.py** - Secure Random Generation

**Why Exemplary**:

- Uses `secrets` module (not `random`) for cryptographic security
- Simple, focused utility with one clear purpose
- Proper shebang and imports
- Appropriate for password generation

**Key Patterns Demonstrated**:

```python
#!/usr/bin/env python3
import secrets

# CORRECT: Use secrets module for passwords
password = secrets.token_urlsafe(32)

# WRONG (never do this):
# import random
# password = ''.join(random.choices(string.ascii_letters, k=32))
```

**Use This Pattern When**:

- Generating passwords or tokens
- Creating cryptographic random values
- Building security-sensitive utilities

---

## Testing Exemplars

### 10. **tests/integration/test_idempotency.bats** - Integration Testing

**Why Exemplary**:

- Clear test documentation (user story, requirements, strategy)
- Test-specific environment setup
- Temporary directory usage (no system pollution)
- Proper setup/teardown with cleanup
- Helper functions for reusability
- LOG_FILE set BEFORE sourcing (avoids readonly conflicts)
- Suppression of readonly variable errors in tests

**Key Patterns Demonstrated**:

```bash
#!/usr/bin/env bats
# Integration tests for idempotency
#
# Tests User Story 4: Rapid Environment Replication
# Requirements: SC-008 (idempotent re-run ≤5 minutes)

setup() {
  export PROJECT_ROOT="${BATS_TEST_DIRNAME}/../.."
  export LIB_DIR="${PROJECT_ROOT}/lib"

  # Test-specific directories (use /tmp)
  export TEST_CHECKPOINT_DIR="/tmp/vps-test-$$-checkpoints"
  export TEST_LOG_DIR="/tmp/vps-test-$$-logs"

  # Set LOG_FILE BEFORE sourcing logger.sh (it uses readonly)
  export LOG_FILE="${TEST_LOG_DIR}/test.log"

  # Create test directories
  mkdir -p "${TEST_CHECKPOINT_DIR}" "${TEST_LOG_DIR}"

  # Source core libraries (suppress errors for readonly vars)
  source "${LIB_DIR}/core/logger.sh" 2>/dev/null || true
  source "${LIB_DIR}/core/checkpoint.sh"

  # Initialize systems
  checkpoint_init 2>/dev/null || true
}

teardown() {
  rm -rf "${TEST_CHECKPOINT_DIR}"
  rm -rf "${TEST_LOG_DIR}"
}

# Helper functions
capture_state() {
  echo "Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$1"
  ls -la "${CHECKPOINT_DIR}" >> "$1"
}

simulate_phase() {
  local phase="$1"

  if checkpoint_exists "${phase}"; then
    log_info "Phase ${phase} skipped (checkpoint exists)"
    return 0
  fi

  # Do work...
  checkpoint_create "${phase}"
}

@test "description of test" {
  # Test implementation...
  [[ condition ]]
}
```

**Use This Pattern When**:

- Writing integration tests
- Testing modules with state
- Creating helper functions for tests
- Setting up isolated test environments

---

### 11. **tests/unit/test_logger.bats** - Unit Testing

**Why Exemplary**:

- Fast, isolated unit tests
- Tests single module functionality
- Uses test helper for consistency
- Proper assertions
- Tests both success and failure cases
- Environment variable override for testing

**Key Patterns Demonstrated**:

```bash
#!/usr/bin/env bats
# Unit tests for logger.sh

load '../test_helper.bash'

setup() {
  # Create temporary directory for test logs
  export TEST_DIR="${BATS_TEST_TMPDIR}/logger_test_$$"
  mkdir -p "$TEST_DIR"

  export LOG_DIR="${TEST_DIR}/logs"
  export LOG_FILE="${LOG_DIR}/test.log"
  export LOG_LEVEL="DEBUG"
  export ENABLE_COLORS="false"

  source "${PROJECT_ROOT}/lib/core/logger.sh" 2>/dev/null || true
}

teardown() {
  rm -rf "$TEST_DIR"
}

@test "logger_init creates log directory and files" {
  logger_init "$LOG_DIR"

  [[ -d "$LOG_DIR" ]]
  [[ -f "$LOG_FILE" ]]
}

@test "logger_init fails with invalid directory" {
  LOG_DIR="/root/forbidden"
  run logger_init "$LOG_DIR"

  assert_failure
}

@test "_get_log_level_value returns correct numeric levels" {
  result=$(_get_log_level_value "DEBUG")
  [[ "$result" -eq 0 ]]
}

@test "log_debug writes to file with DEBUG level" {
  logger_init "$LOG_DIR"
  log_debug "Debug message test"

  grep -q "Debug message test" "$LOG_FILE"
}

@test "log_debug is suppressed when LOG_LEVEL is INFO" {
  logger_init "$LOG_DIR"
  LOG_LEVEL="INFO"

  log_debug "Should not appear"

  ! grep -q "Should not appear" "$LOG_FILE"
}
```

**Use This Pattern When**:

- Writing unit tests for modules
- Testing individual functions
- Creating fast, isolated tests
- Testing both positive and negative cases

---

## Architecture Patterns

### Cross-Cutting Patterns

#### Module Loading Pattern

**Pattern**: Guard against double-sourcing with readonly variables

```bash
# At the top of EVERY module
if [[ -n "${_MODULE_NAME_LOADED:-}" ]]; then
  return 0
fi
readonly _MODULE_NAME_LOADED=1
```

**Why**: Prevents double-sourcing which breaks readonly variables and creates state corruption.

---

#### Transaction Recording Pattern

**Pattern**: Record every state change with rollback command

```bash
# After any state change
apt-get install -y nginx
transaction_log "Installed nginx" "apt-get remove -y nginx"

# For file changes
cp "$FILE" "${FILE}.bak"
transaction_log "Modified $FILE" "cp ${FILE}.bak $FILE"
```

**Why**: Enables automated rollback on failure, ensuring clean state recovery.

---

#### Checkpoint Pattern

**Pattern**: Check before work, checkpoint after success

```bash
# At start of phase
if checkpoint_exists "phase-name"; then
  log_info "Phase already completed"
  return 0
fi

# Do work...

# Only checkpoint after verification
if ! command -v installed_binary &>/dev/null; then
  log_error "Installation failed"
  return 1
fi

checkpoint_create "phase-name"
```

**Why**: Enables safe re-runs and resume after failures. Only checkpoint after validation.

---

#### Retry Pattern

**Pattern**: Retry with exponential backoff for network operations

```bash
local max_retries=3
local retry_delay=2

for attempt in $(seq 1 ${max_retries}); do
  if command_that_might_fail; then
    return 0
  fi

  if [[ ${attempt} -lt ${max_retries} ]]; then
    log_warning "Retry ${attempt}/${max_retries}..."
    sleep $((retry_delay * attempt))  # Exponential backoff
  fi
done

log_error "Failed after ${max_retries} attempts"
return 1
```

**Why**: Handles transient network failures gracefully without user intervention.

---

#### Heredoc Configuration Pattern

**Pattern**: Generate configuration files with heredoc

```bash
cat >"${CONFIG_FILE}" <<'EOF'
# Configuration file
KEY="value"
SETTING="option"
EOF

transaction_log "create_file" "${CONFIG_FILE}" "rm -f '${CONFIG_FILE}'"
```

**Why**: Clean, readable configuration generation. Single quotes prevent variable expansion in heredoc.

---

### Testing Patterns

#### Test Environment Isolation

**Pattern**: Use /tmp for test data, override system directories

```bash
setup() {
  export TEST_DIR="/tmp/test-$$-${RANDOM}"
  export LOG_FILE="${TEST_DIR}/test.log"  # Set BEFORE sourcing

  mkdir -p "$TEST_DIR"
  source "${LIB_DIR}/module.sh" 2>/dev/null || true
}

teardown() {
  rm -rf "$TEST_DIR"
}
```

**Why**: Prevents test pollution of system. Cleanup ensures no test residue.

---

## Consistency Observations

### Naming Conventions

1. **Module Guard Variables**: `_MODULE_NAME_LOADED` (uppercase, underscore-prefixed)
2. **Function Names**: `module_name_action` (lowercase, underscores)
3. **Constants**: `UPPERCASE_WITH_UNDERSCORES`
4. **Local Variables**: `lowercase_with_underscores`
5. **Private Functions**: `_function_name` (underscore-prefixed)

### Documentation Standards

1. **File Headers**: Purpose, usage, dependencies
2. **Function Comments**: Args, returns, side effects
3. **Inline Comments**: Why, not what
4. **UX References**: Comment with UX requirement ID (e.g., `# UX-020: Consistent colors`)

### Error Handling

1. **Always validate inputs**: Check for empty/missing parameters
2. **Return explicit status**: `return 0` for success, `return 1` for failure
3. **Log errors**: Use `log_error` before returning failure
4. **Transaction logging**: Record state changes for rollback

### Code Structure

1. **Module order**: Shebang → set options → guard → sourcing → constants → functions
2. **Function order**: Public API first, helpers after
3. **Separation**: One logical concern per function (≤50 lines)

---

## Anti-Patterns to Avoid

### ❌ Don't: Checkpoint Before Validation

```bash
# WRONG
apt-get install -y vscode
checkpoint_create "ide-vscode"  # Created even if broken
```

**✅ Do: Validate Then Checkpoint**

```bash
# RIGHT
apt-get install -y vscode
if ! command -v code &>/dev/null; then
  log_error "VSCode installation failed"
  return 1
fi
checkpoint_create "ide-vscode"  # Only after verification
```

---

### ❌ Don't: Forget Transaction Logging

```bash
# WRONG - No rollback possible
apt-get install -y nginx
```

**✅ Do: Always Record State Changes**

```bash
# RIGHT
apt-get install -y nginx
transaction_log "Installed nginx" "apt-get remove -y nginx"
```

---

### ❌ Don't: Use random Module for Passwords

```bash
# WRONG - NOT cryptographically secure
import random
password = ''.join(random.choices(string.ascii_letters, k=32))
```

**✅ Do: Use secrets Module**

```bash
# RIGHT
import secrets
password = secrets.token_urlsafe(32)
```

---

### ❌ Don't: Silent Error Swallowing

```bash
# WRONG
wget "$URL" | gunzip | tar xf -  # Errors hidden in pipe
```

**✅ Do: Check Each Step**

```bash
# RIGHT
if ! wget "$URL" -O file.tar.gz; then
  log_error "Download failed"
  return 1
fi
if ! tar xzf file.tar.gz; then
  log_error "Extraction failed"
  return 1
fi
```

---

### ❌ Don't: Race Conditions in Service Starts

```bash
# WRONG - Service may not be ready
systemctl start xrdp
ss -tlnp | grep -q ":3389"  # Immediate check fails
```

**✅ Do: Poll Until Ready**

```bash
# RIGHT
systemctl start xrdp
for i in {1..30}; do
  if ss -tlnp | grep -q ":3389"; then
    log_info "RDP server ready"
    break
  fi
  sleep 1
done
```

---

## Recommendations

### For New Developers

1. **Start with system-prep.sh**: Best example showing all patterns
2. **Read lib/core modules**: Foundation for everything else
3. **Run tests**: `make test-unit` to understand expected behavior
4. **Follow the patterns**: Don't invent new approaches unless necessary
5. **Document thoroughly**: Include why, not just what

### For Maintaining Quality

1. **Add tests**: All new modules need integration tests
2. **Validate before checkpointing**: Never checkpoint unverified state
3. **Record transactions**: All state changes need rollback commands
4. **Use helper functions**: Extract repeated patterns
5. **Document decisions**: Use inline comments for non-obvious choices

### For Adding Features

1. **Check exemplars first**: Find similar patterns before implementing
2. **Follow module structure**: Guards, sourcing, constants, functions
3. **Integrate logging**: Use appropriate log levels
4. **Add checkpoints**: Enable idempotency from day one
5. **Test thoroughly**: Unit + integration tests required

---

## Conclusion

This codebase demonstrates high-quality shell scripting with Python utilities. The exemplars shown here represent our standards for:

- **Modularity**: Clear separation with reusable libraries
- **Idempotency**: Checkpoint-based resumable operations
- **Recoverability**: Transaction-based rollback system
- **Testability**: Comprehensive unit and integration tests
- **Maintainability**: Consistent patterns and documentation
- **User Experience**: Progress tracking, error messages, accessibility

When implementing new features, refer to these exemplars to maintain consistency and quality. The patterns shown here have been battle-tested across the entire provisioning system and should be followed for all new development.

**Remember**: The best code is consistent code. Follow these patterns, and our codebase will remain maintainable and reliable.
