# VPS Provisioning Tool - AI Agent Instructions

> **⚡ PRIMARY PROTOCOL: FRIDAY PERSONA**
>
> You MUST operate under the **FRIDAY Persona** protocol defined in `.github/instructions/friday-persona.instructions.md`.
>
> **Core Directive**: **Talk less, do more**
>
> - Execute tool calls IMMEDIATELY without explanation
> - Provide brief summaries AFTER execution (1-2 sentences)
> - Never announce what you're about to do
> - Focus on results, not process
>
> **Four Pillars (Non-Negotiable)**:
>
> 1. **Code Quality**: SOLID, DRY, Clean Architecture
> 2. **Testing**: ≥80% critical path coverage before completion
> 3. **UX Consistency**: WCAG 2.2 AA compliance
> 4. **Performance**: Meet budgets (≤15 min full provision, ≤5 min re-run)
>
> **Response Pattern**:
>
> ```
> [Execute tools]
> [More tools as needed]
>
> Result: [Brief summary]
> ```
>
> All instructions below are project-specific implementation details that MUST be followed within the FRIDAY framework.

---

## Project Overview

**VPS Developer Workstation Provisioning Tool** - Automated system that transforms fresh Digital Ocean Debian 13 VPS into fully-configured development workstation in ≤15 minutes. Installs XFCE desktop, RDP server, three IDEs (VSCode, Cursor, Antigravity), and configures developer user with passwordless sudo.

**Core Architecture**: Modular Bash orchestration with Python utilities. Transaction-based rollback system. Checkpoint-driven idempotency. Progressive UI with real-time feedback.

## Critical Architecture Patterns

### 1. Three-Layer Library System

```
lib/
├── core/         # Foundation: logging, transactions, checkpoints, error handling
├── modules/      # Business logic: system-prep, desktop-env, ide-*, rdp-server
└── utils/        # Python utilities: credential-gen, health-check, session-monitor
```

**Module Loading Pattern**: Every module starts with:

```bash
set -euo pipefail
if [[ -n "${_MODULE_NAME_LOADED:-}" ]]; then return 0; fi
readonly _MODULE_NAME_LOADED=1
source "${LIB_DIR}/core/logger.sh"
# Additional dependencies...
```

**Why**: Prevents double-sourcing which breaks readonly variables and creates state corruption.

### 2. Transaction & Rollback System

Every state-changing action MUST be recorded in `lib/core/transaction.sh`:

```bash
# Record action with rollback command
transaction_record "Installed package nginx" "apt-get remove -y nginx"
transaction_record "Modified /etc/ssh/sshd_config" "cp /etc/ssh/sshd_config.bak /etc/ssh/sshd_config"
```

**Rollback executes in LIFO order** (reverse chronological). See `lib/core/rollback.sh` for implementation.

**Critical**: If you add ANY system modification, record its rollback command immediately after.

### 3. Checkpoint-Based Idempotency

Each module phase uses checkpoints to enable safe re-runs:

```bash
# Check if already completed
if checkpoint_exists "system-prep"; then
  log_info "System prep already completed (checkpoint found)"
  return 0
fi

# Do work...

# Mark complete
checkpoint_create "system-prep"
```

**Why**: Allows provisioning to resume after network failures, reboots, or interruptions. Re-running is safe and fast (≤5 min).

### 4. Progressive UX with Phase Weights

UI in `lib/core/progress.sh` uses weighted phases:

```bash
progress_register_phase "system-prep" 15      # 15% of total time
progress_register_phase "desktop-env" 25      # 25% of total time
progress_register_phase "ide-vscode" 20       # etc...
```

**Display Format**: `[Phase 2/10] Desktop Installation ████████████████ 65% (3m 42s remaining)`

When adding new phases, update weights in `bin/vps-provision` main function.

## Development Workflows

### Running Tests

