# GitHub Copilot Instructions

## Priority Guidelines

When generating code for this repository:

1.  **Version Compatibility**: Strictly adhere to **Bash 4.x+** (Debian 13 standard) and **Python 3.11+**.
2.  **Context Files**: Prioritize patterns defined in `docs/Technology_Stack_Blueprint.md` and `docs/Code_Exemplars_Blueprint.md`.
3.  **Architectural Consistency**: Maintain the **Modular Hybrid Architecture** (Shell core, Python utilities). Do not introduce ad-hoc scripts outside the established `lib/` structure.
4.  **Code Quality**: Prioritize **maintainability** (strict typing, clear logging) and **reliability** (idempotency, error handling).

## Technology Version Detection

Before generating code, verify context but default to:

1.  **Shell**: Bash 4.x+. Do NOT use `sh` (POSIX) compatible code if Bash features (arrays, local vars) make the code cleaner.
2.  **Python**: Python 3.11+. Use modern features like `match` statements and type hinting.
3.  **OS**: Debian 13 (Bookworm). Assume `apt` is the package manager and `systemd` is the init system.

## Codebase Scanning Instructions

When context files don't provide specific guidance:

1.  **Identify Shell Patterns**:
    -   Look for `lib/core/` usage for logging and config.
    -   Check for `local` variable declarations.
    -   Observe the `transaction_record` pattern for rollback.

2.  **Identify Python Patterns**:
    -   Look for class-based structures in `lib/utils/`.
    -   Check for `argparse` usage in `main()` functions.

## Code Quality Standards

### Maintainability
-   **Strict Mode**: ALL shell scripts MUST start with `set -euo pipefail`.
-   **Guards**: ALL shared shell libraries MUST use include guards (`if [[ -n "${_LIB_NAME_LOADED:-}" ]]; then return 0; fi`).
-   **Typing**: ALL Python functions MUST have type hints (`def func(arg: int) -> str:`).
-   **Headers**: All scripts must have a shebang and brief description header.

### Security
-   **Credentials**: NEVER use `random` for secrets; use Python's `secrets` module.
-   **Redaction**: Use `log_redact` or `log_redacted` when logging potentially sensitive inputs.
-   **Privileges**: Do not use `sudo` inside scripts unless absolutely necessary; prefer running the script with appropriate privileges.

### Reliability (Idempotency)
-   **Checkpoints**: ALL long-running/state-changing operations MUST use the `checkpoint_exists` / `checkpoint_create` pattern.
-   **Transactions**: ALL destructive operations MUST record a rollback command via `transaction_record`.

## Documentation Requirements

-   **Shell**: Use Javadoc-style comments for functions:
    ```bash
    # @description Installs a package
    # @arg $1 package_name Name of package
    # @return 0 on success, 1 on failure
    function install_pkg() { ... }
    ```
-   **Python**: Use Google-style docstrings.

## Testing Approach

### Unit Testing (Shell)
-   Use `bats-core`.
-   Mock commands using `mock_command` helper.
-   Isolate tests using `setup()` and `teardown()`.
-   Example: `tests/unit/test_logger.bats`.

### Integration Testing (Python)
-   Use `pytest`.
-   Use fixtures for setup.
-   Example: `tests/unit/test_health_check.py`.

## Technology-Specific Guidelines

### Shell (Bash) Guidelines
-   **Variables**: Use `readonly` for constants (UPPER_CASE). Use `local` for function variables (snake_case).
-   **Output**: NEVER use `echo` for status; use `log_info`, `log_error`, etc.
-   **Navigation**: NEVER use `cd` without a subshell `(cd ...)` or `pushd/popd`.
-   **Arrays**: Prefer Bash arrays over string splitting.

### Python Guidelines
-   **Imports**: Standard library first, then 3rd party, then local modules.
-   **Linting**: Code must pass `black` formatting and `mypy` strict type checking.
-   **Entry Points**: Use the `if __name__ == "__main__":` idiom.

## Folder Structure Context
-   `bin/`: Executable entry points (no logic, just wiring).
-   `lib/core/`: Foundation (logging, config, checks).
-   `lib/modules/`: Feature logic (desktop, rdp).
-   `lib/utils/`: Python helpers.
-   `docs/`: Documentation.

## Project-Specific Guidance

-   **Hybrid Nature**: If a task involves complex string parsing, JSON handling, or floating-point math, **suggest a Python utility** in `lib/utils/` instead of complex AWK/Sed chains.
-   **Virtualization**: Recall that tests may run in Docker or KVM; respect the `test-e2e-isolated` patterns.
