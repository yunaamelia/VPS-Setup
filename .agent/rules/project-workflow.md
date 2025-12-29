---
trigger: always_on
---

# Project Workflow Rules

## Overview
These rules are derived from `docs/Project_Workflow_Analysis_Blueprint.md` and define the standard workflows for development, testing, and execution.

## 1. Feature Development Workflow
**Rule**: All new features MUST follow this 7-step process:
1.  **Branch**: Create `feature/name` from `main`.
2.  **Spec**: Create spec in `specs/` and generate plan via `make spec-plan`.
3.  **Implement**: Write code in `lib/modules/` following the Module Template.
4.  **Test**: Write BATS tests in `tests/unit/` and `tests/integration/`.
5.  **Lint**: Run `make lint` and `make format`.
6.  **Commit**: Use conventional commits referencing issue IDs.
7.  **PR**: Submit with test results.

## 2. Module Execution Pattern
**Rule**: Every provisioning module MUST implement this flow:
1.  **Idempotency Check**: Return immediately if checkpoint exists.
2.  **Checkpoint Start**: Mark start of phase.
3.  **Prerequisites**: Validate preconditions.
4.  **Execution**: Perform tasks with **Transaction Recording**.
5.  **Verify**: Validate success.
6.  **Checkpoint Create**: Mark completion.

## 3. Error Handling & Rollback
**Rule**: Automatic Rollback is MANDATORY.
- **Trap**: All scripts must trap `ERR`.
- **Transactions**: Every state change must record a rollback command.
- **Recovery**: On error, the system must unwind changes LIFO.

## 4. Validation Workflow
**Rule**: Success is defined by `lib/utils/health-check.py`.
- All modules must pass their specific health checks.
- `verification_execute` is the final gate for provisioning success.

## 5. Naming Conventions
**Rule**:
- **Module Functions**: `module_name_verb` (e.g., `system_prep_execute`).
- **Core Functions**: `domain_verb` (e.g., `logger_info`, `checkpoint_create`).
- **Private Functions**: `_function_name`.
