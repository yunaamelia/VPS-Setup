# VPS Provision Documentation

> **Complete documentation for the VPS Developer Workstation Provisioning Tool**

## Quick Links

| Document                                        | Purpose                          | Audience                    |
| ----------------------------------------------- | -------------------------------- | --------------------------- |
| **[Quick Start Guide](quickstart.md)**          | Get started in 5 minutes         | New users, first-time setup |
| **[CLI Usage Guide](cli-usage.md)**             | Complete command-line reference  | All users, daily operations |
| **[Architecture Guide](architecture.md)**       | System design and components     | Developers, contributors    |
| **[Security Guide](security.md)**               | Security practices and hardening | Security teams, compliance  |
| **[Troubleshooting Guide](troubleshooting.md)** | Problem diagnosis and resolution | All users, support teams    |

## Documentation Overview

### For End Users

Start here if you're using the tool to provision your VPS:

1. **[Quick Start Guide](quickstart.md)** ⭐ **Start here!**

   - 5-minute setup walkthrough
   - Common use cases with examples
   - First login instructions
   - Quick troubleshooting tips

2. **[CLI Usage Guide](cli-usage.md)**

   - Complete command-line reference
   - All available options and flags
   - Advanced usage scenarios
   - Configuration file format

3. **[Troubleshooting Guide](troubleshooting.md)**
   - Common issues and solutions
   - Installation failure recovery
   - RDP connection problems
   - Performance optimization
   - Debug mode and logging

### For Developers & Contributors

Start here if you're developing or extending the tool:

1. **[Architecture Guide](architecture.md)**

   - System architecture overview
   - Component layer descriptions
   - Data flow and state management
   - Module development patterns
   - Extensibility points
   - Testing architecture

2. **[Security Guide](security.md)**
   - Security principles and practices
   - Authentication & authorization
   - Network security configuration
   - Secure coding standards
   - Audit logging
   - Vulnerability management

### For Security Teams

Security-focused documentation:

1. **[Security Guide](security.md)** ⭐ **Priority read**

   - Threat model and mitigations
   - Hardening procedures
   - Compliance considerations (GDPR, SOC 2)
   - Incident response procedures
   - Security checklist

2. **[Architecture Guide](architecture.md)** (Security Architecture section)
   - Input sanitization
   - Credential management
   - Privilege management
   - Audit logging

## Key Features

### 🚀 One-Command Provisioning

```bash
vps-provision
```

Complete developer workstation in ≤15 minutes.

### 🔄 Idempotent & Resumable

Safe to run multiple times. Automatically resumes from checkpoints after failures.

### 🔙 Automatic Rollback

All changes tracked. System restored to clean state on failure.

### 🔒 Security-Focused

- Strong password generation (CSPRNG)
- SSH hardening (key-only auth)
- Firewall configuration (UFW)
- Intrusion prevention (fail2ban)
- Audit logging

### 📊 Real-Time Progress

Visual progress indicators with time estimates.

### 🎨 Accessible UX

- Color-coded output with text labels ([OK], [ERR], [WARN])
- `--no-color` mode for screen readers
- Simple ASCII art (no complex Unicode)
- Sensitive data redaction

## Installation

### Prerequisites

- Fresh **Debian 13 (Bookworm)** VPS
- Minimum: **2GB RAM, 1 vCPU, 25GB disk**
- **Root SSH access**

### Quick Install

```bash
# SSH into your VPS
ssh root@your-vps-ip

# Clone and run
git clone https://github.com/your-org/vps-provision.git /opt/vps-provision
cd /opt/vps-provision
./bin/vps-provision
```

**Detailed instructions**: See [Quick Start Guide](quickstart.md)

## What Gets Installed

### Desktop Environment

- **XFCE 4.18**: Lightweight desktop environment
- **xrdp**: RDP server for remote access

### IDEs (Integrated Development Environments)

- **Visual Studio Code**: Microsoft's popular code editor
- **Cursor**: AI-powered IDE
- **Antigravity**: Modern development environment

