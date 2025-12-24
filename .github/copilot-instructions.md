# Copilot Instructions: VPS Provisioning System

## PROTOCOL 0: FRIDAY Persona (MANDATORY)

**All AI agents MUST follow the FRIDAY persona instructions as the foundational protocol.**

See: `.github/instructions/friday-persona.instructions.md`

**Core Requirements:**

- **Communication**: English only, action-first, minimal explanations
- **Code Quality**: SOLID principles, DRY, clean architecture (non-negotiable)
- **Testing**: TDD approach, ≥80% coverage for critical paths (required before completion)
- **UX Consistency**: WCAG 2.2 AA accessibility, consistent patterns (validate before deploy)
- **Performance**: Meet budgets (≤3s load, ≤200ms API, ≤5s TTI)
- **Execution Style**: "Talk less, do more" - lead with tool calls, brief summaries only

**Quality Gates (No task complete without):**

- [ ] Code meets SOLID + DRY standards
- [ ] Tests written and passing (≥80% critical path coverage)
- [ ] UX accessible and consistent
- [ ] Performance requirements met
- [ ] Security validated (no vulnerabilities)

**Response Pattern**: `[Execute tools] → Brief result summary`

---

## Project Overview

**Purpose**: Automated provisioning tool that transforms fresh Digital Ocean Debian 13 VPS into fully-functional developer workstation with RDP access, 3 IDEs (VSCode, Cursor, Antigravity), and developer tools—all via single command in ≤15 minutes.

**Language**: Bash 5.1+ (orchestration), Python 3.11+ (utilities)  
**Target**: Debian 13 (Bookworm) VPS, minimum 2GB RAM/1vCPU/25GB disk

## Architecture: Modular Shell System

### Core Design Principles

- **Idempotency**: All modules use checkpoint system—safe to re-run
- **Transactionality**: All actions logged with rollback commands in LIFO order
- **Phased Execution**: 10 distinct phases, each independently testable
- **State Persistence**: Session state stored in `/var/vps-provision/sessions/` as JSON

### Directory Structure

```
bin/vps-provision          # Main CLI entry point
lib/
  core/                    # Framework (logger, checkpoint, transaction, rollback)
  modules/                 # Phase implementations (system-prep, desktop-env, rdp-server, etc.)
  utils/                   # Python utilities (credential-gen, health-check, package-manager)
  models/                  # JSON schemas for state validation
```

### Data Flow: Session → Phases → Actions → Checkpoints

1. CLI initializes `ProvisioningSession` with unique ID
2. Each phase checks for existing checkpoint before executing
3. Actions logged to transaction log with rollback commands
4. On success: checkpoint created; on failure: automatic rollback via LIFO

## Critical Conventions

### Module Pattern (ALL modules MUST follow)

```bash
#!/bin/bash
set -euo pipefail

# Prevent multiple sourcing
if [[ -n "${_MODULE_NAME_SH_LOADED:-}" ]]; then
  return 0
fi
readonly _MODULE_NAME_SH_LOADED=1

# Source dependencies explicitly
source "${LIB_DIR}/core/logger.sh"
source "${LIB_DIR}/core/checkpoint.sh"

# Constants (readonly, ALL CAPS)
readonly MODULE_PHASE="phase-name"
readonly -a REQUIRED_PACKAGES=("pkg1" "pkg2")

# Main execution function: module_name_execute
module_name_execute() {
  checkpoint_exists "$MODULE_PHASE" && {
    log_info "Phase already completed, skipping"
    return 0
  }

  # Implementation
  checkpoint_create "$MODULE_PHASE"
}
```

### Logging Standards

- **Use structured logging**: `log_info "Message" "key1=value1" "key2=value2"`
- **Redact secrets**: Use `[REDACTED]` for passwords/tokens in logs
- **Progress tracking**: Update `progress_set_current` and `progress_update_percentage` in long operations
- Example: `log_info "Installing package" "name=${pkg}" "version=${ver}"`

### Testing Strategy (TDD Required)

- **Unit tests** (`tests/unit/`): Core library functions, mocked system calls
- **Integration tests** (`tests/integration/`): Module execution on real system with mocked external dependencies
- **Contract tests** (`tests/contract/`): CLI interface validation against JSON schemas
- **E2E tests** (`tests/e2e/`): Full provisioning on fresh Debian 13 VPS

**Test framework**: bats-core 1.10.0  
**Test structure**: Each test file has `setup()` to create temp directories and mock functions

