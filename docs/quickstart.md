# VPS Provision - Quick Start Guide

> Get your developer workstation running in under 5 minutes of active work!

## Prerequisites Check (2 minutes)

Before you begin, ensure you have:

- ✅ **Fresh Debian 13 VPS** from Digital Ocean
  - Minimum: 2GB RAM, 1 vCPU, 25GB disk
  - Recommended: 4GB RAM, 2 vCPU for best performance
- ✅ **Root SSH access** to your VPS

  ```bash
  # Test SSH connection
  ssh root@your-vps-ip
  ```

- ✅ **Stable internet connection** (both on VPS and your local machine)
  - VPS needs to download ~2GB of packages
  - Your machine will connect via RDP after provisioning

## Installation (1 minute)

### Step 1: SSH into Your VPS

```bash
ssh root@your-vps-ip
```

### Step 2: Download the Provisioning Tool

```bash
# Clone the repository
git clone https://github.com/your-org/vps-provision.git /opt/vps-provision

# Change to the directory
cd /opt/vps-provision
```

### Step 3: Run the Provisioning Script

```bash
# Basic provisioning (uses defaults)
./bin/vps-provision
```

**That's it!** The tool will now:

1. ✅ Validate your system (Debian 13, disk space, RAM)
2. ✅ Update packages and install base tools
3. ✅ Install XFCE desktop environment
4. ✅ Configure RDP server on port 3389
5. ✅ Create developer user (username: `devuser`)
6. ✅ Install VSCode, Cursor, and Antigravity IDEs
7. ✅ Configure terminal enhancements
8. ✅ Install development tools (git, build-essential, etc.)

**Total time**: ~15 minutes on 4GB/2vCPU droplet

## What to Expect

### Progress Display

You'll see real-time progress updates:

```
[Phase 2/10] Desktop Installation ================ 65% (3m 42s remaining)

[OK] Installing XFCE desktop environment...
[OK] Configuring display manager...
[OK] Setting up desktop icons and themes...
```

### Completion Message

When provisioning completes, you'll see:

```
==============================================================================

                       [OK] PROVISIONING SUCCESSFUL

==============================================================================

Your VPS developer workstation is ready!

CONNECTION DETAILS (copy-paste ready):
------------------------------------------------------------------------------

  RDP Connection:
    Host:     123.45.67.89
    Port:     3389
    Username: devuser
    Password: [REDACTED]

  [WARN] IMPORTANT: Change your password on first login!

  Connection String (for RDP clients):
    devuser@123.45.67.89:3389

------------------------------------------------------------------------------

Your temporary password (SAVE THIS NOW, will not be shown again):
  aB3$xYz9!mN2pQ5r

```

**⚠️ SAVE YOUR PASSWORD!** It will only be shown once.

## Connecting via RDP (2 minutes)

### Windows Users

1. Open **Remote Desktop Connection** (press `Win + R`, type `mstsc`)
2. Enter the connection details:
   - Computer: `123.45.67.89:3389`
   - Username: `devuser`
3. Click **Connect**
4. Enter the password when prompted
5. Accept the certificate warning (first time only)

### macOS Users

1. Download **Microsoft Remote Desktop** from App Store
2. Click **Add PC**
3. Enter connection details:
   - PC name: `123.45.67.89`
   - User account: `devuser`
4. Click **Connect**
5. Enter password when prompted

### Linux Users

```bash
# Using Remmina (GUI)
remmina

# Using xfreerdp (CLI)
xfreerdp /u:devuser /p:'your-password' /v:123.45.67.89:3389 /cert:ignore
```

## First Login Actions

### 1. Change Your Password (REQUIRED)

Open terminal in RDP session:

```bash
# Change your password
passwd

# Enter old password (the temporary one)
# Enter new password (twice for confirmation)
```

### 2. Verify Installations

Check that everything works:

```bash
# Check VSCode
code --version

# Check Cursor (from Applications menu)
# Click: Applications → Development → Cursor

# Check Antigravity (from Applications menu)
# Click: Applications → Development → Antigravity

# Check git
git --version

# Check developer tools
gcc --version
make --version
```

### 3. Start Coding!

- Launch any IDE from **Applications → Development** menu
- Open terminal for command-line work
- All development tools are ready to use

## Common Use Cases

### Use Case 1: Basic Development (Default)

```bash
# Uses all defaults: devuser, all IDEs, all tools
vps-provision
```

✅ **Best for**: Individual developers, learning, quick testing

---

### Use Case 2: Custom Username

```bash
# Use your preferred username
vps-provision --username alice
```

✅ **Best for**: Personal preference, multiple users on same host

---

### Use Case 3: Automated/CI Mode

```bash
# No prompts, JSON output for parsing
vps-provision --yes --output-format json > result.json
```

