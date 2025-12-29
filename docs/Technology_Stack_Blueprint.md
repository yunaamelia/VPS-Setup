# Technology Stack Blueprint

## 1. Project Overview

| Attribute | Details |
| :--- | :--- |
| **Project Name** | `vps-provision` |
| **Description** | Automated VPS provisioning and configuration system |
| **Primary Languages** | Bash (Shell), Python 3.x |
| **Architecture** | Modular CLI with library-based architecture |
| **Target Platform** | Debian 13 (Bookworm) |
| **Analysis Depth** | Implementation-Ready |

## 2. Core Technologies

### 2.1 Shell / Bash Stack (Primary)
The core logic of the provisioning system is built using Bash scripting, emphasizing portability and direct system interaction.

-   **Language Version**: Bash 4.x+ (Debian standard)
-   **Execution Mode**: Strict Mode (`set -euo pipefail`)
-   **Architecture**: Modular library system (`lib/`) + entry point (`bin/`)
-   **Style Guide**: enforcing POSIX compatibility where possible, structured variable naming.

### 2.2 Python Stack (Secondary)
Python is used for complex logic, utility scripts, and cross-platform compatibility tasks where Shell might be brittle (e.g., complex string parsing, structured data handling).

-   **Language Version**: Python 3.11+ (Debian 13 standard)
-   **Virtual Environment**: `.venv` (managed via `docs/quickstart.md` or `Makefile`)
-   **Core Libraries**:
    -   `psutil` (>=5.9.0): System monitoring and process management.

### 2.3 Build & Task Management
-   **Tool**: GNU Make
-   **Configuration**: `Makefile`
-   **Usage**: Wraps all development workflows (install, test, lint, clean, build).
-   **Performance**: configured with `PARALLEL_JOBS := 4` and `--output-sync=target` for parallel execution.

## 3. Tooling & Development Ecosystem

### 3.1 Testing Frameworks

| Type | Framework | Target | Description |
| :--- | :--- | :--- | :--- |
| **Unit/Integration** | **bats-core** (v1.10.0) | Shell | The Bash Automated Testing System. Used for testing Bash functions and scripts. |
| **Unit/Integration** | **pytest** (>=7.4.0) | Python | Standard testing framework for Python utilities. |
| **Coverage** | **pytest-cov** (>=4.1.0) | Python | Measures code coverage for Python tests. |

### 3.2 Linting & Static Analysis

| Tool | Language | Purpose | Configuration |
| :--- | :--- | :--- | :--- |
| **ShellCheck** | Shell | Static analysis | Detects bugs and stylistic issues in shell scripts. |
| **shfmt** | Shell | Formatting | Enforces consistent indentation (2 spaces) and style. |
| **Flake8** | Python | Linting | Checks for PEP 8 compliance and logic errors. |
| **Pylint** | Python | Linting | Deep static code analysis. |
| **Black** | Python | Formatting | Uncompromising code formatter. |
| **Mypy** | Python | Type Checking | Static type checker for type safety. |
| **Codespell** | Mixed | Spell Check | Checks for common spelling errors in code and docs. |

### 3.3 Infrastructure & Virtualization

-   **Development**:
    -   **Docker**: Used to run isolated End-to-End (E2E) tests (`test-e2e-isolated`).
    -   **BuildKit**: Enabled for efficient Docker builds.
-   **Testing Infrastructure**:
    -   **KVM / libvirt**: Used for full system simulation and destructive testing (`test-e2e-kvm`).
    -   **QEMU**: Underlying emulator for KVM.

## 4. Implementation Patterns & Conventions

### 4.1 Shell Scripting Patterns

#### Strict Mode
All scripts MUST start with strict error handling to fail fast on errors or undefined variables.
```bash
#!/usr/bin/env bash
set -euo pipefail
```

#### Modular Sourcing
Functions are organized into modules in `lib/` and sourced with guards to prevent double-loading.
```bash
# lib/core/logger.sh
if [[ -n "${_LOGGER_SH_LOADED:-}" ]]; then
  return 0
fi
readonly _LOGGER_SH_LOADED=1
```

#### Logging
A centralized `logger` module provides leveled logging with color support and file persistence.
```bash
source "${LIB_DIR}/core/logger.sh"
log_info "Initialization complete"
log_error "Failed to locate config"
```

### 4.2 Python Patterns

#### Type Hinting
All Python code MUST use type hints to ensure clarity and enable static checking with `mypy`.
```python
def check_disk_space(path: str, min_gb: int) -> bool:
    ...
```

#### Project Structure
-   `bin/`: Executable scripts (entry points).
-   `lib/`: Shared libraries and modules.
    -   `lib/core/`: Foundation modules (logging, config).
    -   `lib/modules/`: Feature-specific logic.
    -   `lib/utils/`: Python helper scripts.
-   `tests/`: Test suites (unit, integration, contract, e2e).
-   `config/`: Configuration files and templates.

## 5. Technology Decision Context

### Why Shell?
-   **Rationale**: The primary goal is to provision a Debian VPS. Shell offers the most direct and dependency-free way to interact with system packages (`apt`), services (`systemd`), and files.
-   **Constraint**: Must run on a fresh VPS with minimal initial dependencies.

### Why Python?
-   **Rationale**: Used when Shell becomes too complex or unreadable (e.g., JSON parsing, complex logic).
-   **Constraint**: Limited to standard library or packages easily installable via `pip` in a venv.

### Why KVM & Docker?
-   **Rationale**: Testing provisioning scripts is destructive.
    -   **Docker**: Fast, lightweight checks for file manipulation and package installation logic.
    -   **KVM**: Essential for testing kernel-level changes, systemd services, and full boot sequences that containers cannot simulate.
