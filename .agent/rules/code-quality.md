# Shell Script Code Quality Standards

## Overview
These standards ensure consistent, maintainable, and reliable shell scripts across the VPS-Setup project. All contributions must adhere to these guidelines.

---

## Core Principles

### 1. POSIX Compatibility
- Prefer POSIX-compliant constructs when possible
- Use Bash-specific features intentionally (document when required)
- Shebang: `#!/usr/bin/env bash` for portability

### 2. Strict Mode
All scripts MUST enable strict error handling:
```bash
set -euo pipefail
```
- `-e`: Exit on error
- `-u`: Exit on undefined variable
- `-o pipefail`: Fail on pipe errors

---

## Function Standards

### Size and Complexity
| Metric | Limit | Enforcement |
|--------|-------|-------------|
| Function lines | ≤50 LOC | Code review |
| Cyclomatic complexity | ≤10 | ShellCheck analysis |
| Nesting depth | ≤3 levels | Code review |
| Parameters | ≤5 | Refactor to config if exceeded |

### Naming Conventions
```bash
# Functions: snake_case with module prefix
validator_check_prerequisites()
logger_info()
rollback_cleanup()

# Local variables: lowercase snake_case
local temp_dir=""
local exit_code=0

# Global/exported: UPPERCASE_SNAKE_CASE
export PROJECT_ROOT=""
export LOG_LEVEL="INFO"
```

### Documentation
```bash
# Required for all public functions:
# @description Brief description of function purpose
# @param $1 Parameter description
# @return Exit code meaning
# @example Usage example
function module_function_name() {
  local param1="$1"
  # implementation
}
```

---

## Error Handling

### Required Patterns
```bash
# Always check command success
if ! command -v required_tool &>/dev/null; then
  logger_error "Required tool not found: required_tool"
  return 1
fi

# Use trap for cleanup
trap 'cleanup_on_exit' EXIT
trap 'cleanup_on_error' ERR

# Validate inputs early (fail-fast)
[[ -z "${required_param:-}" ]] && {
  logger_error "Missing required parameter"
  return 1
}
```

### Exit Codes
| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | General error |
| 2 | Invalid usage/arguments |
| 3 | Configuration error |
| 4 | Dependency missing |
| 5 | Permission denied |
| 10+ | Module-specific errors |

---

## Static Analysis

### ShellCheck Enforcement
- **CI Requirement**: All scripts must pass `shellcheck` with zero warnings
- **Minimum Version**: ShellCheck 0.8.0+
- **Severity**: error, warning, info (all enforced)

### Allowed Suppressions
Suppress only with justification comment:
```bash
# shellcheck disable=SC2034  # Variable used by sourcing script
EXPORTED_VAR="value"
```

### Formatting (shfmt)
- Indent: 2 spaces
- Binary ops: Split after operator
- Switch case indent: 2 spaces
- Run: `shfmt -w -i 2 -ci script.sh`

---

## Module Organization

### File Structure
```
lib/
├── core/           # Infrastructure modules (logger, config, validator)
├── modules/        # Feature modules (desktop, rdp, ide)
├── models/         # Data structures and schemas
└── utils/          # Utility scripts (Python helpers)
```

### Source Dependencies
```bash
# At top of script, source required modules
# shellcheck source=lib/core/logger.sh
source "${PROJECT_ROOT}/lib/core/logger.sh"
```

---

## Prohibited Patterns

| Anti-Pattern | Alternative |
|--------------|-------------|
| `eval "$user_input"` | Use arrays, `printf %q` |
| `cd` without subshell | `(cd dir && command)` or `pushd/popd` |
| Unquoted variables | Always quote: `"${var}"` |
| `[ condition ]` | Use `[[ condition ]]` for Bash |
| Parsing `ls` output | Use globs or `find` |
| `cat file \| cmd` | Use `cmd < file` |

---

## Review Checklist

- [ ] Strict mode enabled (`set -euo pipefail`)
- [ ] All functions documented
- [ ] Variables quoted properly
- [ ] Error handling present
- [ ] ShellCheck passes
- [ ] Module prefix used for functions
- [ ] No prohibited patterns
