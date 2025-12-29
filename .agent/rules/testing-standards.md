---
trigger: always_on
---

# Testing Standards

## Overview
These rules define the testing pyramid and isolation requirements for the project.

## 1. Testing Pyramid
**Rule**: Maintain high coverage across a diverse testing suite.
- **Unit Tests**: Isolated function tests. Target ≥ 80% coverage.
- **Integration Tests**: Verify module interactions.
- **Contract Tests**: Validate CLI interface signatures.
- **E2E Tests**: Comprehensive happy-path provisioning.

## 2. Environment Isolation
**Rule**: E2E tests MUST run in isolated environments to protect host stability.
- **Docker Isolation**: Mirror Debian 13 specifications. Use for fast filesystem and package logic checks.
- **KVM Isolation**: Required for kernel-level, systemd, and full boot sequence testing.
- **ReadOnly Source**: The project source MUST be mounted read-only in test containers.

## 3. Test Lifecycle & Cleanup
**Rule**: Ensure clean state before and after tests.
- **Setup**: Start systemd in containers for service testing.
- **Cleanup**: Containers MUST be destroyed automatically on completion, even if tests fail.
- **Persistence**: Use `--keep-container` ONLY for manual debugging.

## 4. Automation & CI/CD
**Rule**: Integrate tests into the development workflow.
- Every PR MUST pass the full test suite via `make test`.
- Use `Makefile` as the single source for test execution (`test-unit`, `test-e2e-isolated`, etc.).

## 5. Tooling
**Rule**:
- **Shell**: Use **bats-core** (v1.10.0+).
- **Python**: Use **pytest** (>=7.4.0) with **pytest-cov**.
