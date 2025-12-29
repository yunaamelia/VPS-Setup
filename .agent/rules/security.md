---
trigger: always_on
---

# Security Standards

## Overview
These rules define the security requirements and best practices for the VPS provisioning tool.

## 1. Authentication & Authorization
**Rule**: Generate cryptographically secure passwords.
- Use `secrets` module in Python for all generation.
- Minimum length: 16 characters.
- SSH: Key-only authentication MANDATORY. Disable `PasswordAuthentication` in `sshd_config`.
- Root: Disable `PermitRootLogin` after dev user creation.

## 2. Network Security
**Rule**: Implement restrictive firewall and rate limiting.
- **Firewall**: UFW enabled by default. Default deny incoming, allow outgoing. Specifically allow ports 22 (SSH) and 3389 (RDP).
- **Rate Limiting**: `fail2ban` MUST be configured for both SSH and RDP.

## 3. Data Protection
**Rule**: Protect sensitive information in transit and at rest.
- **Log Redaction**: All logs MUST redact passwords, tokens, and API keys using [REDACTED] markers.
- **Encryption**: TLS 1.2+ mandatory for RDP (`security_layer=tls`). Use modern ciphers for SSH.
- **Permissions**: Sensitive files must have restrictive permissions (e.g., 600 for SSH keys, 640 for logs).

## 4. Secure Coding Practices
**Rule**: Validate all external inputs and fail securely.
- **Sanitization**: All user-provided arguments (usernames, paths, IPs) MUST be sanitized via `lib/core/sanitize.sh`.
- **Fail Securely**: Scripts MUST use `set -euo pipefail`. Critical failures must trigger rollback.
- **No Info Disclosure**: Do not leak system paths or credentials in error messages.

## 5. Audit Logging
**Rule**: Maintain a tamper-evident audit trail.
- Every state change MUST be recorded in the transaction log (`/var/log/vps-provision/transactions.log`).
- Enable `auditd` for monitoring critical system files and user modifications.
