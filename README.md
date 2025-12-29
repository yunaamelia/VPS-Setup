# VPS Developer Workstation Provisioning Tool

An enterprise-grade, automated provisioning system designed to transform a fresh Debian 13 VPS into a fully-functional, secure, and remote-accessible developer workstation.

## 📖 Overview

This project provides a robust, idempotent, and fail-safe automation suite that sets up a complete development environment. It handles everything from system hardening and desktop environment installation to configuring RDP access and installing modern development tools like VSCode, Cursor, and Antigravity.

## 🛠 Technology Stack

### Core System
- **OS**: Debian 13 "Trixie" (Testing)
- **Shell**: Bash 5.1+ (Strict Mode `set -euo pipefail`)
- **Scripting**: Python 3.11+ (Type-hinted utilities)

### Desktop & Access
- **Desktop Environment**: XFCE4 (Optimized for performance)
- **Remote Access**: xrdp (Secure RDP configuration)
- **Browser**: Firefox ESR

### Development Tools
- **IDEs**: VSCode, Cursor, Antigravity
- **Build Tools**: build-essential, GNU Make, Git
- **Shell Environment**: oh-my-bash, customized `.bashrc`

### Testing & Quality
- **Test Framework**: BATS (Bash Automated Testing System)
- **Linting**: ShellCheck, Pylint, Flake8

## 🏗 Project Architecture

The system follows a strict **Four-Layer Architecture** to ensure modularity, maintainability, and reliability:

1.  **CLI Layer** (`bin/`)
    - Entry point handling, argument parsing, and user interaction.
    - **Key Component**: `vps-provision`

2.  **Core Library Layer** (`lib/core/`)
    - Foundation services sharing no business logic.
    - **Components**: `logger.sh`, `config.sh`, `checkpoint.sh`, `transaction.sh`

3.  **Module Layer** (`lib/modules/`)
    - Business logic isolated into independent, pluggable modules.
    - **Components**: `system-prep.sh`, `desktop.sh`, `rdp.sh`, `ide.sh`

4.  **Utility Layer** (`lib/utils/`)
    - Specialized Python scripts for complex logic (data processing, validation).
    - **Components**: `health-check.py`, `credential-gen.py`

### Key Architectural Patterns
- **Checkpoint-Driven Idempotency**: Logic can be re-run safely; completed phases are skipped.
- **Transaction-Based State Management**: Operations are tracked for reliable rollback on failure.
- **Fail-Safe Usage**: "Strict Mode" always enabled; errors trigger immediate cleanup.

## 🚀 Getting Started

### Prerequisites
- A fresh **Debian 13 (Trixie)** VPS.
- Root or sudo access.
- Minimum 2GB RAM / 20GB Disk recommended.

### Installation & Usage

1.  **Clone the Repository**
    ```bash
    git clone https://github.com/your-org/vps-setup.git
    cd vps-setup
    ```

2.  **Run the Provisioner**
    ```bash
    # Standard run
    sudo ./bin/vps-provision

    # Run with custom username
    sudo ./bin/vps-provision --username mydevuser
    ```

3.  **Connect via RDP**
    - Use any RDP client (Remote Desktop Connection, Remmina).
    - Connect to the VPS IP address.
    - Login with the credentials provided at the end of the provisioning process.

## 📂 Project Structure

```text
vps-setup/
├── bin/                # Executable entry points
│   └── vps-provision   # Main CLI script
├── config/             # Configuration templates and defaults
├── docs/               # Architecture blueprints and guides
├── lib/
│   ├── core/           # Core infrastructure (logging, checkpoints)
│   ├── modules/        # Feature modules (installers, setup)
│   ├── models/         # Data structures
│   └── utils/          # Python helper scripts
├── specs/              # Technical specifications and implementation plans
├── tests/              # BATS test suites
├── Makefile            # Build and test automation
└── requirements.txt    # Python dependencies
```

## ✨ Key Features

- **Idempotence**: Safe to run multiple times. Detects and skips completed tasks.
- **Auto-Rollback**: Automatically reverts changes if a critical step fails.
- **Modular Architecture**: Easily add new modules (e.g., specific dev stacks) without touching core logic.
- **Progressive UX**: clear, weighted progress bars and status updates.
- **Secure By Design**: Generated credentials, limited root usage, secure RDP settings.

## 🔄 Development Workflow

We follow a **Spec-Driven Development** process:

1.  **Design**: Create/Update a spec in `specs/`.
2.  **Branch**: Create a feature branch (e.g., `feat/new-module`).
3.  **Test**: Write BATS tests in `tests/` covering the new functionality.
4.  **Implement**: Write code in `lib/` adhering to the spec.
5.  **Verify**: Run `make test` to ensure no regressions.
6.  **Review**: Submit a Pull Request.

## 📏 Coding Standards

### Bash
- **Strict Mode**: All scripts must start with `set -euo pipefail`.
- **Style**: Google Shell Style Guide (2-space indent, snake_case functions).
- **Validation**: Must pass `shellcheck` without warnings.
- **Headers**: All files must have a header describing purpose and usage.

### Python
- **Style**: PEP 8 compliance.
- **Type Hints**: Mandatory for all function signatures.
- **Docstrings**: Google-style docstrings for modules and functions.

## 🧪 Testing

The project uses a comprehensive testing strategy driven by **BATS**:

- **Unit Tests**: `make test-unit` - Isolated function tests.
- **Integration Tests**: `make test-integration` - Module interaction verification.
- **Full Suite**: `make test` - Runs all tests including style checks.

## 🤝 Contributing

Contributions are welcome! Please read [CONTRIBUTING.md](CONTRIBUTING.md) for detailed guidelines on setting up your development environment, submitting PRs, and our code of conduct.

## 📄 License

See the repository details for license information.