✅ **Best for**: Infrastructure automation, CI/CD pipelines

---

### Use Case 4: Minimal Installation (Server Only)

```bash
# Skip desktop and RDP (server/CLI only)
vps-provision --skip-phase desktop-install --skip-phase rdp-config
```

✅ **Best for**: Lightweight servers, CI/CD runners, no GUI needed

---

### Use Case 5: Specific IDEs Only

```bash
# Install only VSCode, skip others
vps-provision --only-phase ide-vscode
```

✅ **Best for**: Saving disk space, focused development environment

---

## Troubleshooting Quick Fixes

### Problem: "Permission Denied"

**Solution**:

```bash
# Run with sudo
sudo vps-provision
```

---

### Problem: Provisioning Hangs or Freezes

**Solution**:

```bash
# In another SSH session, resume from checkpoint
vps-provision --resume
```

---

### Problem: Can't Connect via RDP

**Check**:

```bash
# Verify xrdp is running
systemctl status xrdp

# Check firewall
ufw status

# Check port is listening
ss -tlnp | grep 3389
```

**Fix**:

```bash
# Restart xrdp
systemctl restart xrdp

# Open firewall (if closed)
ufw allow 3389/tcp
```

---

### Problem: Black Screen After RDP Login

**Solution**:

```bash
# As developer user in SSH session
echo "xfce4-session" > ~/.xsession
chmod +x ~/.xsession

# Restart xrdp
sudo systemctl restart xrdp
```

---

## Advanced Options

### Debug Mode

```bash
# See detailed logs for troubleshooting
vps-provision --log-level DEBUG
```

Logs written to: `/var/log/vps-provision/provision.log`

---

### Dry Run (Preview Only)

```bash
# See what will be done without making changes
vps-provision --dry-run
```

---

### Force Re-provisioning

```bash
# Ignore all checkpoints, start fresh
vps-provision --force
```

⚠️ **Warning**: This will re-run all phases, even if already completed

---

### Resume After Failure

```bash
# Continue from last successful checkpoint
vps-provision --resume
```

✅ **Best for**: Network interruptions, temporary failures

---

## Performance Tips

### Faster Provisioning

1. **Use 4GB RAM / 2 vCPU VPS**: Cuts time from 20 min to 12 min
2. **Close geographic distance**: Choose datacenter near package mirrors
3. **Stable network**: Avoid peak hours for faster downloads

### Optimizing for Your Workload

**Lightweight Development**:

```bash
# Skip heavyweight IDEs
vps-provision --skip-phase ide-cursor --skip-phase ide-antigravity
```

**Heavy Compilation**:

```bash
# Upgrade VPS to 8GB RAM / 4 vCPU before provisioning
# Handles large C++ or Java projects better
```

---

## Getting Help

### Documentation

- **Full CLI Reference**: `docs/cli-usage.md`
- **Architecture Guide**: `docs/architecture.md`
- **Security Guide**: `docs/security.md`
- **Troubleshooting**: `docs/troubleshooting.md`

### View Help

```bash
# Built-in help
vps-provision --help

# Version information
vps-provision --version
```

### Support Channels

1. **GitHub Issues**: Report bugs and request features
2. **Documentation**: Check `/usr/share/doc/vps-provision/`
3. **Logs**: Review `/var/log/vps-provision/provision.log`
4. **Community Forum**: Ask questions and share tips

---

## Next Steps

After successful provisioning:

1. ✅ **Change your password** (mandatory)
2. ✅ **Configure SSH keys** for your developer user
3. ✅ **Install project dependencies** (npm, cargo, etc.)
4. ✅ **Clone your repositories**
5. ✅ **Configure git** with your name and email
6. ✅ **Set up backups** for important data

### Recommended Post-Provisioning

```bash
# Configure git
git config --global user.name "Your Name"
git config --global user.email "your.email@example.com"

# Generate SSH key for git
ssh-keygen -t ed25519 -C "your.email@example.com"

# Add SSH key to GitHub/GitLab
cat ~/.ssh/id_ed25519.pub
# Copy and paste into GitHub Settings → SSH Keys

# Test SSH connection
ssh -T git@github.com
```

---

## Summary

✅ **Setup**: 5 minutes of active work  
✅ **Provisioning**: 15 minutes automated  
✅ **Total Time**: ~20 minutes from zero to coding

**You now have**:

- 🖥️ Full desktop environment (XFCE)
- 🌐 RDP access from anywhere
- 💻 Three IDEs (VSCode, Cursor, Antigravity)
- 🛠️ Complete development toolchain
- 🔒 Secure, hardened configuration

**Start building amazing things!** 🚀

---

**Last Updated**: December 24, 2025  
**Version**: 1.0.0