Example mock pattern in integration tests:

```bash
setup() {
  export LOG_FILE="${BATS_TEST_TMPDIR}/test.log"
  export CHECKPOINT_DIR="${BATS_TEST_TMPDIR}/checkpoints"

  # Override functions to avoid root requirement
  apt-get() { echo "apt-get $*" >> "${LOG_FILE}"; return 0; }
  export -f apt-get
}
```

## Spec-Driven Workflow (MANDATORY)

Project follows **Specification-Driven Workflow v1** (`.github/instructions/spec-driven-workflow-v1.instructions.md`).

### Critical Artifacts (Keep Updated)

- `specs/001-vps-dev-provision/spec.md`: User stories with acceptance criteria in EARS notation
- `specs/001-vps-dev-provision/plan.md`: Technical approach and architecture decisions
- `specs/001-vps-dev-provision/tasks.md`: Implementation plan with task IDs, priorities, dependencies
- `specs/001-vps-dev-provision/data-model.md`: JSON schemas for all state objects

### EARS Notation for Requirements

All requirements follow Easy Approach to Requirements Syntax:

- **Event-driven**: `WHEN [trigger] THE SYSTEM SHALL [behavior]`
- **State-driven**: `WHILE [state] THE SYSTEM SHALL [behavior]`
- Example: "WHEN provisioning fails, THE SYSTEM SHALL execute rollback in reverse order"

### Task Format in tasks.md

```markdown
- [ ] T042 [P] [US1] Description with file path
  # [P] = Parallelizable
  # [US1] = User Story 1
  # File path = lib/modules/ide-vscode.sh
```

## Build & Development Commands

### Essential Makefile Targets

```bash
make install        # Install bats-core and Python dependencies
make test           # Run all test suites
make test-unit      # Unit tests only
make test-integration  # Integration tests (requires sudo)
make test-e2e       # Full provisioning on test VPS
make lint           # shellcheck + pylint
make clean          # Remove logs, temp files
```

### Running Provisioning

```bash
./bin/vps-provision               # Normal execution
./bin/vps-provision --dry-run     # Show planned actions without execution
./bin/vps-provision --resume      # Continue from last checkpoint after failure
./bin/vps-provision --force       # Clear checkpoints and re-provision
./bin/vps-provision --help        # Full CLI documentation
```

## Key Integration Points

### Checkpoint System (`lib/core/checkpoint.sh`)

- **Purpose**: Enables idempotency—track completed phases to avoid re-execution
- **Location**: `/var/vps-provision/checkpoints/<phase>.checkpoint`
- **Usage**: `checkpoint_exists "phase-name"` returns 0 if exists, 1 otherwise

### Transaction Log (`lib/core/transaction.sh`)

- **Purpose**: Record all actions with rollback commands for automatic recovery
- **Format**: Each line is `ACTION|TIMESTAMP|ROLLBACK_COMMAND`
- **Example**: `PACKAGE_INSTALL|2025-12-24T10:30:00Z|apt-get remove -y xrdp`

### Rollback Engine (`lib/core/rollback.sh`)

- **Trigger**: Automatic on any error (exit code ≠ 0)
- **Process**: Parse transaction log in LIFO order, execute rollback commands
- **Verification**: Check system state after rollback to ensure clean state

### Python Utilities Integration

Python utilities in `lib/utils/` provide specialized operations called from Bash modules:

#### credential-gen.py

- **Purpose**: Secure password generation using CSPRNG (Cryptographically Secure Pseudo-Random Number Generator)
- **Requirements**: Minimum 16 characters, mixed case, numbers, symbols
- **Usage from Bash**: `python3 "${LIB_DIR}/utils/credential-gen.py" --length 20`
- **Security**: Passwords NEVER written to logs—always use `[REDACTED]` placeholder
- **Output**: Prints password to stdout for capture in Bash variable

#### package-manager.py

- **Purpose**: Advanced APT operations beyond basic apt-get capabilities
- **Features**:
  - Dependency resolution with conflict detection
  - Package verification (checksums, signatures)
  - Retry logic for transient failures
  - Lock file management (handles stale `/var/lib/dpkg/lock`)
- **Usage**: `python3 "${LIB_DIR}/utils/package-manager.py" install package1 package2`
- **Returns**: Exit code 0 on success, non-zero with error details on stderr

#### health-check.py

