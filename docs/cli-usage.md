# VPS Provision Command-Line Interface Documentation

## Overview

The `vps-provision` command-line tool automates the complete provisioning of a fresh Digital Ocean Debian 13 VPS into a fully-functional developer workstation. This document provides comprehensive guidance on using all CLI features.

## Quick Start

For most users, simply run:

```bash
sudo vps-provision
```

The tool will guide you through the provisioning process with clear status updates and progress indicators. Total time: approximately 15 minutes on a 4GB RAM / 2 vCPU droplet.

## Basic Usage

```bash
vps-provision [OPTIONS]
```

Run with `--help` flag for full usage information:

```bash
vps-provision --help
```

## Common Scenarios

### 1. First-Time Provisioning

```bash
# Run with all defaults
sudo vps-provision

# Preview what will be done without making changes
sudo vps-provision --dry-run

# Use custom username
sudo vps-provision --username alice
```

### 2. Recovery and Resume

```bash
# Resume from last checkpoint after a failure
sudo vps-provision --resume

# Force complete re-provisioning (ignore checkpoints)
sudo vps-provision --force
```

### 3. Selective Installation

```bash
# Install only specific phases
sudo vps-provision --only-phase ide-vscode --only-phase ide-cursor

# Skip specific phases
sudo vps-provision --skip-phase ide-antigravity --skip-phase terminal-setup
```

### 4. Troubleshooting and Debugging

```bash
# Enable debug logging
sudo vps-provision --log-level DEBUG

# Dry run with debug logging
sudo vps-provision --dry-run --log-level DEBUG

# View detailed logs after provisioning
sudo tail -f /var/log/vps-provision/provision.log
```

### 5. Automation and CI/CD

```bash
# Non-interactive mode (skip all prompts)
sudo vps-provision --yes

# JSON output for parsing
sudo vps-provision --yes --output-format json > result.json

# Plain text output (no colors) for log files
sudo vps-provision --yes --no-color
```

## Command-Line Options

### General Options

| Option      | Short | Description                             |
| ----------- | ----- | --------------------------------------- |
| `--help`    | `-h`  | Display help message and exit           |
| `--version` | `-v`  | Display version information and exit    |
| `--yes`     | `-y`  | Skip confirmation prompts (auto-accept) |

### Execution Mode Options

| Option              | Description                                         |
| ------------------- | --------------------------------------------------- |
| `--dry-run`         | Preview planned actions without executing them      |
| `--skip-validation` | Skip pre-flight system validation (not recommended) |
| `--resume`          | Resume from last checkpoint after failure           |
| `--force`           | Force re-provisioning (clear all checkpoints)       |

### Configuration Options

| Option            | Short | Argument | Description                                                        |
| ----------------- | ----- | -------- | ------------------------------------------------------------------ |
| `--config`        | `-c`  | `PATH`   | Path to custom configuration file                                  |
| `--username`      |       | `NAME`   | Custom username for developer account (default: devuser)           |
| `--log-level`     |       | `LEVEL`  | Set logging verbosity: DEBUG, INFO, WARNING, ERROR (default: INFO) |
| `--output-format` |       | `FORMAT` | Output format: text, json (default: text)                          |

### Display Options

| Option                   | Description                     |
| ------------------------ | ------------------------------- |
| `--no-color` / `--plain` | Disable colored terminal output |

### Phase Control Options

| Option         | Argument | Description                                                 |
| -------------- | -------- | ----------------------------------------------------------- |
| `--skip-phase` | `PHASE`  | Skip specific phase(s), can be specified multiple times     |
| `--only-phase` | `PHASE`  | Run only specific phase(s), can be specified multiple times |

**Note**: `--skip-phase` and `--only-phase` cannot be used together.

## Valid Phases

The following phases can be used with `--skip-phase` or `--only-phase`:

| Phase             | Description                                   | Typical Duration |
| ----------------- | --------------------------------------------- | ---------------- |
| `system-prep`     | System preparation and updates                | ~2 minutes       |
| `desktop-install` | XFCE desktop environment                      | ~5 minutes       |
| `rdp-config`      | RDP server configuration                      | ~1 minute        |
| `user-creation`   | Developer user provisioning                   | ~30 seconds      |
| `ide-vscode`      | Visual Studio Code installation               | ~3 minutes       |
| `ide-cursor`      | Cursor IDE installation                       | ~2 minutes       |
| `ide-antigravity` | Antigravity IDE installation                  | ~2 minutes       |
| `terminal-setup`  | Terminal enhancements and shell configuration | ~45 seconds      |
| `dev-tools`       | Development tools installation                | ~1.5 minutes     |
| `verification`    | Post-installation validation                  | ~1 minute        |

## Exit Codes

The command returns different exit codes to indicate the result:

