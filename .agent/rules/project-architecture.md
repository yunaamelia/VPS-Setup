---
trigger: always_on
---

# Project Architecture Rules

## Overview
These rules are derived from `docs/Project_Architecture_Blueprint.md` and define the architectural standards for the VPS Provisioning Tool.

## 1. Directory Structure Standards
**Rule**: Maintain strict separation of concerns based on directory responsibility.
- `bin/`: CLI entry points only. No business logic.
- `lib/core/`: Framework services (logging, error handling, state). **NO** dependency on modules.
- `lib/modules/`: Business logic (features). Depends on core.
- `lib/utils/`: Standalone Python scripts. Stateless and isolated.

## 2. Dependency Management
**Rule**: Dependencies MUST flow strictly downwards.
- CLI $\to$ Orchestration $\to$ Core $\to$ OS Rules
- **FORBIDDEN**: Core sourcing Modules.
- **FORBIDDEN**: Modules sourcing other Modules (prevents circular dependencies).
- **FORBIDDEN**: Utilities depending on Shell libraries.

## 3. State Management
**Rule**: All state-changing operations MUST use the defined persistence mechanisms.
- **Checkpoints**: Use `checkpoint_create "phase_name"` to mark completion. Check at start of execution.
- **Transactions**: Use `transaction_record "Description" "Rollback Command"` for *every* system change.
- **Persistence**: Store all state in `/var/vps-provision/`.

## 4. Technology Usage
**Rule**: Use the right tool for the layer.
- **Bash (5.1+)**: Control Plane. Orchestration, file ops, package management.
- **Python (3.11+)**: Data Plane. Complex logic, crypto, JSON parsing, validation.
- **Config**: INI-style or sourced Bash variables. NO hardcoded values in code.

## 5. Development Workflow
**Rule**: When adding a new feature, follow the standard lifecycle:
1.  **Create Module**: implementation in `lib/modules/`.
2.  **Define Interface**: `module_execute` function.
3.  **Idempotency**: First line MUST be `if checkpoint_exists ...`.
4.  **Transaction**: Every action MUST have a rollback.
5.  **Registration**: Add to `bin/vps-provision` phase list.

## 6. Security Architecture
**Rule**: Secure by default.
- **Root**: Script blocks execution if EUID != 0.
- **Secrets**: Generated via `secrets` module, never stored in plaintext config.
- **Input**: Validate all user inputs via `lib/core/sanitize.sh`.

## 7. Anti-Patterns (Architecture Violations)
- **Violation**: "Quick fix" sourcing of a sibling module. (Solution: Refactor shared logic to `lib/core`).
- **Violation**: Hardcoded paths (e.g., `/var/log/myapp`). (Solution: Use `${LOG_DIR}`).
- **Violation**: Silent failures. (Solution: Use `transaction_record` and proper error handlers).
