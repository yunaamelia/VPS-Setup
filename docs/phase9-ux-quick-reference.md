# Phase 9 UX Enhancement Quick Reference

## Error Message Format (UX-007)

All errors now follow standardized format:

```
[SEVERITY] <Concise Message>
 > Suggested Action
```

### Severity Levels (UX-011)

- **FATAL**: Critical errors requiring immediate abort (disk full, permission denied)
- **ERROR**: Retryable errors (network timeout, lock contention)
- **WARNING**: Non-critical informational issues

### Example

```bash
[FATAL] Insufficient disk space (25GB required, 10GB available)
 > Free up disk space by removing unnecessary files or expanding storage.
```

## Actionable Error Suggestions (UX-008)

Every error type includes context-specific guidance:

| Error Type    | Suggestion                                                             |
| ------------- | ---------------------------------------------------------------------- |
| E_NETWORK     | Check internet connection and DNS resolution. Verify firewall rules.   |
| E_DISK        | Free up disk space by removing unnecessary files or expanding storage. |
| E_LOCK        | Wait a moment and retry. Another package manager may be running.       |
| E_PKG_CORRUPT | Clear package cache with 'apt-get clean' and retry installation.       |
| E_PERMISSION  | Ensure script is running with root/sudo privileges.                    |
| E_NOT_FOUND   | Install missing dependency or check command spelling.                  |
| E_TIMEOUT     | Increase timeout or check system load and network stability.           |

## Confirmation Prompts (UX-009)

Destructive operations now require explicit confirmation:

### Interactive Mode

```bash
$ vps-provision --force
WARNING: This may overwrite existing configurations and reinstall packages.
Force mode will clear all checkpoints and re-provision from scratch. Continue? [y/N]: _
```

### Bypass Prompts

```bash
# Use --yes flag for automation/CI-CD
$ vps-provision --force --yes
```

### Non-Interactive Detection

The CLI automatically detects non-interactive shells (CI/CD) and requires `--yes` flag.

## Success Banner (UX-010)

Upon successful provisioning, displays formatted connection details:

```
╔═══════════════════════════════════════════════════════════════════════════╗
║                          PROVISIONING SUCCESSFUL                          ║
╚═══════════════════════════════════════════════════════════════════════════╝

CONNECTION DETAILS (copy-paste ready):
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  RDP Connection:
    Host:     192.168.1.100
    Port:     3389
    Username: devuser
    Password: [REDACTED]  # Security: password hidden in logs

  ⚠️  IMPORTANT: Change your password on first login!

  Connection String (for RDP clients):
    devuser@192.168.1.100:3389

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

INSTALLED IDEs:
  • Visual Studio Code
  • Cursor
  • Antigravity

NEXT STEPS:
  1. Connect via RDP using the credentials above
  2. Change your password when prompted
  3. Launch any IDE from the Applications menu
  4. Start coding!

For support, see: /usr/share/doc/vps-provision/README.md
```

## Input Validation (UX-012)

All user inputs validated with specific feedback:

### Username Validation

```bash
$ vps-provision --username "BadUser"
[ERROR] Invalid username: BadUser
 > Must start with lowercase letter, contain only lowercase letters, numbers, underscore, hyphen (3-32 characters)

# Valid examples: devuser, alice, bob-dev, test_user123
```

### Password Complexity

```bash
$ validate_password "short"
[ERROR] Password too short: 5 characters
 > Password must be at least 16 characters long

# Requirements:
# - Minimum 16 characters
# - At least one uppercase letter (A-Z)
# - At least one lowercase letter (a-z)
# - At least one digit (0-9)
# - At least one special character (!@#$%^&*)
```

### IP Address Validation

```bash
$ validate_ip_address "192.168.1.300"
[ERROR] Invalid IP address octet: 300
 > Each octet must be between 0 and 255

# Valid example: 192.168.1.100
```

### Port Validation

```bash
$ validate_port "70000"
[ERROR] Port number out of range: 70000
 > Port must be between 1 and 65535

# Valid examples: 22, 3389, 8080
```