| Code | Name                  | Description                                    |
| ---- | --------------------- | ---------------------------------------------- |
| 0    | `SUCCESS`             | Provisioning completed successfully            |
| 1    | `VALIDATION_FAILED`   | Pre-flight validation failed                   |
| 2    | `PROVISIONING_FAILED` | Provisioning failed during execution           |
| 3    | `ROLLBACK_FAILED`     | Provisioning and rollback both failed          |
| 4    | `VERIFICATION_FAILED` | Provisioning completed but verification failed |
| 5    | `CONFIG_ERROR`        | Configuration file invalid or unreadable       |
| 6    | `PERMISSION_DENIED`   | Insufficient permissions (must run as root)    |
| 127  | `COMMAND_NOT_FOUND`   | Required command or dependency not found       |

## Environment Variables

The tool respects the following environment variables:

| Variable                 | Description                               | Default                          |
| ------------------------ | ----------------------------------------- | -------------------------------- |
| `VPS_PROVISION_CONFIG`   | Override default config file location     | `/etc/vps-provision/config.conf` |
| `VPS_PROVISION_LOG_DIR`  | Override default log directory            | `/var/log/vps-provision`         |
| `VPS_PROVISION_NO_COLOR` | Disable colored output (set to any value) | (not set)                        |

## Prerequisites

Before running the provisioning tool, ensure:

- ✅ Running as root or with sudo
- ✅ Debian 13 (Bookworm) operating system
- ✅ Active internet connection
- ✅ Minimum 10GB disk space available
- ✅ Minimum 2GB RAM (4GB recommended)

The tool will automatically validate these requirements before starting provisioning.

## Interactive Features

### Tab Completion

Bash tab completion is available for all command-line options and arguments. To enable:

```bash
# System-wide installation (requires root)
sudo cp etc/bash-completion.d/vps-provision /etc/bash_completion.d/
source /etc/bash_completion.d/vps-provision

# Or for current user only
source etc/bash-completion.d/vps-provision
```

After enabling, you can use tab completion:

```bash
vps-provision --<TAB>          # Complete options
vps-provision --skip-phase <TAB>  # Complete phase names
vps-provision --log-level <TAB>   # Complete log levels
```

### Interactive Prompts

When running in interactive mode (TTY), the tool may prompt for:

- ✅ Confirmation before destructive operations (unless `--yes` specified)
- ✅ Missing required arguments (unless defaults available)
- ✅ Custom values when needed

In non-interactive mode (CI/CD, scripts), prompts are automatically handled:

- Confirmations are skipped (requires `--yes` flag)
- Defaults are used for missing arguments
- Errors are raised if required values are missing

## Output Formats

### Text Output (Default)

Human-readable output with:

- Color-coded status messages (green=success, red=error, yellow=warning, blue=info)
- Progress indicators with percentage and time estimates
- Clear phase headers and completion messages
- Detailed error messages with suggested actions

Example:

```
[INFO] Starting phase: system-prep
[INFO] Progress: 10% (estimated 2m remaining)
[OK] System packages updated successfully
[INFO] Phase system-prep completed in 1m 45s
```

### JSON Output

Machine-readable structured output for automation:

```bash
vps-provision --output-format json
```

Output structure:

```json
{
  "session_id": "20251224-103000",
  "status": "COMPLETED",
  "start_time": "2025-12-24T10:30:00Z",
  "end_time": "2025-12-24T10:45:00Z",
  "duration_seconds": 900,
  "phases": [
    {
      "name": "system-prep",
      "status": "COMPLETED",
      "duration_seconds": 120,
      "checkpoint_exists": true
    }
  ],
  "errors": [],
  "warnings": []
}
```

### Plain Text Output

For log files and systems without color support:

```bash
vps-provision --no-color
# or
export VPS_PROVISION_NO_COLOR=1
vps-provision
```

Output includes text labels instead of colors:

- `[OK]` for success
- `[ERR]` for errors
- `[WARN]` for warnings
- `[INFO]` for informational messages

## Logging

All operations are logged to `/var/log/vps-provision/provision.log` with:

- Timestamps for each operation
- Detailed command outputs
- Error messages and stack traces
- Redacted sensitive information (`[REDACTED]` placeholders for passwords)

View logs:

```bash
# Follow logs in real-time
sudo tail -f /var/log/vps-provision/provision.log

# View last 100 lines
sudo tail -n 100 /var/log/vps-provision/provision.log

# Search for errors
sudo grep ERROR /var/log/vps-provision/provision.log

# View logs for specific session
sudo grep "session-20251224-103000" /var/log/vps-provision/provision.log
```

## Configuration Files

### Default Configuration

Default settings are loaded from `/etc/vps-provision/config.conf`:

```bash
# Default username for developer account
DEFAULT_USERNAME=devuser

# Default RDP port
RDP_PORT=3389

# Desktop environment
DESKTOP_ENV=xfce

# Enable/disable specific IDEs
INSTALL_VSCODE=true
INSTALL_CURSOR=true
INSTALL_ANTIGRAVITY=true

# Network timeout for downloads (seconds)
DOWNLOAD_TIMEOUT=300

# Retry attempts for failed operations
RETRY_ATTEMPTS=3
```

### Custom Configuration

Use a custom configuration file:

```bash
sudo vps-provision --config /path/to/custom.conf
# or
export VPS_PROVISION_CONFIG=/path/to/custom.conf
sudo vps-provision
```

## Troubleshooting

### Common Issues and Solutions

