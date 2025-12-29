---
trigger: always_on
---

# Technology Stack Rules

## Overview
These rules are derived from `docs/Technology_Stack_Blueprint.md` and define the authoritative technology choices and constraints for the project.

## 1. Core Technologies

### Shell / Bash Stack (Primary)
**Rule**: Use Bash for core logic, orchestration, and system interaction.
- **Version**: Bash 4.x+
- **Strict Mode**: MUST use `set -euo pipefail` at the top of every script.
- **Style**: POSIX compatibility where possible.

### Python Stack (Secondary)
**Rule**: Use Python for complex data processing, validation, and crypto.
- **Version**: Python 3.11+
- **Virtual Env**: Managed via `.venv`.
- **Core Libs**: `psutil`, `secrets`, standard library.

## 2. Build & Task Management
**Rule**: All development workflows MUST be wrapped in `Makefile`.
- **Parallel**: Configured for parallel execution (`PARALLEL_JOBS := 4`).

## 3. Tooling & Ecosystem

### Testing
**Rule**:
- **Shell**: Use **bats-core** (v1.10.0+).
- **Python**: Use **pytest** (>=7.4.0).
- **End-to-End**: Use **Docker** for fast isolation and **KVM** for full system simulation.

### Linting & Static Analysis
**Rule**: Code must pass these checks:
- **Shell**: `shellcheck` (static analysis), `shfmt` (formatting).
- **Python**: `flake8` & `pylint` (linting), `black` (formatting), `mypy` (type checking).

## 4. Implementation Patterns

### Shell Patterns
**Rule**:
- **Modular Sourcing**: Use guard variables to prevent double-loading.
- **Logging**: Use `lib/core/logger.sh`.

### Python Patterns
**Rule**:
- **Type Hinting**: MANDATORY for all Python code.
```python
def func(arg: str) -> bool:
    ...
```

## 5. Decision Context
**Rule**:
- **Use Shell When**: Provisioning, package management, service control, file operations.
- **Use Python When**: JSON parsing, complex string manipulation, floating-point math, crypto.