### Development Tools

- **git**: Version control
- **build-essential**: Compilers and build tools (gcc, g++, make)
- **curl, wget**: Network utilities
- **vim, nano**: Text editors
- **Terminal enhancements**: oh-my-bash, custom themes

### System Configuration

- **Developer user**: Created with passwordless sudo
- **SSH hardening**: Root login disabled, key-only auth
- **Firewall**: UFW enabled with restrictive rules
- **Intrusion prevention**: fail2ban configured

## Common Use Cases

### Individual Developer

```bash
# Default configuration
vps-provision
```

### Team Environment

```bash
# Custom usernames for team members
vps-provision --username alice
vps-provision --username bob
```

### CI/CD Integration

```bash
# Automated provisioning with JSON output
vps-provision --yes --output-format json
```

### Lightweight Server

```bash
# Skip desktop/RDP for CLI-only
vps-provision --skip-phase desktop-install --skip-phase rdp-config
```

## Performance

| VPS Size         | Provisioning Time | Recommended For                          |
| ---------------- | ----------------- | ---------------------------------------- |
| 2GB RAM / 1 vCPU | ~20 minutes       | Testing, light development               |
| 4GB RAM / 2 vCPU | ~12 minutes       | ⭐ **Recommended** - General development |
| 8GB RAM / 4 vCPU | ~10 minutes       | Heavy compilation, multi-IDE usage       |

## Support

### Self-Service

1. Check the **[Troubleshooting Guide](troubleshooting.md)**
2. Review logs: `/var/log/vps-provision/provision.log`
3. Run in debug mode: `vps-provision --log-level DEBUG`

### Community

- **GitHub Issues**: Bug reports and feature requests
- **Discussions**: Questions and community support
- **Wiki**: Community-contributed guides and tips

### Professional Support

Contact: support@example.com (if applicable)

## Contributing

We welcome contributions! Areas to contribute:

- **Documentation**: Improve guides, add examples
- **Testing**: Write tests, report bugs
- **Features**: Add new IDEs, tools, configurations
- **Security**: Report vulnerabilities, suggest hardening

See `CONTRIBUTING.md` for guidelines.

## License

[Insert License Here - e.g., MIT, Apache 2.0]

## Version

**Current Version**: 1.0.0  
**Last Updated**: December 24, 2025

## Changelog

See `CHANGELOG.md` for version history and release notes.

---

## Quick Reference Card

### Essential Commands

```bash
# Basic provisioning
vps-provision

# Resume after failure
vps-provision --resume

# Force fresh start
vps-provision --force

# Debug mode
vps-provision --log-level DEBUG

# Preview without changes
vps-provision --dry-run

# Custom username
vps-provision --username alice

# No-color mode (accessibility)
vps-provision --no-color
```

### Log Files

```bash
# Main provisioning log
tail -f /var/log/vps-provision/provision.log

# Transaction log (for rollback)
cat /var/log/vps-provision/transactions.log

# RDP server log
journalctl -u xrdp -f
```

### Service Management

```bash
# Check RDP server
systemctl status xrdp

# Restart RDP server
systemctl restart xrdp

# Check firewall
ufw status verbose

# View checkpoints
ls -la /var/vps-provision/checkpoints/
```

### Connection Testing

```bash
# Test RDP port
telnet YOUR_VPS_IP 3389

# Test from local machine
xfreerdp /u:devuser /v:YOUR_VPS_IP:3389
```

---

## Documentation Standards

This documentation follows these principles:

- **User-Centric**: Written for the user's goals, not the system's implementation
- **Actionable**: Includes copy-paste commands and concrete examples
- **Accessible**: Clear language, no jargon without explanation
- **Complete**: Covers happy paths, edge cases, and error scenarios
- **Maintainable**: Easy to update as the system evolves

**Feedback**: Documentation improvements welcome! Open an issue or submit a PR.

---

**Last Updated**: December 24, 2025  
**Maintained By**: VPS Provision Team
