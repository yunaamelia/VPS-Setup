# Project Folder Structure Blueprint

## 1. Structural Overview

This project follows a **Modular Shell/Python Hybrid Architecture** designed for robust VPS provisioning and management. It separates core infrastructure logic, feature modules, data models, and utilities into distinct directories, promoting maintainability and testability.

### Organizational Principles
-   **Layered Architecture**: `core` (infrastructure), `modules` (features), `bin` (execution).
-   **Separation of Concerns**: Logic is separated from configuration and data definitions.
-   **Polyglot Utility**: Shell is used for system-level operations, while Python is used for complex data processing and monitoring.
-   **Test-Driven**: A dedicated `tests` directory mirrors the structure for comprehensive validation.

### Monorepo Structure
This is a single repository focused on one primary deliverable (`vps-provision`), but organized with distinct internal components that could theoretically be decoupled.

## 2. Directory Visualization

```
vpsnew/
├── .agent/                 # Agent configuration and workflows
├── .github/                # GitHub workflows, prompts, and templates
├── bin/                    # Executable entry points
├── config/                 # Configuration files
├── docs/                   # Project documentation
├── lib/                    # Core libraries and modules
│   ├── core/               # Infrastructure logic (logging, error handling)
│   ├── models/             # Data schemas (JSON schemas)
│   ├── modules/            # Feature implementation (desktop, RDP, IDEs)
│   └── utils/              # Helper scripts (Python/Shell)
├── logs/                   # Runtime logs (gitignored)
├── specs/                  # Specification documents
└── tests/                  # Test suites (BATS, PyTest)
```

## 3. Key Directory Analysis

### Shell/Python Hybrid Structure

#### `bin/` (Executables)
Contains the primary entry points for the application.
-   `vps-provision`: Main provisioning script.
-   `preflight-check`: Initial system validation.
-   `release.sh`: Release management script.

#### `lib/core/` (Infrastructure)
Foundational shell scripts that provide lower-level services.
-   `logger.sh`: Logging infrastructure.
-   `error-handler.sh`: Robust error management.
-   `checkpoint.sh`: State saving/resuming logic.
-   `validator.sh`: Input and state validation.

#### `lib/modules/` (Features)
Business logic for specific provisioning tasks.
-   `desktop-env.sh`: Desktop environment setup.
-   `rdp-server.sh`: Remote access configuration.
-   `ide-*.sh`: IDE installation scripts.

#### `lib/utils/` (Utilities)
Helper scripts, primarily Python, for complex operations.
-   `package-manager.py`: Advanced package handling.
-   `health-check.py`: System health monitoring.
-   `benchmark.sh`: Performance testing tools.

#### `lib/models/` (Data Schemas)
JSON schemas defining data structures.
-   `provisioning-session.schema.json`: Session state definition.

#### `config/` (Configuration)
Contains configuration files for the application.

#### `tests/` (Testing)
Test suites for the application.
-   `unit/`: Unit tests for individual functions.
-   `integration/`: Integration tests for modules.

## 4. File Placement Patterns

-   **Executables**: Must go in `bin/` and have executable permissions.
-   **Core Logic**: Low-level, reusable shell functions go in `lib/core/`.
-   **Feature Logic**: High-level feature implementations go in `lib/modules/`.
-   **Complex Logic**: Operations requiring complex data structures or parsing should be Python scripts in `lib/utils/`.
-   **Schemas**: JSON schemas go in `lib/models/`.
-   **Documentation**: Markdown files go in `docs/`.

## 5. Naming and Organization Conventions

### File Naming
-   **Shell Scripts**: `kebab-case.sh`.
-   **Python Scripts**: `kebab-case.py`.
-   **JSON Schemas**: `kebab-case.schema.json`.
-   **Documentation**: `Pascal_Snake_Case.md` (e.g., `Project_Folder_Structure_Blueprint.md`) or `SCREAMING_SNAKE_CASE.md` (e.g., `README.md`, `CONTRIBUTING.md`).

### Folder Naming
-   **General**: `kebab-case`.
-   **Documentation**: `docs` (lowercase).

### Organizational Patterns
-   **Module Prefixing**: Functions within `lib/modules/desktop-env.sh` should generally be prefixed (e.g., `desktop_env_install`).
-   **Self-Contained Modules**: Modules should depend on `core` but avoid circular dependencies with other `modules`.

## 6. Navigation and Development Workflow

### Entry Points
-   Start at `bin/vps-provision` to understand the main execution flow.
-   Check `lib/core/state.sh` to understand how persistent state is managed.

### Common Development Tasks
-   **Adding a Feature**: Create a new script in `lib/modules/`, register it in `bin/vps-provision`.
-   **Adding a Check**: Add validation logic to `lib/core/validator.sh`.
-   **Adding a schema**: Create a new `.schema.json` in `lib/models/`.

## 7. Build and Output Organization

### Build
-   `Makefile`: Primary entry point for build, test, and maintenance tasks.

### Output
-   `logs/`: Runtime logs are written here.
-   `.cache/`: Temporary cache files.

## 8. Technology-Specific Organization

### Shell (Bash)
-   **Strict Mode**: Scripts should verify `set -euo pipefail`.
-   **Sourcing**: Libraries are sourced relative to the project root or script location.
-   **ShellCheck**: All scripts must pass ShellCheck.

### Python
-   **Virtual Environment**: Managed in `.venv`.
-   **Type Hinting**: Enforced via MyPy.
-   **Linting**: Enforced via Pylint/Flake8.

## 9. Extension and Evolution

### Extension Points
-   **New Modules**: Add new `.sh` files to `lib/modules/`.
-   **New Utilities**: Add python scripts to `lib/utils/`.

### Scalability
-   The modular design allows adding many features without cluttering the main logic.
-   Python utilities can replace complex shell logic as complexity grows.

### Maintainable
-   Checkpoints allow specific modules to be re-run or skipped.

## 10. Structure Templates

### New Feature Module Template (`lib/modules/new-feature.sh`)
```bash
#!/usr/bin/env bash
# @description Module for [Feature Name]
# @author [Author Name]

# shellcheck source=lib/core/logger.sh
source "${PROJECT_ROOT}/lib/core/logger.sh"

# @description Application entry point for the module
function new_feature_main() {
    logger_info "Starting [Feature Name]..."
    # Implementation
}
```

### New Python Utility Template (`lib/utils/new-util.py`)
```python
#!/usr/bin/env python3
"""
[Utility Name] - [Description]
"""

import sys
import logging

def main():
    """Main entry point."""
    logging.basicConfig(level=logging.INFO)
    logging.info("Starting utility...")

if __name__ == "__main__":
    main()
```

## 11. Structure Enforcement

-   **Linting**: `make lint` checks for structure and code quality.
-   **Tests**: `make test` ensures structural integrity via test execution.
-   **CI/CD**: GitHub Actions enforce these checks on Pull Requests.

---
*Blueprint automatically generated by Antigravity Agent. Last Updated: 2025-12-29.*
