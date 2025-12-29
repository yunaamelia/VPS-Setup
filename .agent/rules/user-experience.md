---
trigger: always_on
---

# User Experience Standards

## Overview
These rules define the interaction patterns, error handling, and visual feedback for the CLI.

## 1. Error Message Formatting
**Rule**: All errors MUST follow the standardized format.
- Format: `[SEVERITY] <Concise Message> \n  > Suggested Action`
- **Severities**:
    - **FATAL**: Critical/Non-retryable (abort).
    - **ERROR**: Retryable/Recoverable.
    - **WARNING**: Informational/Non-fatal.

## 2. Interactive Feedback
**Rule**: Provide clear progress and confirmation.
- **Progress Bars**: Use weighted progress bars with percentage and phase labels.
- **Confirmations**: Destructive operations (like `--force`) MUST require explicit user confirmation unless `--yes` is provided.
- **Non-Interactive Detection**: Automatically detect CI/CD environments and default to requiring `--yes`.

## 3. Success Feedback
**Rule**: Final output MUST provide actionable next steps.
- Display a "PROVISIONING SUCCESSFUL" banner.
- Provide a summary of connection details (IP, Port, Username, Redacted Password).
- List installed IDEs and next steps for the user.

## 4. Input Validation
**Rule**: Validate all inputs early with specific feedback.
- **Username**: Must follow regex `^[a-z][a-z0-9_-]{2,31}$`.
- **Password**: Minimum 16 chars, mix of case/digit/symbol.
- **IP/Ports**: Must be within valid ranges (0-255 octets, 1-65535 ports).

## 5. Accessibility & Plain Mode
**Rule**: Support non-color terminals.
- Respect `--plain` or `--no-color` flags.
- Avoid relying solely on color to convey meaning.