```bash
make test              # All tests (unit + integration + contract)
make test-unit         # Core library tests (fast, no VPS needed)
make test-integration  # Integration tests (require VPS simulation)
make test-contract     # CLI interface contract tests
make test-e2e          # Full provisioning test (fresh VPS required)
```

**Test Structure**: BATS for shell tests, pytest for Python. All tests use temporary directories under `/tmp/vps-test-$$-*` to avoid polluting system.

### Debugging

Enable debug logging:

```bash
LOG_LEVEL=DEBUG ./bin/vps-provision
```

View transaction log for rollback debugging:

```bash
cat /var/log/vps-provision/transactions.log
```

Check checkpoint status:

```bash
ls -la /var/vps-provision/checkpoints/
```

### Adding New Modules

1. Create in `lib/modules/your-module.sh`
2. Follow module loading pattern (see Architecture #1)
3. Register phase in `bin/vps-provision` main function
4. Add checkpoint at start/end of execute function
5. Record ALL state changes with `transaction_record`
6. Update phase weights for progress display
7. Add integration test in `tests/integration/test_your_module.bats`

## Project-Specific Conventions

### Logging Standards

```bash
log_debug "Internal state: $variable_name"        # Development only
log_info "Installing package: nginx"               # User-visible progress
log_warning "Retrying failed download (attempt 2)" # Recoverable issues
log_error "Failed to install critical package"     # Fatal errors
```

**Output goes to both console (colored) and `/var/log/vps-provision/provision.log` (plain text).**

### Error Handling

Use error handler from `lib/core/error-handler.sh`:

```bash
# Automatic rollback on any error
trap 'error_handler $? "$BASH_COMMAND" "${BASH_SOURCE[0]}" "${LINENO}"' ERR

# Manual error reporting
if ! some_critical_operation; then
  error_report "Critical operation failed" "CRITICAL_OPERATION_FAILURE"
  return 1
fi
```

**Why**: All errors trigger automatic transaction rollback unless explicitly handled.

### Sanitization

User inputs MUST be sanitized using `lib/core/sanitize.sh`:

```bash
username=$(sanitize_username "$raw_username")   # Strips non-alphanumeric
filepath=$(sanitize_filepath "$raw_path")       # Prevents path traversal
```

**Security**: Prevents injection attacks in shell commands and file operations.

### Configuration Management

Default config: `config/default.conf`
Custom config: `--config /path/to/custom.conf`

Config format:

```bash
USERNAME="devuser"
INSTALL_VSCODE="true"
INSTALL_CURSOR="true"
RDP_PORT="3389"
```

Loaded via `lib/core/config.sh`. All values accessible as shell variables after loading.

## Integration Points

### External Dependencies

- **Package Repositories**: apt.debian.org, code.visualstudio.com, cursor.sh
- **IDE Installers**: VSCode (.deb), Cursor (AppImage), Antigravity (tar.gz)
- **RDP Protocol**: xrdp server on port 3389
- **SSH Access**: Hardened config in `/etc/ssh/sshd_config`

**Network Failure Handling**: All downloads retry 3x with exponential backoff. See `lib/core/file-ops.sh::download_file`.

### Service Management

Services controlled via `lib/core/services.sh`:

```bash
service_enable "xrdp"           # Enable and start
service_status "xrdp"           # Check if running
service_restart "ssh"           # Restart service
```

**Why**: Abstracts systemctl/service commands for consistent behavior across Debian versions.

## Key Files Reference

- **`bin/vps-provision`**: Main CLI entry point, phase orchestration
- **`lib/core/logger.sh`**: Structured logging with levels and colors
- **`lib/core/transaction.sh`**: Transaction recording for rollback
- **`lib/core/checkpoint.sh`**: Idempotency via checkpoint files
- **`lib/modules/system-prep.sh`**: Example module showing all patterns
- **`specs/001-vps-dev-provision/spec.md`**: Complete requirements (EARS notation)
- **`tests/integration/test_idempotency.bats`**: Example integration test
- **`Makefile`**: All test and build commands

## When Adding Features

1. **Read spec first**: `specs/001-vps-dev-provision/spec.md` contains all requirements in EARS format
2. **Update plan**: Modify `specs/001-vps-dev-provision/plan.md` with implementation approach
3. **Add module**: Create in `lib/modules/`, follow existing patterns exactly
4. **Add tests**: Integration test in `tests/integration/`, contract test for CLI changes
5. **Update docs**: CLI help in `bin/vps-provision`, user docs in `README.md`

## Performance Targets

- **Full provision**: ≤15 min on 4GB/2vCPU droplet
- **Idempotent re-run**: ≤5 min (checkpoints + validation only)
- **RDP ready**: Immediately after completion
- **IDE launch**: ≤10 sec from desktop click

**Profiling**: Phase timings logged automatically. Check logs for bottlenecks.

## Frequently Modified Modules

### IDE Installation Modules (Most Common Changes)

IDE modules (`lib/modules/ide-*.sh`) follow a strict pattern:

1. **Check prerequisites** before attempting installation
2. **Add GPG keys and repositories** with 3x retry logic
3. **Install package** via apt or manual download
4. **Verify installation** by checking executable and desktop launcher
5. **Create checkpoint** only after successful verification

**Example from `ide-vscode.sh`**:

```bash
ide_vscode_check_prerequisites() {
  if ! checkpoint_exists "desktop-install"; then
    log_error "Desktop environment not installed"
    return 1
  fi
  # Check required commands...
}

ide_vscode_add_gpg_key() {
  local max_retries=3
  while (( retry_count < max_retries )); do
    if wget -qO- "$VSCODE_GPG_URL" | gpg --dearmor > "$VSCODE_GPG_KEY"; then
      transaction_log "gpg_key_add" "rm -f '$VSCODE_GPG_KEY'"
      return 0
    fi
    sleep 2  # Exponential backoff
  done
}
```

**Common Pitfall**: Don't create checkpoint before verification - installations can appear successful but have broken launchers.

### Desktop Environment Module

The `desktop-env.sh` module is the largest dependency - most failures happen here. Key patterns:

- **Massive package installation** requires progress updates every ~5 packages
- **Service conflicts** with existing display managers must be detected early
- **Session configuration** files must be written atomically to prevent corruption
- **X11/Wayland detection** determines configuration paths

## Python Utility Patterns

Python utilities in `lib/utils/` provide structured data validation:

### health-check.py

Post-installation validator returning JSON or text output:

```python
check = {
    "name": "Operating System",
    "category": "system",
    "status": "pass|fail|error",  # Tri-state result
    "message": "Human-readable summary",
    "details": {}  # Structured data for debugging
}
```

**Usage Pattern**:

```bash
# From bash modules
if ! python3 "${LIB_DIR}/utils/health-check.py" --output json > "$RESULT_FILE"; then
  log_error "Health check failed"
  cat "$RESULT_FILE"  # Show detailed results
fi
```

**When to Use**: After any major provisioning phase to validate system state before proceeding.

### credential-gen.py

Generates cryptographically secure random passwords:

```python
# Uses secrets module (not random!)
password = secrets.token_urlsafe(32)
```

**Security Note**: Never use `random` module for passwords - always `secrets`.

## Common Testing Failures & Debugging

### Integration Test Pattern

BATS tests use temporary directories to avoid system pollution:

```bash
setup() {
  export TEST_DIR="${BATS_TEST_TMPDIR}/network_test"
  export LOG_FILE="${TEST_DIR}/test.log"  # MUST set BEFORE sourcing

  source "${LIB_DIR}/core/logger.sh" 2>/dev/null || true  # Suppress readonly errors
}
```

**Why**: Logger uses `readonly` for paths. Setting after sourcing causes test failures.

### Network Failure Simulation

Tests use mock commands with attempt counters:

```bash
mock_cmd() {
  attempt_count=$((attempt_count + 1))
  if [[ $attempt_count -lt 3 ]]; then
    echo "Network error" >&2
    return 100  # E_NETWORK error code
  fi
  echo "Success"
}
```

**Pattern**: Fail N-1 times, succeed on Nth attempt to validate retry logic.

### Test Execution Order

```bash
make test-unit         # Fast (5-10s) - run first
make test-integration  # Medium (1-2m) - requires sudo for some tests
make test-contract     # Fast (10-20s) - CLI validation
make test-e2e          # Slow (15m) - requires fresh VPS
```

**Pro Tip**: Run `make test-unit` constantly during development. Only run e2e before commits.

## Common Pitfalls & Solutions

### 1. Double-Sourcing Readonly Variables

**Problem**: `readonly LOG_FILE` set in logger.sh causes failures when sourced twice.

**Solution**: Guard pattern at top of every module:

```bash
if [[ -n "${_MODULE_NAME_LOADED:-}" ]]; then return 0; fi
readonly _MODULE_NAME_LOADED=1
```

### 2. Missing Rollback Commands

**Problem**: System left in inconsistent state after failure.

**Solution**: Every state change needs rollback:

```bash
apt-get install -y nginx
transaction_record "Installed nginx" "apt-get remove -y nginx"

# For file changes
cp "$FILE" "${FILE}.bak"
transaction_record "Modified $FILE" "cp ${FILE}.bak $FILE"
```

### 3. Checkpoint Created Before Validation

**Problem**: Re-runs skip broken installations.

**Solution**: Always validate THEN checkpoint:

```bash
# Wrong
apt-get install -y vscode
checkpoint_create "ide-vscode"  # Created even if broken

# Right
apt-get install -y vscode
if ! command -v code &>/dev/null; then
  log_error "VSCode installation failed"
  return 1
fi
checkpoint_create "ide-vscode"  # Only after verification
```

### 4. Progress Weights Don't Sum to 100

**Problem**: Progress bar stuck at 95% or jumps erratically.

**Solution**: Audit phase weights in `bin/vps-provision` main function:

```bash
# Weights must sum to 100
progress_register_phase "system-prep" 15    # 15%
progress_register_phase "desktop-env" 30    # +30 = 45%
progress_register_phase "rdp-server" 10     # +10 = 55%
# ... must total 100
```

### 5. Network Timeouts Without Retry

**Problem**: Provisioning fails on first transient network hiccup.

**Solution**: Use `download_file` from `lib/core/file-ops.sh`:

```bash
# Wrong
wget "$URL" -O "$FILE"

# Right
download_file "$URL" "$FILE"  # Built-in 3x retry with exponential backoff
```

### 6. Silent Errors in Pipelines

**Problem**: `set -euo pipefail` doesn't catch all pipe failures.

**Solution**: Check exit status explicitly:

```bash
# Risky
wget "$URL" | gunzip | tar xf -

# Safe
if ! wget "$URL" -O file.tar.gz; then
  log_error "Download failed"
  return 1
fi
if ! tar xzf file.tar.gz; then
  log_error "Extraction failed"
  return 1
fi
```

### 7. Race Conditions in Service Starts

**Problem**: Service marked "started" but not yet ready to accept connections.

**Solution**: Poll until ready:

```bash
systemctl start xrdp
# Don't immediately test connection!

# Wait for readiness
for i in {1..30}; do
  if ss -tlnp | grep -q ":3389"; then
    log_info "RDP server ready"
    break
  fi
  sleep 1
done
```

## Questions or Unclear Areas?

If you encounter patterns not documented here, check:

1. Similar module in `lib/modules/` for examples
2. Test in `tests/integration/` for expected behavior
3. Spec in `specs/001-vps-dev-provision/` for requirements
