# User Experience Standards

## Overview
These standards ensure a consistent, professional, and accessible command-line experience for the VPS-Setup provisioning tool. All user-facing output must follow these guidelines.

---

## Output Formatting

### Progress Indicators
```bash
# Phase progress with percentage and timing
[Phase 1/10] System Preparation ████████████████ 100% (2m 15s)

# Spinner for indeterminate operations
[⠋] Installing packages...

# Step-level progress
  ✓ Updated package lists
  ✓ Installed dependencies
  → Installing desktop environment...
```

### Status Prefixes
| Prefix | Usage | Color |
|--------|-------|-------|
| `[INFO]` | General information | Blue |
| `[SUCCESS]` | Completed successfully | Green |
| `[WARNING]` | Non-fatal issue | Yellow |
| `[ERROR]` | Fatal error | Red |
| `[DEBUG]` | Debug output (verbose mode) | Gray |

### Message Format
```bash
# Standard format
[LEVEL] Concise message describing action or outcome

# Examples
[INFO] Starting VPS provisioning...
[SUCCESS] Desktop environment installed
[WARNING] Low disk space detected (5GB remaining)
[ERROR] Failed to install package: xfce4-terminal
```

---

## Color Standards

### NO_COLOR Support
All output MUST respect the `NO_COLOR` environment variable:
```bash
if [[ -z "${NO_COLOR:-}" ]] && [[ -t 1 ]]; then
  # Use colors
  COLOR_GREEN='\033[32m'
else
  # No colors
  COLOR_GREEN=''
fi
```

### Color Palette
| Color | ANSI Code | Usage |
|-------|-----------|-------|
| Green | `\033[32m` | Success, completion |
| Yellow | `\033[33m` | Warning, caution |
| Red | `\033[31m` | Error, failure |
| Blue | `\033[34m` | Info, headings |
| Bold | `\033[1m` | Emphasis |
| Reset | `\033[0m` | Clear formatting |

---

## Exit Codes

### Standard Codes
| Code | Meaning | User Action |
|------|---------|-------------|
| 0 | Success | None required |
| 1 | General failure | Check error message |
| 2 | Invalid arguments | See `--help` |
| 3 | Configuration error | Check config file |
| 4 | Missing dependency | Install requirements |
| 5 | Permission denied | Run with appropriate privileges |

### Exit Message Pattern
```bash
# On success
[SUCCESS] Provisioning completed in 13m 42s!

# On failure
[ERROR] Provisioning failed at phase: Desktop Installation
        See /var/log/vps-provision/provision.log for details
        Run with --resume to continue after fixing
```

---

## Help Text

### Required Elements
```bash
Usage: vps-provision [OPTIONS]

One-command transformation of a fresh Debian 13 VPS into a fully-functional
developer workstation with RDP access and three IDEs.

Options:
  -h, --help          Display this help message
  -v, --verbose       Enable verbose output
  -y, --yes           Skip confirmation prompts
  --version           Display version information
  --dry-run           Show what would be done without changes
  --username USER     Set developer username (default: devuser)
  --force             Clear checkpoints and re-provision
  --resume            Continue from last checkpoint

Examples:
  vps-provision                    # Standard provisioning
  vps-provision --username dev     # Custom username
  vps-provision --dry-run          # Preview changes

Report bugs to: https://github.com/your-org/vps-provision/issues
```

---

## Error Messages

### Requirements
1. **Specific**: Describe exactly what failed
2. **Actionable**: Suggest how to fix
3. **Contextual**: Include relevant details

### Error Format
```bash
# ✅ GOOD: Specific and actionable
[ERROR] Failed to install package: xfce4-terminal
        Cause: dpkg returned exit code 100
        Suggestion: Check internet connection and run: apt-get update

# ❌ BAD: Vague and unhelpful
[ERROR] Installation failed
```

---

## Confirmation Prompts

### Interactive Mode
```bash
# Destructive operations require confirmation
WARNING: This will remove all existing configurations.
Continue? [y/N]: 

# Use --yes to skip
vps-provision --yes
```

### Non-Interactive Detection
```bash
if [[ ! -t 0 ]]; then
  # Running non-interactively
  logger_warning "Running in non-interactive mode"
fi
```

---

## Logging Levels

### Configuration
```bash
# LOG_LEVEL environment variable
export LOG_LEVEL=INFO  # Default

# Available levels (increasing verbosity)
ERROR   # Only errors
WARNING # Errors and warnings
INFO    # Standard output (default)
DEBUG   # Verbose debugging
```

### Level Usage
| Level | Output | Example |
|-------|--------|---------|
| ERROR | Critical failures only | `Failed to connect to repository` |
| WARNING | Important notices | `Using fallback mirror` |
| INFO | Phase progress, summaries | `Installing desktop environment` |
| DEBUG | Detailed operations | `Running: apt-get install xfce4` |

---

## Accessibility

### Screen Reader Compatibility
- Use semantic output (clear phrases, not just symbols)
- Provide text alternatives for progress bars
- Avoid rapid output updates that overwhelm assistive tech

### Terminal Width
```bash
# Respect terminal width
if [[ -n "${COLUMNS:-}" ]]; then
  MAX_WIDTH=$((COLUMNS - 2))
else
  MAX_WIDTH=78  # Safe default
fi
```

---

## Review Checklist

- [ ] Uses standard status prefixes
- [ ] Respects NO_COLOR environment
- [ ] Provides actionable error messages
- [ ] Includes --help with examples
- [ ] Uses consistent color palette
- [ ] Tests terminal width handling
- [ ] Confirms destructive operations
