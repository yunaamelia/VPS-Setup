# Testing Standards

## Overview
This project uses the BATS (Bash Automated Testing System) framework for testing shell scripts. All tests must follow these standards to ensure consistency, reliability, and maintainability.

---

## Test Organization

### Directory Structure
```
tests/
├── unit/                  # Isolated function tests (fast, no side effects)
├── integration/           # Module interaction tests
├── contract/              # API/interface contract tests
├── e2e/                   # Full provisioning workflow tests
└── test_helper.bash       # Shared test utilities
```

### Test Pyramid
| Level | Coverage Target | Execution Time | Purpose |
|-------|-----------------|----------------|---------|
| Unit | ≥80% functions | <30s total | Verify individual functions |
| Integration | Critical paths | <2min total | Verify module interactions |
| Contract | All public APIs | <1min total | Verify interface contracts |
| E2E | Happy path | <15min | Full provisioning validation |

---

## Test File Conventions

### Naming
```bash
# Test files: <module>_<aspect>.bats
logger_output.bats
validator_prerequisites.bats
rollback_cleanup.bats

# Test functions: descriptive, starts with @test
@test "logger_info outputs message with INFO prefix"
@test "validator returns error when disk space insufficient"
```

### Structure
```bash
#!/usr/bin/env bats
# Test file description

load '../test_helper'

setup() {
  common_setup
  # Test-specific setup
}

teardown() {
  common_teardown
  # Test-specific cleanup
}

@test "function_name: expected behavior when condition" {
  # Arrange
  local input="test_value"
  
  # Act
  run function_under_test "$input"
  
  # Assert
  assert_success
  assert_output --partial "expected"
}
```

---

## Coverage Requirements

### Mandatory Coverage
- [ ] All public functions in `lib/core/`
- [ ] All error handling paths
- [ ] All exit code scenarios
- [ ] Edge cases (empty input, special characters)
- [ ] Boundary conditions

### Coverage Enforcement
```bash
# Run coverage report
make test-coverage

# Minimum thresholds (CI enforced)
# Unit tests: 80% function coverage
# Critical paths: 100% coverage
```

---

## Assertion Patterns

### Use Specific Assertions
```bash
# ✅ GOOD: Specific assertions
assert_success
assert_failure 2
assert_output "Expected exact output"
assert_output --partial "substring"
assert_line --index 0 "First line"

# ❌ BAD: Generic assertions
[ "$status" -eq 0 ]
[[ "$output" == *"substring"* ]]
```

### Common Assertions
| Assertion | Purpose |
|-----------|---------|
| `assert_success` | Exit code 0 |
| `assert_failure [N]` | Non-zero exit code |
| `assert_output TEXT` | Exact output match |
| `assert_output --partial TEXT` | Substring match |
| `assert_line [--index N] TEXT` | Line content match |
| `refute_output --partial TEXT` | Must NOT contain |

---

## Mocking and Stubs

### Using test_helper.bash
```bash
# Mock a command
mock_command "apt-get" "Package installed" 0

# Create mock file
create_mock_file "/etc/test.conf" "key=value"
```

### Mock External Dependencies
```bash
@test "handles missing dependency gracefully" {
  # Arrange: mock command to fail
  mock_command "systemctl" "" 1
  
  # Act
  run check_service_status
  
  # Assert
  assert_failure
  assert_output --partial "Service not available"
}
```

---

## Test Independence

### Requirements
- Tests MUST NOT depend on execution order
- Tests MUST NOT share mutable state
- Tests MUST clean up all resources in teardown
- Tests MUST work in isolation and in batch

### Isolation Pattern
```bash
setup() {
  common_setup
  export TEST_TEMP_DIR
  export ISOLATED_CONFIG="${TEST_TEMP_DIR}/config"
}

teardown() {
  common_teardown  # Cleans TEST_TEMP_DIR
}
```

---

## CI Integration

### Pre-commit Hook
- Runs unit tests (<30s)
- Blocks commit on failure

### Pre-push Hook
- Runs unit + integration tests
- Blocks push on failure

### CI Pipeline
```yaml
test:
  stage: test
  script:
    - make test-unit
    - make test-integration
    - make test-contract
```

---

## Test Documentation

### When to Document
- Non-obvious test rationale
- Complex setup requirements
- Known limitations
- Workarounds for Bats quirks

### Example
```bash
# Tests the rollback mechanism when desktop installation fails.
# This test mocks apt-get to simulate package installation failure
# and verifies that cleanup is called with correct arguments.
# Note: Requires mocked systemctl due to container limitations.
@test "rollback: cleans up partial installation on failure" {
  # ...
}
```

---

## Review Checklist

- [ ] Follows Arrange-Act-Assert pattern
- [ ] Uses specific assertions (not generic `[ ]`)
- [ ] Includes setup/teardown
- [ ] Has descriptive test name
- [ ] Cleans up resources
- [ ] Independent of other tests
- [ ] Covers edge cases
- [ ] Mocks external dependencies
