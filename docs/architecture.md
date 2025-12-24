# VPS Provision Architecture

## Overview

The VPS Provision tool follows a modular, layered architecture designed for maintainability, testability, and extensibility. This document describes the architectural components and their interactions.

## Architecture Layers

### 1. CLI Layer (`bin/`)

**Purpose**: Command-line interface and user interaction

**Components**:

- `vps-provision`: Main CLI entry point
- `preflight-check`: Pre-flight validation tool
- `session-manager.sh`: Multi-session management utility

**Responsibilities**:

- Parse command-line arguments
- Validate input parameters
- Orchestrate provisioning phases
- Handle error reporting and exit codes
- Manage user interactions (prompts, confirmations)

### 2. Core Library Layer (`lib/core/`)

**Purpose**: Foundational services used across all modules

**Components**:

- **logger.sh**: Structured logging with levels, colors, and redaction
- **progress.sh**: Progress tracking, time estimation, visual indicators
- **checkpoint.sh**: Idempotency via checkpoint files
- **transaction.sh**: Transaction recording for rollback
- **rollback.sh**: LIFO rollback execution on failures
- **config.sh**: Configuration management and validation
- **validator.sh**: System and input validation
- **sanitize.sh**: Input sanitization and security
- **error-handler.sh**: Centralized error handling
- **state.sh**: State persistence and recovery
- **ux.sh**: User experience utilities (prompts, banners)
- **services.sh**: System service management
- **file-ops.sh**: Safe file operations with backup
- **lock.sh**: Process locking and concurrency control

**Key Patterns**:

- Single responsibility: each module does one thing well
- Guard clauses: prevent double-sourcing with readonly checks
- Dependency injection: modules source only required dependencies
- Error propagation: set -euo pipefail for strict error handling

### 3. Module Layer (`lib/modules/`)

**Purpose**: Business logic for specific provisioning tasks

**Components**:

- **system-prep.sh**: OS validation, package updates, base tools
- **desktop-env.sh**: XFCE desktop installation and configuration
- **rdp-server.sh**: xrdp server setup and hardening
- **user-provisioning.sh**: Developer user creation and sudo setup
- **ide-vscode.sh**: Visual Studio Code installation
- **ide-cursor.sh**: Cursor IDE installation
- **ide-antigravity.sh**: Antigravity IDE installation
- **terminal-setup.sh**: Terminal enhancements (oh-my-bash, themes)
- **dev-tools.sh**: Development tools (git, build-essential, etc.)
- **firewall.sh**: UFW firewall configuration
- **fail2ban.sh**: Intrusion prevention setup
- **audit-logging.sh**: System audit log configuration
- **verification.sh**: Post-installation validation
- **summary-report.sh**: Final report generation
- **status-banner.sh**: SSH login banner

**Module Pattern**:

```bash
#!/bin/bash
set -euo pipefail

# Prevent double-sourcing
if [[ -n "${_MODULE_NAME_LOADED:-}" ]]; then
  return 0
fi
readonly _MODULE_NAME_LOADED=1

# Source dependencies
source "${LIB_DIR}/core/logger.sh"
source "${LIB_DIR}/core/checkpoint.sh"

# Public functions
module_execute() {
  # Check prerequisites
  if checkpoint_exists "prerequisite"; then
    log_info "Prerequisites already met"
  fi

  # Do work with checkpoints
  if ! checkpoint_exists "module-phase1"; then
    # Execute phase 1
    checkpoint_create "module-phase1"
  fi

  # Record transactions for rollback
  transaction_record "Action taken" "rollback command"
}
```

### 4. Utility Layer (`lib/utils/`)

**Purpose**: Python utilities for complex validation and reporting

**Components**:

- **credential-gen.py**: Cryptographically secure password generation
- **health-check.py**: Post-installation system health validation
- **session-monitor.py**: RDP session monitoring and reporting
- **package-manager.py**: Advanced package management operations
- **state-compare.sh**: State comparison for validation

**Why Python?**:

- Complex data validation (JSON schemas)
- Structured output formats (JSON, YAML)
- Rich standard library for health checks
- Better error handling for edge cases

### 5. Data Models (`lib/models/`)

**Purpose**: JSON schemas for structured data validation

**Components**:

- **checkpoint.schema.json**: Checkpoint file format
- **transaction-log.schema.json**: Transaction log format
- **provisioning-session.schema.json**: Session state format

## Data Flow

```
User Command (CLI)
    ↓
Argument Parsing & Validation (bin/vps-provision)
    ↓
Configuration Loading (core/config.sh)
    ↓
Pre-flight Checks (core/validator.sh)
    ↓
Phase Orchestration (bin/vps-provision main loop)
    ↓
Module Execution (lib/modules/*.sh)
    ├→ Transaction Recording (core/transaction.sh)
    ├→ Checkpoint Creation (core/checkpoint.sh)
    ├→ Progress Updates (core/progress.sh)
    └→ Logging (core/logger.sh)
    ↓
Verification (modules/verification.sh)
    ↓
Summary Report (modules/summary-report.sh)
    ↓
Exit with Status Code
```

## Error Handling Flow

```
Error Detected
    ↓
Error Handler (core/error-handler.sh)
    ↓
Log Error Details (core/logger.sh)
    ↓
Rollback Decision
    ├→ Automatic Rollback (core/rollback.sh)
    │   ├→ Parse Transaction Log (LIFO order)
    │   ├→ Execute Rollback Commands
    │   └→ Verify Clean State
    └→ Exit with Error Code
```

