---
trigger: always_on
---

# Tech Stack Exemplars & Best Practices

## Overview
These rules are derived from `docs/Code_Exemplars_Blueprint.md` and define the required coding standards for the VPS Provisioning Tool. You must follow these patterns when writing or modifying code.

---

## Shell Scripting (Bash)

### 1. Module Structure
**Rule**: Every library module MUST prevent double-sourcing using the guard pattern.
```bash
if [[ -n "${\_MODULE_NAME_LOADED:-}" ]]; then
  return 0
fi
readonly _MODULE_NAME_LOADED=1
```

### 2. Idempotency & Checkpoints
**Rule**: Use the checkpoint system for all long-running or state-changing phases.
**Rule**: NEVER create a checkpoint before validating success.
```bash
# CORRECT PATTERN
do_work
if validate_work; then
  checkpoint_create "phase-name"
else
  return 1
fi
```

### 3. Transaction Logging (Rollback)
**Rule**: All state changes (files, packages) MUST be recorded in the transaction log with a rollback command.
```bash
transaction_log "action description" "rollback command"
```

### 4. Logging
**Rule**: Use the structured logging library (`lib/core/logger.sh`) instead of `echo`.
- `log_info`: Normal progress
- `log_warning`: Non-fatal issues
- `log_error`: Fatal errors (before return 1)
- `log_debug`: verbose details

### 5. Error Handling
**Rule**: Retry network operations with exponential backoff.
**Rule**: Validate all inputs at function start.

---

## Python Utilities

### 1. Security
**Rule**: NEVER use `random` for generating secrets/passwords. MUST use `secrets` module.
```python
import secrets
token = secrets.token_urlsafe(32)
```

### 2. Validation
**Rule**: Return structured data (dicts/classes) rather than simple booleans for health checks.
**Rule**: Use tri-state status: `pass`, `fail`, `error` (for execution failures).

---

## Testing Standards

### 1. Environment Isolation
**Rule**: Tests MUST NOT modify system files. Use `BATS_TEST_TMPDIR` or `/tmp` for all file operations.
**Rule**: Mock external commands that change system state.

### 2. Readonly Variables
**Rule**: In test `setup()`, handle readonly variables from core modules gracefully (e.g., typically by creating a fresh process or suppressing errors if sourcing again).

---

## Anti-Patterns (FORBIDDEN)

1.  **Silent Pipe Errors**: `cmd1 | cmd2` is forbidden without `set -o pipefail`. better to check each step:
    ```bash
    # BAD
    wget url | tar xz

    # GOOD
    wget url -O file
    tar xz file
    ```

2.  **Race Conditions**: Do not assume a service is up immediately after start. Poll for the port or socket.
    ```bash
    systemctl start service
    # Loop and check port/socket...
    ```

3.  **Hardcoded Paths**: Use configuration variables (e.g., `${LIB_DIR}`) instead of literal paths like `/usr/local/lib`.