- **Purpose**: Post-installation validation of all provisioned components
- **Checks**:
  - Service status (xrdp, lightdm active)
  - Port accessibility (22, 3389 listening)
  - IDE executables (VSCode, Cursor, Antigravity launch test)
  - Configuration correctness (xrdp.ini, sesman.ini parsed)
  - Resource availability (disk, memory thresholds)
- **Usage**: `python3 "${LIB_DIR}/utils/health-check.py" --json > health-report.json`
- **Output**: JSON report with pass/fail status per component

## JSON Schema Validation

State validation uses JSON schemas in `lib/models/` to ensure data integrity:

### Schema Files & Purpose

- **provisioning-session.schema.json**: Root session object with phases array
- **checkpoint.schema.json**: Individual checkpoint metadata structure
- **transaction-log.schema.json**: Transaction log entry format for rollback

### How Validation Works

1. Bash writes session state as JSON to `/var/vps-provision/sessions/`
2. Python utilities validate against schemas before processing
3. Invalid state triggers ERROR log and prevents operation
4. Schema enforces required fields, types, enums, patterns

### Example: Session State Structure

```json
{
  "session_id": "20251224-103000",
  "status": "IN_PROGRESS",
  "phases": [
    {
      "phase_name": "system-prep",
      "status": "COMPLETED",
      "checkpoint_exists": true
    }
  ]
}
```

### Adding New State Fields

1. Update schema in `lib/models/*.schema.json`
2. Increment schema version
3. Add migration logic in `lib/core/state.sh` for backward compatibility
4. Document in `specs/001-vps-dev-provision/data-model.md`

## IDE Installation Strategy

Each IDE module follows a fallback installation strategy for resilience:

### VSCode (lib/modules/ide-vscode.sh)

1. **Primary**: Official Microsoft APT repository
   - Add GPG key from `packages.microsoft.com`
   - Add repository to `/etc/apt/sources.list.d/vscode.list`
   - Install via `apt-get install code`
2. **Fallback**: Direct .deb download if repository fails
3. **Verification**: Check `/usr/bin/code` exists, test launch with `--version`
4. **Desktop Integration**: Verify launcher at `/usr/share/applications/code.desktop`

### Cursor (lib/modules/ide-cursor.sh)

1. **Primary**: Download .deb from official Cursor website
2. **Fallback**: AppImage if .deb installation fails
   - Install to `/opt/cursor/`
   - Create symlink in `/usr/local/bin/cursor`
3. **Verification**: Test launch with timeout (10s max)
4. **Desktop Integration**: Create custom `.desktop` file if AppImage used

### Antigravity (lib/modules/ide-antigravity.sh)

1. **Primary**: Fetch latest AppImage from GitHub releases API
2. **Installation**: Install to `/opt/antigravity/`, make executable
3. **CLI Alias**: Add to `/etc/bash.bashrc` for all users
4. **Verification**: Execute with `--version` flag

### Common IDE Patterns

- **Prerequisites Check**: Desktop environment must be installed first
- **Transaction Logging**: Log installation with rollback command (uninstall/remove)
- **Launch Testing**: Run IDE in headless mode to verify no missing dependencies
- **Memory Limits**: Monitor memory during installation to prevent OOM

## Multi-Session RDP Configuration

Multi-session support configured in `lib/modules/rdp-server.sh`:

### xrdp.ini Configuration

```ini
max_bpp=32                    # Color depth
xserverbpp=24
port=3389                     # Standard RDP port
security_layer=tls            # Force TLS encryption
crypt_level=high              # High encryption level
```

### sesman.ini Configuration (Critical for Multi-Session)

```ini
[Sessions]
MaxSessions=50                # Allow up to 50 concurrent sessions
KillDisconnected=0            # Preserve disconnected sessions
DisconnectedTimeLimit=0       # No timeout for disconnected sessions
IdleTimeLimit=0               # No timeout for idle sessions

[Xorg]
param=-novtswitch             # Don't switch virtual terminals
param=-nolisten tcp           # Security: no TCP connections to X
```

### Session Isolation Mechanism

- Each RDP connection gets unique X display (`:10`, `:11`, `:12`, etc.)
- Separate user processes in isolated namespaces
- File permissions prevent cross-session access
- Resource limits per session (memory, CPU) to prevent monopolization

### Performance Monitoring

- Track memory usage: target ≤1.3GB per active session
- 3 concurrent sessions target: ~3GB used, 1GB buffer for system
- Monitor with: `xrdp-sesadmin -l` (list active sessions)