## State Management

### Checkpoints

**Location**: `/var/vps-provision/checkpoints/`

**Format**: Empty marker files with phase names

**Purpose**: Enable idempotent re-runs by tracking completed phases

**Lifecycle**:

1. Check: `checkpoint_exists "phase-name"`
2. Create: `checkpoint_create "phase-name"`
3. Clear: `checkpoint_clear_all` (on `--force`)

### Transaction Log

**Location**: `/var/log/vps-provision/transactions.log`

**Format**: One line per action, tab-separated

```
TIMESTAMP	ACTION_DESCRIPTION	ROLLBACK_COMMAND
```

**Purpose**: Record every state-changing action with its undo command

**Usage**: Parsed in reverse order (LIFO) during rollback

### Progress State

**Location**: `/var/vps-provision/progress.state`

**Format**: Key-value pairs

```
CURRENT_PHASE=3
PHASE_NAME=ide-vscode
START_TIME=1703433600
```

**Purpose**: Resume provisioning after interruption

## Security Architecture

### Input Sanitization

All user inputs pass through `lib/core/sanitize.sh`:

- Username validation: alphanumeric + underscore/hyphen
- File path validation: prevent path traversal
- Log level validation: whitelist approach
- Phase name validation: predefined list only

### Credential Management

- Passwords generated via `secrets` module (CSPRNG)
- Minimum 16 characters with mixed case, digits, symbols
- Redacted in all log outputs using `[REDACTED]` marker
- Displayed to terminal once, never persisted unencrypted

### Privilege Management

- Root execution required (validated in preflight)
- Developer user created with limited sudo privileges
- Service accounts isolated with minimal permissions
- Firewall rules enforce least privilege access

### Audit Logging

- All actions logged to `/var/log/vps-provision/`
- Transaction log immutable after creation
- System audit logs (auditd) configured for security events
- SSH access logged and monitored

## Testing Architecture

### Unit Tests (`tests/unit/`)

**Framework**: bats-core

**Coverage**: Individual functions in core libraries

**Pattern**:

```bash
@test "function_name returns expected result" {
  # Arrange
  local input="test"

  # Act
  result=$(function_name "$input")

  # Assert
  [[ "$result" == "expected" ]]
}
```

### Integration Tests (`tests/integration/`)

**Framework**: bats-core with Docker containers

**Coverage**: Module interactions, system integration

**Pattern**:

- Mock external dependencies
- Test happy paths and error scenarios
- Validate checkpoint and transaction behavior

### Contract Tests (`tests/contract/`)

**Framework**: bats-core + JSON schema validation

**Coverage**: CLI interface, output formats, exit codes

**Purpose**: Ensure backward compatibility

### E2E Tests (`tests/e2e/`)

**Framework**: Bash scripts on real VPS instances

**Coverage**: Full provisioning workflow, multi-session scenarios

**Duration**: 15+ minutes per test run

## Performance Considerations

### Parallel Execution

Phases executed sequentially for predictability. Future enhancement: parallel IDE installations.

### Caching Strategy

- Package manager cache preserved between phases
- Desktop environment packages cached locally
- IDE installers downloaded once, validated before use

### Resource Monitoring

- Memory usage tracked during package installations
- CPU usage monitored to prevent system overload
- Disk space validated before and after each phase

### Network Optimization

- Retry logic with exponential backoff (3 attempts)
- Connection pooling for repeated downloads
- Parallel downloads for independent packages (future)

## Extensibility Points

### Adding New IDEs

1. Create `lib/modules/ide-newname.sh` following existing pattern
2. Implement `ide_newname_execute()` with checkpoints
3. Add phase to `bin/vps-provision` orchestration
4. Update documentation and help text
5. Add integration test in `tests/integration/`

### Adding New Configuration Options

1. Add default value to `config/default.conf`
2. Update `lib/core/config.sh` validation
3. Document in help text and README
4. Add sanitization in `lib/core/sanitize.sh` if needed
5. Update contract tests

### Adding New Validation Checks

1. Add function to `lib/core/validator.sh`
2. Call from preflight or post-install phase
3. Define success criteria and error messages
4. Add test in `tests/unit/test_validator.bats`

## Deployment Considerations

### Installation

- Single-file deployment: all dependencies self-contained
- No external package manager dependencies (npm, pip)
- Bash 5.1+ and Python 3.11+ assumed present on Debian 13

### Updates

- Version number in `bin/vps-provision` header
- Backward compatibility for config files maintained
- Migration scripts for breaking changes (future)

### Monitoring

- Log rotation configured (logrotate)
- Health check endpoint (future: systemd service)
- Metrics exported for monitoring systems (future)

## Future Enhancements

### Short-term (Next Release)

- Parallel IDE installation to reduce total time
- Web UI for remote provisioning
- Support for additional Linux distributions

### Long-term (Roadmap)

- Plugin architecture for custom provisioning steps
- Cloud-init integration for automated deployment
- Configuration management integration (Ansible, Puppet)
- Kubernetes deployment for containerized workstations

## References

- [Bash Best Practices](https://www.gnu.org/software/bash/manual/)
- [POSIX Shell Standard](https://pubs.opengroup.org/onlinepubs/9699919799/)
- [Security Hardening Guide](https://www.debian.org/doc/manuals/securing-debian-manual/)
- [Idempotency Patterns](https://en.wikipedia.org/wiki/Idempotence)