#### 1. Permission Denied

**Error**: `[ERROR] PERMISSION_DENIED: This script must be run as root`

**Solution**: Run with sudo:

```bash
sudo vps-provision
```

#### 2. Pre-flight Validation Failed

**Error**: `[ERROR] VALIDATION_FAILED: System does not meet requirements`

**Solution**: Check the specific validation failure:

```bash
sudo vps-provision --dry-run --log-level DEBUG
```

Common causes:

- Insufficient disk space: Free up space or use a larger droplet
- Wrong OS version: Requires Debian 13 (Bookworm)
- Missing internet connection: Check network connectivity

#### 3. Provisioning Failed Mid-Process

**Error**: `[ERROR] PROVISIONING_FAILED: Failed at phase X`

**Solution**: Resume from last checkpoint:

```bash
sudo vps-provision --resume
```

To start fresh:

```bash
sudo vps-provision --force
```

#### 4. Package Download Timeouts

**Error**: `[ERROR] Network timeout downloading package`

**Solution**: Retry with longer timeout or different mirror:

```bash
# Edit config to increase timeout
sudo nano /etc/vps-provision/config.conf
# Set: DOWNLOAD_TIMEOUT=600

sudo vps-provision --resume
```

#### 5. Port Already in Use

**Error**: `[ERROR] Port 3389 already in use`

**Solution**: Stop conflicting service or use different port:

```bash
# Check what's using the port
sudo lsof -i :3389

# Stop the service
sudo systemctl stop <service-name>

# Then retry
sudo vps-provision --resume
```

### Getting Help

1. **View detailed logs**: `sudo tail -f /var/log/vps-provision/provision.log`
2. **Enable debug mode**: `sudo vps-provision --log-level DEBUG`
3. **Dry run first**: `sudo vps-provision --dry-run`
4. **Check documentation**: `/usr/share/doc/vps-provision/README.md`
5. **Review examples**: `vps-provision --help`

## Best Practices

1. **Always start with dry run**: Preview actions before executing

   ```bash
   sudo vps-provision --dry-run
   ```

2. **Use custom username**: Don't use default 'devuser' in production

   ```bash
   sudo vps-provision --username <your-name>
   ```

3. **Enable debug logging**: For first-time runs or troubleshooting

   ```bash
   sudo vps-provision --log-level DEBUG
   ```

4. **Save output**: Capture output for records

   ```bash
   sudo vps-provision 2>&1 | tee provisioning.log
   ```

5. **Verify before connecting**: Check verification phase completes successfully

   ```bash
   # Look for: "[OK] Verification phase completed successfully"
   ```

6. **Change password**: Always change the default password on first login

7. **Backup checkpoints**: Before forcing re-provisioning
   ```bash
   sudo cp -r /var/vps-provision/checkpoints /root/checkpoints-backup
   ```

## Security Considerations

- 🔒 All passwords are redacted in logs (`[REDACTED]`)
- 🔒 SSH is hardened (root login disabled, key-only authentication)
- 🔒 RDP uses TLS encryption with 4096-bit RSA certificates
- 🔒 Firewall is configured (default DENY, explicit ALLOW for ports 22, 3389)
- 🔒 Fail2ban is installed and configured for SSH and RDP
- 🔒 Password expiry is enforced on first login
- 🔒 Sudo access is logged and audited

## Advanced Usage

### Scripted Provisioning

```bash
#!/bin/bash
# automated-provision.sh

# Enable error handling
set -euo pipefail

# Run provisioning with automation flags
if sudo vps-provision --yes --output-format json > result.json; then
  echo "Provisioning succeeded"

  # Extract connection details
  session_id=$(jq -r '.session_id' result.json)
  status=$(jq -r '.status' result.json)

  echo "Session: $session_id"
  echo "Status: $status"
else
  echo "Provisioning failed with exit code $?"
  exit 1
fi
```

### Custom Phase Workflows

```bash
# Install only core system (no IDEs)
sudo vps-provision --only-phase system-prep \
                   --only-phase desktop-install \
                   --only-phase rdp-config \
                   --only-phase user-creation

# Install IDEs separately later
sudo vps-provision --only-phase ide-vscode
```

### Monitoring Progress

```bash
# In one terminal, start provisioning
sudo vps-provision

# In another terminal, watch logs
watch -n 2 'tail -n 20 /var/log/vps-provision/provision.log'

# Or follow progress with specific patterns
tail -f /var/log/vps-provision/provision.log | grep -E 'Progress|COMPLETED|ERROR'
```

## Version Information

Check tool version and build information:

```bash
vps-provision --version
```

Output:

```
vps-provision version 1.0.0
Build date: 2025-12-24
Project: VPS Developer Workstation Provisioning
```

## See Also

- Main documentation: `/usr/share/doc/vps-provision/README.md`
- Configuration reference: `/usr/share/doc/vps-provision/configuration.md`
- Architecture guide: `/usr/share/doc/vps-provision/architecture.md`
- Troubleshooting guide: `/usr/share/doc/vps-provision/troubleshooting.md`

---

**Last Updated**: December 24, 2025  
**Version**: 1.0.0