### Troubleshooting Multi-Session Issues

- **"Connection refused"**: Check `systemctl status xrdp` and port 3389 open
- **Session hangs**: Check disk space (`df -h`), memory (`free -h`)
- **Can't reconnect**: Verify `KillDisconnected=0` in sesman.ini
- **Slow performance**: Check CPU load (`top`), consider reducing concurrent sessions

## Common Patterns & Gotchas

### 1. Always Check Checkpoint Before Work

```bash
# CORRECT
module_execute() {
  checkpoint_exists "$PHASE" && return 0
  # ... do work ...
  checkpoint_create "$PHASE"
}

# WRONG - will re-execute on every run
module_execute() {
  # ... do work ...
  checkpoint_create "$PHASE"
}
```

### 2. Log All Actions to Transaction Log

```bash
# Before modifying system
transaction_log "FILE_BACKUP" "/etc/xrdp/xrdp.ini.bak" "restore /etc/xrdp/xrdp.ini"
cp /etc/xrdp/xrdp.ini /etc/xrdp/xrdp.ini.bak
# Modify file
transaction_log "FILE_MODIFY" "/etc/xrdp/xrdp.ini" "restore from backup"
```

### 3. Package Installation with Validation

```bash
# Use module pattern
for pkg in "${REQUIRED_PACKAGES[@]}"; do
  if ! dpkg -s "$pkg" &>/dev/null; then
    transaction_log "PACKAGE_INSTALL" "$pkg" "apt-get remove -y $pkg"
    apt-get install -y "$pkg" || {
      log_error "Failed to install $pkg"
      return 1
    }
  fi
done
```

### 4. Progress Tracking in Loops

```bash
local total=${#PACKAGES[@]}
local current=0
for pkg in "${PACKAGES[@]}"; do
  ((current++))
  progress_update_percentage "$((current * 100 / total))"
  # ... install pkg ...
done
```

## Performance Targets (Enforce in Code)

- Total provisioning: ≤ 15 minutes (4GB RAM, 2 vCPU)
- RDP session initialization: ≤ 10 seconds
- IDE launch time: ≤ 10 seconds
- Idempotent re-run: ≤ 5 minutes (checkpoint validation only)
- Multi-session support: 3 concurrent RDP users within 4GB RAM

## Security Requirements (OWASP Aligned)

- No hardcoded secrets—use env vars or secure generation
- Redact `[REDACTED]` in all logs for passwords/tokens
- SSH hardening: disable root login, password auth
- Firewall: default deny, explicit allow ports 22, 3389
- TLS for RDP: 4096-bit RSA self-signed certificates
- Sudo configuration: passwordless for devuser with audit logging

## When Adding New Features

1. **Update spec.md**: Add user story with acceptance scenarios (EARS notation)
2. **Update tasks.md**: Break down into tasks with IDs, priorities, file paths
3. **Write tests first**: Integration test → implement module → verify
4. **Update data-model.md**: If adding new state/configuration
5. **Document in plan.md**: Architecture decisions and trade-offs

## Quick Reference: File Locations

- Session state: `/var/vps-provision/sessions/session-<id>.json`
- Logs: `/var/log/vps-provision/provision.log`
- Checkpoints: `/var/vps-provision/checkpoints/<phase>.checkpoint`
- Transactions: `/var/log/vps-provision/transactions.log`
- Config: `config/default.conf` (default values), custom via `--config`

## Example: Adding New Module

```bash
# 1. Create module file
lib/modules/new-feature.sh

# 2. Implement with pattern
#!/bin/bash
set -euo pipefail
if [[ -n "${_NEW_FEATURE_SH_LOADED:-}" ]]; then return 0; fi
readonly _NEW_FEATURE_SH_LOADED=1

source "${LIB_DIR}/core/logger.sh"
source "${LIB_DIR}/core/checkpoint.sh"
readonly NEW_FEATURE_PHASE="new-feature"

new_feature_execute() {
  checkpoint_exists "$NEW_FEATURE_PHASE" && return 0
  log_info "Starting new feature"
  # Implementation
  checkpoint_create "$NEW_FEATURE_PHASE"
}

# 3. Add integration test
tests/integration/test_new_feature.bats

# 4. Update tasks.md with task IDs
# 5. Source in bin/vps-provision
# 6. Add to phase execution sequence
```