## New CLI Flags

### --yes, -y

Skip confirmation prompts (useful for automation):

```bash
vps-provision --force --yes
```

### --plain, --no-color

Disable colored output for better accessibility:

```bash
vps-provision --plain
```

## Developer Usage

### Using Error Formatting in Modules

```bash
source "${LIB_DIR}/core/error-handler.sh"

# Classify and format errors automatically
local error_type=$(error_classify "$exit_code" "$stderr" "$stdout")
local severity=$(error_get_severity "$error_type")
local suggestion=$(error_get_suggestion "$error_type")
local formatted=$(error_format_message "$severity" "Operation failed" "$suggestion")
```

### Adding Confirmation Prompts

```bash
source "${LIB_DIR}/core/ux.sh"

if confirm_action "Delete all data?" "This action cannot be undone"; then
  # User confirmed, proceed
  rm -rf /data/*
else
  # User declined
  log_info "Operation cancelled by user"
fi
```

### Validating User Input

```bash
source "${LIB_DIR}/core/ux.sh"

if ! validate_username "$username"; then
  # Validation failed, specific error already logged
  exit 1
fi

if ! validate_password "$password"; then
  # Validation failed with detailed feedback
  exit 1
fi
```

### Displaying Success Banner

```bash
source "${LIB_DIR}/core/ux.sh"

show_success_banner "$ip_address" "$rdp_port" "$username" "$password"
```

## Testing

Run Phase 9 integration tests:

```bash
cd /home/raccoon/vpsnew
bats tests/integration/test_ux_error_handling.bats
```

Expected output:

```
39 tests, 0 failures
✓ All T109-T114 tasks verified
```

## Compliance Matrix

| Requirement                       | Implementation           | Status |
| --------------------------------- | ------------------------ | ------ |
| UX-007: Standardized error format | error_format_message()   | ✅     |
| UX-008: Actionable suggestions    | ERROR_SUGGESTIONS map    | ✅     |
| UX-009: Confirmation prompts      | confirm_action(), --yes  | ✅     |
| UX-010: Success banner            | show_success_banner()    | ✅     |
| UX-011: Severity classification   | FATAL/ERROR/WARNING      | ✅     |
| UX-012: Input validation          | validate\_\*() functions | ✅     |
| UX-015: Standard shortcuts        | -y, -v, -h flags         | ✅     |
| UX-017: Non-interactive detection | ux_detect_interactive()  | ✅     |
| UX-019: Plain mode                | --plain alias            | ✅     |
| UX-024: Redact sensitive info     | [REDACTED] markers       | ✅     |

## Files Reference

- **Core UX Module**: `lib/core/ux.sh` (349 lines)
- **Error Handler**: `lib/core/error-handler.sh` (enhanced)
- **Logger**: `lib/core/logger.sh` (log_fatal added)
- **CLI Entry Point**: `bin/vps-provision` (integrated UX features)
- **Tests**: `tests/integration/test_ux_error_handling.bats` (39 tests)
- **Summary**: `specs/001-vps-dev-provision/phase9-error-handling-summary.md`

## Tips & Best Practices

1. **Always use error formatting**: Call `error_format_message()` for consistent error reporting
2. **Confirm destructive ops**: Use `confirm_action()` before data deletion or reinstallation
3. **Validate early**: Call validation functions at input boundaries to fail fast
4. **Provide context**: Include specific details in error messages (file paths, values, etc.)
5. **Test non-interactive**: Always test with `--yes` flag for CI/CD compatibility
6. **Use severity correctly**: FATAL = abort now, ERROR = retry possible, WARNING = FYI only

## Support

For questions or issues with Phase 9 UX enhancements:

1. Review implementation summary: `specs/001-vps-dev-provision/phase9-error-handling-summary.md`
2. Check test cases: `tests/integration/test_ux_error_handling.bats`
3. Examine source code: `lib/core/ux.sh`, `lib/core/error-handler.sh`
