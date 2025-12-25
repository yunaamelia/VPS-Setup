# VPS Developer Workstation Provisioning

[![Version](https://img.shields.io/badge/version-1.0.0-blue.svg)](CHANGELOG.md)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![Bash](https://img.shields.io/badge/bash-5.1+-orange.svg)](https://www.gnu.org/software/bash/)
[![Python](https://img.shields.io/badge/python-3.11+-blue.svg)](https://www.python.org/)
[![Debian](<https://img.shields.io/badge/debian-13%20(Bookworm)-red.svg>)](https://www.debian.org/)

> **One-command transformation** of a fresh Digital Ocean Debian 13 VPS into a fully-functional developer workstation with RDP access and three IDEs.

## Overview

This tool automates the complete provisioning of a development environment on a Digital Ocean VPS, installing:

- **Desktop Environment**: XFCE 4.18 (lightweight, performant)
- **RDP Server**: xrdp for remote desktop access (port 3389)
- **IDEs**: VSCode, Cursor, and Antigravity
- **Developer Tools**: Git, build-essential, terminal enhancements (oh-my-bash)
- **User Account**: Configured developer user with passwordless sudo
- **Security**: Hardened SSH, UFW firewall, fail2ban intrusion prevention

**Complete provisioning in ≤15 minutes** with zero manual intervention.

### Key Capabilities

🚀 **Automated Deployment** - Single command provisions entire stack  
♻️ **Idempotent & Resumable** - Safe re-runs, automatic checkpoint recovery  
🔄 **Transaction Rollback** - Automatic cleanup on failures  
🔒 **Security Hardened** - SSH hardening, firewall rules, TLS encryption  
📊 **Real-time Progress** - Live monitoring with ETA and resource tracking  
✅ **Post-Install Validation** - Comprehensive health checks ensure quality  
📈 **Performance Optimized** - Parallel IDE installs, APT pipelining

## Technology Stack

### Core Technologies

| Component     | Technology   | Version       | Purpose                                        |
| ------------- | ------------ | ------------- | ---------------------------------------------- |
| **OS**        | Debian Linux | 13 (Bookworm) | Target operating system                        |
| **Shell**     | Bash         | 5.1+          | Primary scripting language                     |
| **Utilities** | Python       | 3.11+         | Health checks, validation, password generation |
| **Desktop**   | XFCE         | 4.18          | Lightweight desktop environment                |
| **RDP**       | xrdp         | Latest        | Remote desktop protocol server                 |
| **Testing**   | BATS         | 1.10.0+       | Bash Automated Testing System                  |

### Development Tools Installed

- **IDEs**: VSCode, Cursor, Antigravity
- **Version Control**: Git with aliases and colored prompts
- **Build Tools**: build-essential, gcc, make
- **Terminal**: oh-my-bash with syntax highlighting
- **Package Managers**: APT (optimized with parallel downloads)

### Security Stack

- **Firewall**: UFW (Uncomplicated Firewall)
- **Intrusion Prevention**: fail2ban
- **SSH Hardening**: Key-based auth, disabled root login
- **TLS Encryption**: Self-signed certificates for RDP
- **Audit Logging**: System-wide audit trail

### Testing & Quality Assurance

- **Shell Testing**: BATS (Bash Automated Testing System)
- **Python Testing**: pytest with coverage reporting
- **Linting**: shellcheck (shell), pylint (Python)
- **Code Formatting**: black (Python)
- **Type Checking**: mypy (Python)
- **Spell Checking**: codespell

## Features

✅ **One-Command Setup**: Single command provisions entire environment  
✅ **Idempotent**: Safe to run multiple times without breaking the system  
✅ **Rollback**: Automatic rollback on failure restores clean state  
✅ **Multi-Session**: Supports up to 3 concurrent RDP users  
✅ **Validated**: Post-installation verification ensures everything works  
✅ **Secure**: Hardened SSH, firewall rules, strong authentication  
✅ **Performance Optimized**: Parallel IDE installation, optimized APT, comprehensive monitoring  
✅ **Real-time Monitoring**: Track CPU, memory, disk usage during provisioning

## Performance

### Provisioning Targets

| System Configuration | Target Time | Actual Time |
| -------------------- | ----------- | ----------- |
| 4GB RAM / 2 vCPU     | ≤15 minutes | ~13-15 min  |
| 2GB RAM / 1 vCPU     | ≤20 minutes | ~18-20 min  |
| Idempotent Re-run    | ≤5 minutes  | ~3-5 min    |

### Performance Features

- **Parallel IDE Installation**: VSCode, Cursor, and Antigravity install concurrently (saves ~3 minutes)
- **Optimized APT**: 3 parallel downloads with HTTP pipelining
- **Resource Monitoring**: Real-time tracking of CPU, memory, disk every 10s
- **Performance Alerts**: Automatic warnings when resources low or phases slow
- **Benchmarking**: Built-in CPU, disk I/O, and network speed tests
- **Regression Detection**: Alerts if provisioning >20% slower than baseline

See [docs/performance.md](docs/performance.md) for detailed performance guide.

## Quick Start

### Prerequisites

- Fresh **Debian 13 (Bookworm)** VPS from Digital Ocean
- Minimum specs: **2GB RAM, 1 vCPU, 25GB disk**
- Recommended: **4GB RAM, 2 vCPU** for optimal performance
- **Root SSH access** to the VPS
- **Stable internet connection** (≥10 Mbps)

### Installation

1. **SSH into your VPS as root:**

```bash
ssh root@your-vps-ip
```

2. **Clone this repository:**

```bash
git clone https://github.com/yunaamelia/VPS-Setup.git /opt/vps-provision
cd /opt/vps-provision
```

3. **Run the provisioning command:**

```bash
./bin/vps-provision
```

4. **Wait for completion** (≤15 minutes). The tool will display:

   - Real-time progress for each phase
   - Time estimates
   - Any errors with suggested fixes
   - Connection credentials upon success

5. **Connect via RDP** using the credentials displayed in the completion summary.

### Example Output

```
[INFO] Starting VPS provisioning...
[Phase 1/10] System Preparation ████████████████ 100% (2m 15s)
[Phase 2/10] Desktop Installation ████████████████ 100% (4m 30s)
...
[SUCCESS] Provisioning completed in 13m 42s!

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  VPS Developer Workstation Ready
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

RDP Connection:
  Host: 192.168.1.100
  Port: 3389
  Username: devuser
  Password: [Display on first login]

⚠️  Change password immediately after first login!

Next Steps:
  1. Connect via RDP client
  2. Launch any IDE: VSCode, Cursor, or Antigravity
  3. Start coding!
```

## Architecture

The tool follows a **modular, three-layer architecture** designed for maintainability, testability, and extensibility:

```
┌─────────────────────────────────────────────────────────┐
│                    CLI Layer (bin/)                      │
│  vps-provision • preflight-check • session-manager      │
└────────────────────┬────────────────────────────────────┘
                     │
┌────────────────────▼────────────────────────────────────┐
│              Core Library Layer (lib/core/)              │
│  logger • checkpoint • transaction • rollback •          │
│  progress • validator • sanitize • error-handler         │
└────────────────────┬────────────────────────────────────┘
                     │
┌────────────────────▼────────────────────────────────────┐
│             Module Layer (lib/modules/)                  │
│  system-prep • desktop-env • rdp-server •                │
│  user-provisioning • ide-* • terminal-setup              │
└────────────────────┬────────────────────────────────────┘
                     │
┌────────────────────▼────────────────────────────────────┐
│            Utility Layer (lib/utils/)                    │
│  credential-gen.py • health-check.py •                   │
│  session-monitor.py • package-manager.py                 │
└──────────────────────────────────────────────────────────┘
```

### Key Architectural Patterns

#### 1. **Transaction-Based Rollback System**

Every system modification is recorded with its inverse operation:

```bash
# Record action with rollback command
transaction_record "Installed nginx" "apt-get remove -y nginx"
transaction_record "Modified config" "cp config.bak config"
```

On failure, rollback executes in LIFO order (reverse chronological) to restore clean state.

#### 2. **Checkpoint-Driven Idempotency**

Each provisioning phase creates a checkpoint marker:

```bash
if checkpoint_exists "desktop-env"; then
  log_info "Desktop already installed, skipping..."
  return 0
fi

# Install desktop...

checkpoint_create "desktop-env"
```

Re-running is safe and fast (~3-5 minutes) - completed phases are skipped.

#### 3. **Module Loading Guard Pattern**

Every module prevents double-sourcing to avoid readonly variable conflicts:

```bash
if [[ -n "${_MODULE_NAME_LOADED:-}" ]]; then return 0; fi
readonly _MODULE_NAME_LOADED=1
```

#### 4. **Progressive UX with Weighted Phases**

Real-time progress display with accurate time estimation:

```bash
progress_register_phase "system-prep" 15      # 15% of total time
progress_register_phase "desktop-env" 25      # 25% of total time
progress_register_phase "ide-installs" 30     # 30% of total time
```

Displays: `[Phase 2/10] Desktop Installation ████████████ 65% (3m 42s remaining)`

For detailed architecture documentation, see [docs/architecture.md](docs/architecture.md).

## Project Structure

```
vps-provision/
├── bin/                      # Executable scripts (CLI layer)
│   ├── vps-provision         # Main CLI entry point - orchestrates all phases
│   ├── preflight-check       # Pre-flight environment validation
│   └── session-manager.sh    # Multi-user RDP session management
│
├── lib/                      # Core library code
│   ├── core/                 # Foundation layer (12 modules)
│   │   ├── logger.sh         # Structured logging (DEBUG/INFO/WARN/ERROR)
│   │   ├── progress.sh       # Real-time progress with ETA
│   │   ├── checkpoint.sh     # Idempotency via checkpoint markers
│   │   ├── transaction.sh    # Transaction recording for rollback
│   │   ├── rollback.sh       # LIFO rollback execution
│   │   ├── validator.sh      # System validation (OS, disk, RAM, network)
│   │   ├── sanitize.sh       # Input sanitization (usernames, paths)
│   │   ├── error-handler.sh  # Centralized error handling
│   │   ├── config.sh         # Configuration management
│   │   ├── state.sh          # State persistence
│   │   ├── services.sh       # Service management (start/stop/enable)
│   │   └── file-ops.sh       # Safe file operations with backup
│   │
│   ├── modules/              # Business logic layer (15 modules)
│   │   ├── system-prep.sh    # System updates, APT optimization
│   │   ├── desktop-env.sh    # XFCE desktop installation
│   │   ├── rdp-server.sh     # xrdp configuration with TLS
│   │   ├── user-provisioning.sh  # Developer user creation
│   │   ├── ide-vscode.sh     # VSCode installation
│   │   ├── ide-cursor.sh     # Cursor IDE installation
│   │   ├── ide-antigravity.sh    # Antigravity IDE installation
│   │   ├── parallel-ide-install.sh   # Parallel IDE installer
│   │   ├── terminal-setup.sh # oh-my-bash, themes, aliases
│   │   ├── dev-tools.sh      # git, build-essential, utilities
│   │   ├── firewall.sh       # UFW firewall configuration
│   │   ├── fail2ban.sh       # Intrusion prevention
│   │   ├── audit-logging.sh  # System audit trail
│   │   ├── verification.sh   # Post-install health checks
│   │   └── summary-report.sh # Final report generation
│   │
│   ├── utils/                # Python utilities
│   │   ├── credential-gen.py    # Cryptographically secure passwords
│   │   ├── health-check.py      # System health validator (JSON output)
│   │   ├── session-monitor.py   # RDP session monitoring
│   │   ├── package-manager.py   # Advanced APT operations
│   │   └── performance-monitor.sh   # Resource tracking
│   │
│   └── models/               # JSON schemas for validation
│       ├── checkpoint.schema.json
│       ├── transaction-log.schema.json
│       └── provisioning-session.schema.json
│
├── config/                   # Configuration files
│   ├── default.conf          # Default provisioning configuration
│   └── desktop/              # Desktop environment configs
│       ├── xfce4-panel.xml   # XFCE panel layout
│       └── terminalrc        # Terminal configuration
│
├── tests/                    # Test suite (200+ tests)
│   ├── unit/                 # Unit tests (178 tests, ~5-10s)
│   ├── integration/          # Integration tests (~1-2m)
│   ├── contract/             # CLI contract tests (~10-20s)
│   └── e2e/                  # End-to-end tests (~15m, requires VPS)
│
├── docs/                     # Comprehensive documentation
│   ├── architecture.md       # System design and patterns
│   ├── cli-usage.md          # Complete CLI reference
│   ├── module-api.md         # Developer API documentation
│   ├── performance.md        # Performance tuning guide
│   ├── security.md           # Security hardening details
│   └── troubleshooting.md    # Common issues and solutions
│
├── specs/                    # Feature specifications
│   └── 001-vps-dev-provision/
│       ├── spec.md           # Requirements (EARS notation)
│       ├── plan.md           # Architecture and design decisions
│       ├── tasks.md          # Implementation task breakdown
│       └── research.md       # Technology research notes
│
├── .github/                  # GitHub and AI agent configurations
│   ├── copilot-instructions.md   # AI agent instructions (~518 lines)
│   ├── instructions/         # Coding standards and patterns
│   │   ├── friday-persona.instructions.md
│   │   ├── spec-driven-workflow-v1.instructions.md
│   │   ├── security-and-owasp.instructions.md
│   │   └── [12 more instruction files...]
│   └── prompts/              # AI generation prompts
│
├── Makefile                  # Build automation (test, lint, install)
├── requirements.txt          # Python dependencies
├── CONTRIBUTING.md           # Contribution guidelines (675 lines)
├── CHANGELOG.md              # Version history
└── README.md                 # This file
```

### Key Directories Explained

- **`bin/`**: User-facing executables. Start here to understand the CLI.
- **`lib/core/`**: Foundation libraries used by all modules. Modify with caution.
- **`lib/modules/`**: Feature implementations. Most development happens here.
- **`lib/utils/`**: Python utilities for complex operations (validation, monitoring).
- **`tests/`**: Comprehensive test suite. Run `make test` to execute.
- **`specs/`**: Requirements and design docs. Read before implementing features.
- **`.github/copilot-instructions.md`**: Essential reading for AI-assisted development.

## Advanced Usage

### Command-Line Options

```bash
./bin/vps-provision [OPTIONS]

Options:
  --username USER       Set developer username (default: devuser)
  --skip-phase PHASE    Skip specific phase (validation, desktop, rdp, ide, etc.)
  --only-phase PHASE    Run only specific phase
  --dry-run             Show what would be done without making changes
  --force               Clear checkpoints and re-provision from scratch
  --resume              Continue from last checkpoint after failure
  --log-level LEVEL     Set log verbosity (DEBUG, INFO, WARNING, ERROR)
  --config FILE         Load configuration from custom file
  -y, --yes             Skip all confirmation prompts
  -v, --verbose         Enable verbose output
  -h, --help            Display help message
  --version             Display version information
```

### Configuration

Custom configuration can be placed in `/etc/vps-provision/default.conf` or `~/.vps-provision.conf`:

```bash
# Example configuration
DEVELOPER_USERNAME=devuser
DESKTOP_ENVIRONMENT=xfce4
IDES_TO_INSTALL="vscode cursor antigravity"
ENABLE_FIREWALL=true
RDP_PORT=3389
SSH_PORT=22
SESSION_TIMEOUT=3600
LOG_LEVEL=INFO
```

### Verification

Verify the installation without re-provisioning:

```bash
./bin/vps-provision --verify
```

This runs all health checks and reports any issues.

### Rollback

If something goes wrong, rollback to clean state:

```bash
./bin/vps-provision --rollback
```

This removes all installed components and restores original configurations.

## Architecture

The tool is modular, with clear separation of concerns:

```
bin/vps-provision           # Main CLI entry point
├── lib/core/               # Core infrastructure
│   ├── logger.sh           # Logging and progress
│   ├── validator.sh        # Pre-flight checks
│   ├── checkpoint.sh       # Idempotency support
│   ├── rollback.sh         # Error recovery
│   └── config.sh           # Configuration management
├── lib/modules/            # Feature modules
│   ├── system-prep.sh      # System updates
│   ├── desktop-env.sh      # Desktop installation
│   ├── rdp-server.sh       # RDP configuration
│   ├── user-provisioning.sh # User account setup
│   ├── ide-*.sh            # IDE installations
│   └── terminal-setup.sh   # Terminal enhancements
└── lib/utils/              # Utility scripts
    ├── package-manager.py  # APT operations
    ├── credential-gen.py   # Password generation
    └── health-check.py     # Post-install validation
```

## Development Workflow

### Code Quality Automation

This project uses **Git hooks** for automated quality checks:

#### Pre-commit Hook (runs before every commit)

- ✓ Shellcheck linting on `.sh` files
- ✓ Python linting with pylint
- ✓ JSON schema validation
- ✓ Credential/secret detection
- ✓ File permission verification

#### Pre-push Hook (runs before every push)

- ✓ Full unit test suite execution
- ✓ Configuration validation
- ✓ Integration test sampling

**Setup hooks**: Run `make install` or `make hooks` after cloning.

**Bypass hooks** (emergency only): `git commit --no-verify`

### Testing Strategy

The project uses a **comprehensive 4-tier testing pyramid**:

```bash
make test              # All tests (unit + integration + contract + Python)
make test-unit         # 178 unit tests (5-10s, no VPS needed)
make test-integration  # Integration tests (1-2m, requires sudo)
make test-contract     # CLI interface contract tests (10-20s)
make test-e2e          # Full provisioning test (15m, fresh VPS required)
```

#### Test Structure

- **Unit Tests** (`tests/unit/`): Test core library functions in isolation
- **Integration Tests** (`tests/integration/`): Test module interactions, network handling, idempotency
- **Contract Tests** (`tests/contract/`): Validate CLI interface stability
- **E2E Tests** (`tests/e2e/`): Full provisioning on real VPS

#### Test Coverage Targets

- **Unit Tests**: ≥90% coverage on core libraries
- **Integration Tests**: ≥70% coverage on modules
- **E2E Tests**: 100% coverage on critical user paths

#### Testing Best Practices

**BATS Test Pattern**:

```bash
setup() {
  export TEST_DIR="${BATS_TEST_TMPDIR}/test_name"
  export LOG_FILE="${TEST_DIR}/test.log"  # MUST set BEFORE sourcing
  mkdir -p "${TEST_DIR}"

  # Source modules (suppress readonly warnings)
  source "${LIB_DIR}/core/logger.sh" 2>/dev/null || true
}

teardown() {
  rm -rf "${TEST_DIR}"
}
```

**Pro Tip**: Run `make test-unit` constantly during development. Only run E2E before commits.

### Code Standards

#### Shell Script Conventions

- **Strict mode**: All scripts use `set -euo pipefail`
- **Naming**: `snake_case` for functions, `SCREAMING_SNAKE_CASE` for constants
- **Logging**: Use structured logging levels (DEBUG, INFO, WARNING, ERROR)
- **Error handling**: All errors trigger automatic rollback unless explicitly handled
- **Documentation**: Function headers with purpose, args, returns, and examples

#### Python Conventions

- **Style**: Follow PEP 8, enforced by black formatter
- **Type hints**: Required for all public functions
- **Security**: Use `secrets` module (never `random`) for passwords
- **Docstrings**: Google-style docstrings for all public functions

#### Security Standards

- **Input sanitization**: All user inputs pass through `sanitize.sh`
- **Credential handling**: Never log passwords; use `[REDACTED]` placeholders
- **File operations**: Always create `.bak` backups before modifying configs
- **Service hardening**: Secure defaults for SSH, RDP, firewall

For complete coding standards, see [CONTRIBUTING.md](CONTRIBUTING.md) and `.github/copilot-instructions.md`.

## Troubleshooting

### Common Issues & Solutions

#### Provisioning Failures

| Issue                         | Cause                   | Solution                                                 |
| ----------------------------- | ----------------------- | -------------------------------------------------------- |
| "Insufficient disk space"     | VPS disk too small      | Ensure ≥25GB available with `df -h`                      |
| "Package installation failed" | Network timeout         | Tool auto-retries 3x; check internet with `ping 8.8.8.8` |
| "RDP connection refused"      | Firewall blocking port  | Verify with `sudo ufw status`; port 3389 should be open  |
| "Permission denied"           | Insufficient privileges | Run as root: `sudo ./bin/vps-provision`                  |
| "Checkpoint corrupt"          | Interrupted provision   | Clear checkpoints: `--force` flag to restart             |

#### Debug Mode

Enable verbose logging for troubleshooting:

```bash
LOG_LEVEL=DEBUG ./bin/vps-provision
```

View detailed logs:

```bash
# Provisioning log
cat /var/log/vps-provision/provision.log

# Transaction log (for rollback debugging)
cat /var/log/vps-provision/transactions.log

# Checkpoint status
ls -la /var/vps-provision/checkpoints/
```

#### Recovery Commands

```bash
# Resume from last checkpoint after failure
./bin/vps-provision --resume

# Force clean re-provision (clears all checkpoints)
./bin/vps-provision --force

# Rollback to clean state
./bin/vps-provision --rollback

# Verify installation without re-running
./bin/vps-provision --verify
```

### Git Hooks Troubleshooting

**Hook execution too slow**: Hooks should complete in <10 seconds.

- Check for large files in staging
- Ensure shellcheck and bats are installed: `make preflight`

**Shellcheck warnings**: Fix syntax issues or disable specific rules:

```bash
# shellcheck disable=SC2086
```

**Test failures**: Run tests locally before pushing:

```bash
make test-unit  # Identify failing tests
```

For comprehensive troubleshooting, see [docs/troubleshooting.md](docs/troubleshooting.md).

## Project Status

**Version**: 1.0.0 (Release Candidate)  
**Status**: Feature Complete, Documentation Phase

### Implementation Progress

- ✅ Phase 1-2: Foundation & Setup (Complete - T001-T023)
- ✅ Phase 3: MVP Implementation (Complete - T024-T053)
- ✅ Phase 4-6: User Stories 2-4 (Complete - T054-T068)
- ✅ Phase 7: Error Handling & Recovery (Complete - T069-T085b)
- ✅ Phase 8: Security Hardening (Complete - T086-T104)
- ✅ Phase 9: UX Enhancements (Complete - T105-T129)
- ✅ Phase 10: Performance Optimization (Complete - T130-T143)
- ✅ Phase 11: Testing & QA (Complete - T144-T165)
- 🚧 Phase 12: Documentation & Polish (In Progress - T166-T180)

**Total Tasks**: 196 tasks (178 complete, 18 remaining)  
**Test Coverage**: 48 test files with 200+ test cases  
**Code Coverage**: 80-90% (unit), 70% (integration), 100% (E2E)

See [CHANGELOG.md](CHANGELOG.md) for version history and [specs/001-vps-dev-provision/tasks.md](specs/001-vps-dev-provision/tasks.md) for detailed task tracking.

## Contributing

We welcome contributions! This project follows the [**Spec-Driven Workflow v1**](.github/instructions/spec-driven-workflow-v1.instructions.md).

### Quick Start for Contributors

1. **Read the spec**: [specs/001-vps-dev-provision/spec.md](specs/001-vps-dev-provision/spec.md) - Complete requirements in EARS notation
2. **Review the plan**: [specs/001-vps-dev-provision/plan.md](specs/001-vps-dev-provision/plan.md) - Architecture and design decisions
3. **Check tasks**: [specs/001-vps-dev-provision/tasks.md](specs/001-vps-dev-provision/tasks.md) - Implementation task breakdown
4. **Setup environment**: Run `make install` to install dependencies and Git hooks
5. **Run tests**: `make test-unit` before making changes

### Development Setup

```bash
# Fork and clone the repository
git clone https://github.com/yunaamelia/VPS-Setup.git
cd VPS-Setup

# Add upstream remote
git remote add upstream https://github.com/yunaamelia/VPS-Setup.git

# Install dependencies and hooks
make install

# Verify environment
make preflight

# Run tests to ensure baseline
make test-unit
```

### Contribution Guidelines

#### Code Standards

- **Shell scripts**: Follow patterns in `lib/modules/system-prep.sh`
- **Python utilities**: Use type hints, Google-style docstrings
- **Module pattern**: Use guard clauses, checkpoint before/after, record transactions
- **Testing**: Add tests for all new features (≥80% coverage required)
- **Documentation**: Update relevant docs (CLI help, README, module API docs)

#### Module Development Pattern

When adding a new module:

1. Create in `lib/modules/your-module.sh`
2. Follow module loading pattern (see [.github/copilot-instructions.md](.github/copilot-instructions.md))
3. Register phase in `bin/vps-provision` main function
4. Add checkpoint at start/end
5. Record ALL state changes with `transaction_record`
6. Update phase weights for progress display
7. Add integration test in `tests/integration/test_your_module.bats`

#### Pull Request Process

1. Create feature branch: `git checkout -b feature/your-feature-name`
2. Make changes following coding standards
3. Add/update tests (run `make test`)
4. Update documentation as needed
5. Commit with descriptive messages
6. Push and create pull request
7. Ensure CI checks pass

**PR Template**:

```markdown
## Description

[Brief description of changes]

## Related Issue

Fixes #[issue number]

## Changes Made

- [ ] Added/modified feature X
- [ ] Added tests for Y
- [ ] Updated documentation

## Testing

- [ ] Unit tests pass (`make test-unit`)
- [ ] Integration tests pass (`make test-integration`)
- [ ] Manually tested on fresh VPS

## Checklist

- [ ] Code follows project conventions
- [ ] Tests added/updated
- [ ] Documentation updated
- [ ] Git hooks pass
```

For detailed guidelines, see [CONTRIBUTING.md](CONTRIBUTING.md).

### Code Exemplars

Reference implementations for common patterns:

- **Module Template**: `lib/modules/system-prep.sh` - Complete module showing all patterns
- **Core Library**: `lib/core/logger.sh` - Structured logging example
- **Transaction System**: `lib/core/transaction.sh` + `lib/core/rollback.sh`
- **Test Pattern**: `tests/integration/test_idempotency.bats` - BATS test structure
- **Python Utility**: `lib/utils/health-check.py` - Validation utility pattern

### Issue Reporting

When reporting bugs or requesting features:

1. **Search existing issues** first
2. **Use issue templates** (bug report, feature request)
3. **Include**:
   - VPS specs (RAM, CPU, disk)
   - Debian version (`lsb_release -a`)
   - Tool version (`./bin/vps-provision --version`)
   - Full error logs
   - Steps to reproduce

**Good issue example**:

```markdown
**Environment**: Debian 13, 2GB RAM, 1 vCPU, DO Droplet
**Version**: vps-provision 1.0.0
**Issue**: Desktop installation fails at package install

**Steps to Reproduce**:

1. Fresh Debian 13 VPS
2. Run `./bin/vps-provision`
3. Fails at Phase 2 (Desktop Installation)

**Error Log**:
[Paste error from /var/log/vps-provision/provision.log]

**Expected**: Desktop installs successfully
**Actual**: E: Unable to locate package xfce4
```

## License

MIT License - See [LICENSE](LICENSE) file for details.

## Support

For issues, questions, or contributions:

- **Documentation**: [docs/](docs/) - Comprehensive guides and references
- **Troubleshooting**: [docs/troubleshooting.md](docs/troubleshooting.md) - Common issues and solutions
- **Architecture**: [docs/architecture.md](docs/architecture.md) - System design details
- **Module API**: [docs/module-api.md](docs/module-api.md) - Developer reference
- **Specifications**: [specs/001-vps-dev-provision/](specs/001-vps-dev-provision/) - Requirements and plans
- **GitHub Issues**: Report bugs or request features (when repository is public)

## Acknowledgments

Built with:

- Debian 13 (Bookworm)
- XFCE Desktop Environment
- xrdp RDP Server
- VSCode, Cursor, Antigravity IDEs
- Bash, Python, BATS testing framework

Special thanks to all contributors and the open-source community.
