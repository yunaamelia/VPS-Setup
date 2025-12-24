# VPS Provision Troubleshooting Guide

## Table of Contents

1. [Common Issues](#common-issues)
2. [Installation Failures](#installation-failures)
3. [RDP Connection Problems](#rdp-connection-problems)
4. [IDE Launch Issues](#ide-launch-issues)
5. [Performance Problems](#performance-problems)
6. [Network Issues](#network-issues)
7. [Recovery Procedures](#recovery-procedures)
8. [Debug Mode](#debug-mode)
9. [Logging](#logging)
10. [Getting Help](#getting-help)

## Common Issues

### Issue: "Permission Denied" Error

**Symptom**: Command fails with "Permission denied" message

**Cause**: Not running as root or with sudo

**Solution**:

```bash
# Run with sudo
sudo vps-provision

# Or switch to root
sudo -i
vps-provision
```

**Verification**:

```bash
# Check if running as root
whoami  # Should output: root
id -u   # Should output: 0
```

---

### Issue: "Debian 13 required" Error

**Symptom**: Pre-flight check fails with OS version error

**Cause**: Running on unsupported Linux distribution or version

**Solution**:

```bash
# Check your OS version
cat /etc/os-release
# Ensure VERSION_ID="13" and ID="debian"

# This tool only supports Debian 13 (Bookworm)
# You must use a compatible VPS
```

**Workaround**: None - Debian 13 is a hard requirement

---

### Issue: "Insufficient disk space" Error

**Symptom**: Pre-flight check fails due to low disk space

**Cause**: Less than 10GB available space

**Solution**:

```bash
# Check available space
df -h /

# Clean up if possible
apt-get clean
apt-get autoremove -y

# Or resize your VPS disk through Digital Ocean panel
```

**Minimum Requirements**: 10GB free space (25GB recommended)

---

### Issue: Provisioning Hangs or Freezes

**Symptom**: No progress updates for > 5 minutes

**Cause**: Network timeout, package download stalled, or system resource exhaustion

**Diagnosis**:

```bash
# In another SSH session, check:
top  # CPU and memory usage
iostat -x 1  # Disk I/O
netstat -tulpn  # Network connections
tail -f /var/log/vps-provision/provision.log  # Live logs
```

**Solution**:

```bash
# If truly hung, kill and resume
pkill -9 vps-provision

# Resume from last checkpoint
vps-provision --resume
```

---

## Installation Failures

### Desktop Environment Installation Fails

**Symptom**: Phase "desktop-install" fails with package errors

**Common Causes**:

1. Repository mirrors unavailable
2. Package conflicts
3. Insufficient memory during installation

**Solution**:

```bash
# Update package lists
apt-get update

# Check for broken packages
apt-get check
dpkg --configure -a

# Resume provisioning
vps-provision --resume
```

**Advanced Diagnosis**:

```bash
# Check specific error
cat /var/log/vps-provision/provision.log | grep -i "error\|fail"

# Test XFCE installation manually
apt-get install -y xfce4 xfce4-goodies
```

---

### IDE Installation Fails

**Symptom**: VSCode, Cursor, or Antigravity installation fails

**Common Causes**:

1. GPG key verification failure
2. Download timeout
3. Package dependency conflicts

**Solution for VSCode**:

```bash
# Manual installation
wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > /usr/share/keyrings/vscode.gpg
echo "deb [arch=amd64 signed-by=/usr/share/keyrings/vscode.gpg] https://packages.microsoft.com/repos/code stable main" > /etc/apt/sources.list.d/vscode.list
apt-get update
apt-get install -y code

# Verify installation
code --version
```

**Solution for Cursor/Antigravity**:

```bash
# Check download logs
tail -100 /var/log/vps-provision/provision.log

# Retry with increased timeout
export DOWNLOAD_TIMEOUT=300
vps-provision --resume
```

---

### RDP Server Configuration Fails

**Symptom**: xrdp service fails to start

**Common Causes**:

1. Port 3389 already in use
2. xrdp package installation incomplete
3. SSL certificate generation failed

**Diagnosis**:

```bash
# Check service status
systemctl status xrdp

# Check port availability
ss -tlnp | grep 3389

# Check logs
journalctl -u xrdp -n 50
```

**Solution**:

```bash
# Restart service
systemctl restart xrdp

# Check configuration
cat /etc/xrdp/xrdp.ini

# Regenerate SSL certificate if needed
cd /etc/xrdp
rm -f cert.pem key.pem
openssl req -x509 -newkey rsa:2048 -nodes -keyout key.pem -out cert.pem -days 365 -subj "/CN=localhost"
systemctl restart xrdp
```

---

## RDP Connection Problems

### Cannot Connect to RDP Port

**Symptom**: RDP client cannot connect to VPS

**Diagnosis**:

```bash
# Check if xrdp is running
systemctl status xrdp

# Check if port is listening
ss -tlnp | grep 3389

# Check firewall rules
ufw status
iptables -L -n -v
```

**Solution**:

```bash
# Start xrdp if stopped
systemctl start xrdp
systemctl enable xrdp

# Open firewall port
ufw allow 3389/tcp
ufw reload

# Test from VPS itself
telnet localhost 3389
```

**External Testing**:

```bash
# From your local machine
telnet YOUR_VPS_IP 3389
# Should connect successfully
```

---

### RDP Connects but Shows Black Screen

**Symptom**: RDP connection succeeds but desktop doesn't appear

**Cause**: XFCE session not starting correctly

**Solution**:

```bash
# As the developer user
echo "xfce4-session" > ~/.xsession
chmod +x ~/.xsession

# Restart xrdp
systemctl restart xrdp
```

**Alternative Solution**:

```bash
# Reinstall XFCE session
apt-get install --reinstall xfce4-session

# Clear user session cache
rm -rf ~/.cache/sessions
```

---

### Authentication Fails

**Symptom**: Wrong username or password error

**Cause**: Incorrect credentials or password expired

**Solution**:

```bash
# Reset developer user password (as root)
passwd devuser

# Ensure user exists
id devuser

# Check account status
chage -l devuser
```

---

## IDE Launch Issues

### VSCode Won't Launch

**Symptom**: VSCode menu entry does nothing or shows error

**Diagnosis**:

```bash
# Try launching from terminal
code
# Check for error messages

# Check if installed
which code
code --version

# Check desktop entry
cat /usr/share/applications/code.desktop
```

**Solution**:

```bash
# Reinstall VSCode
apt-get remove --purge code
apt-get install -y code

# Rebuild desktop menu cache
update-desktop-database

# Test launch
code --new-window
```

---

### Cursor IDE Missing or Broken

**Symptom**: Cursor not in applications menu

**Cause**: AppImage not properly installed or desktop entry missing

**Solution**:

```bash
# Check if AppImage exists
ls -lh /opt/cursor/cursor.AppImage

# Check desktop entry
cat /usr/share/applications/cursor.desktop

# Manually create desktop entry if missing
cat > /usr/share/applications/cursor.desktop <<'EOF'
[Desktop Entry]
Name=Cursor
Exec=/opt/cursor/cursor.AppImage --no-sandbox
Icon=/opt/cursor/icon.png
Type=Application
Categories=Development;IDE;
EOF

update-desktop-database
```

---

## Performance Problems

### Slow Provisioning (> 20 minutes)

**Symptom**: Provisioning takes longer than expected

**Common Causes**:

1. Slow network connection
2. Insufficient VPS resources (< 2GB RAM)
3. Busy Debian package mirrors

**Diagnosis**:

```bash
# Check network speed
curl -o /dev/null http://speedtest.tele2.net/10MB.zip

# Check system resources
free -h
top

# Check I/O wait
iostat -x 1 10
```

**Solution**:

```bash
# Upgrade VPS resources (Digital Ocean panel)
# Or wait for current provisioning to complete

# Use faster mirror (edit /etc/apt/sources.list)
# Replace with geographically closer Debian mirror
```

---

### RDP Session Slow or Laggy

**Symptom**: Desktop is slow or unresponsive over RDP

**Cause**: Network latency, insufficient VPS resources, or compression settings

**Solution**:

```bash
# Optimize xrdp compression (edit /etc/xrdp/xrdp.ini)
crypt_level=low
bitmap_compression=true

# Restart xrdp
systemctl restart xrdp

# Consider upgrading VPS to 4GB RAM for better performance
```

---

### High Memory Usage

**Symptom**: System running out of memory

**Diagnosis**:

```bash
free -h
ps aux --sort=-%mem | head -10
```

**Solution**:

```bash
# Close unused IDEs
# Restart desktop session
# Or upgrade VPS memory
```

---

## Network Issues

### Package Download Failures

**Symptom**: apt-get fails with connection timeout

**Solution**:

```bash
# Check network connectivity
ping -c 4 8.8.8.8
curl -I https://deb.debian.org

# Use different DNS servers
echo "nameserver 8.8.8.8" > /etc/resolv.conf
echo "nameserver 1.1.1.1" >> /etc/resolv.conf

# Retry provisioning
vps-provision --resume
```

---

### SSL Certificate Verification Fails

**Symptom**: wget/curl fail with SSL errors

**Solution**:

```bash
# Update CA certificates
apt-get update
apt-get install -y ca-certificates
update-ca-certificates

# Sync system time (SSL requires accurate time)
apt-get install -y ntpdate
ntpdate pool.ntp.org
```

---

## Recovery Procedures

### Complete Rollback After Failure

**Symptom**: Provisioning failed and system is in inconsistent state

**Solution**:

```bash
# Automatic rollback (usually happens automatically on failure)
# Manual rollback if needed:
vps-provision --rollback  # If implemented

# Or clean slate
vps-provision --force  # Ignore checkpoints, start fresh
```

---

### Resume After Network Interruption

**Symptom**: Provisioning interrupted due to network loss

**Solution**:

```bash
# Wait for network to recover
ping -c 4 8.8.8.8

# Resume from last checkpoint
vps-provision --resume
```

**Checkpoint Status**:

```bash
# Check completed phases
ls -la /var/vps-provision/checkpoints/
```

---

### Clean Up Failed Installation

**Symptom**: Need to start completely fresh

**Solution**:

```bash
# Remove all checkpoints
rm -rf /var/vps-provision/checkpoints/*

# Clear logs
rm -rf /var/log/vps-provision/*

# Remove developer user if exists
userdel -r devuser 2>/dev/null || true

# Uninstall desktop environment (if desired)
apt-get remove --purge xfce4 xfce4-goodies xrdp

# Run fresh provisioning
vps-provision --force
```

---

## Debug Mode

### Enable Verbose Logging

**Command**:

```bash
vps-provision --log-level DEBUG
```

**Output**: All debug messages written to both console and log file

**Log Location**:

```bash
tail -f /var/log/vps-provision/provision.log
```

---

### Dry Run Mode

**Purpose**: Preview actions without making changes

**Command**:

```bash
vps-provision --dry-run
```

**Output**: Shows all planned actions, no system modifications

---

### Step-by-Step Execution

**Command**:

```bash
# Run only specific phases
vps-provision --only-phase system-prep
vps-provision --only-phase desktop-install
```

**Use Case**: Isolate which phase is failing

---

## Logging

### Log Files

| File             | Purpose                  | Location                                |
| ---------------- | ------------------------ | --------------------------------------- |
| provision.log    | Main provisioning log    | /var/log/vps-provision/provision.log    |
| transactions.log | Rollback transaction log | /var/log/vps-provision/transactions.log |
| xrdp.log         | RDP server logs          | /var/log/xrdp.log                       |
| Xorg.log         | X server logs            | /var/log/Xorg.0.log                     |

### Viewing Logs

```bash
# Live tail main log
tail -f /var/log/vps-provision/provision.log

# Search for errors
grep -i error /var/log/vps-provision/provision.log

# Last 100 lines
tail -100 /var/log/vps-provision/provision.log

# Filter by log level
grep "\[ERR\]" /var/log/vps-provision/provision.log
grep "\[WARN\]" /var/log/vps-provision/provision.log
```

### Log Redaction

**Note**: Passwords and sensitive data are automatically redacted in logs using `[REDACTED]` markers per UX-024.

---

## Getting Help

### Collect Diagnostic Information

**Script**:

```bash
#!/bin/bash
# Save this as collect-diagnostics.sh

cat > /tmp/vps-provision-diagnostics.txt <<EOF
=== System Information ===
$(uname -a)
$(cat /etc/os-release)

=== Resources ===
$(free -h)
$(df -h)

=== Network ===
$(ip addr)
$(ss -tlnp)

=== Services ===
$(systemctl status xrdp)

=== Last 50 Log Lines ===
$(tail -50 /var/log/vps-provision/provision.log)

=== Checkpoints ===
$(ls -la /var/vps-provision/checkpoints/)
EOF

echo "Diagnostics saved to /tmp/vps-provision-diagnostics.txt"
```

**Run**:

```bash
chmod +x collect-diagnostics.sh
./collect-diagnostics.sh
```

### Support Channels

1. **Documentation**: Check `/usr/share/doc/vps-provision/`
2. **GitHub Issues**: Report bugs with diagnostics
3. **Community Forum**: Ask questions and share solutions
4. **Email Support**: support@example.com (if applicable)

### Before Asking for Help

Please include:

- [ ] VPS specifications (RAM, CPU, disk)
- [ ] Debian version (`cat /etc/os-release`)
- [ ] Provisioning command used
- [ ] Error messages from logs
- [ ] Diagnostic information from script above
- [ ] Steps to reproduce

---

## Quick Reference

### Common Commands

```bash
# Basic provisioning
vps-provision

# Resume after failure
vps-provision --resume

# Force fresh start
vps-provision --force

# Debug mode
vps-provision --log-level DEBUG

# Dry run (preview only)
vps-provision --dry-run

# View logs
tail -f /var/log/vps-provision/provision.log

# Check service status
systemctl status xrdp

# Test RDP connection
telnet YOUR_VPS_IP 3389
```

### Health Checks

```bash
# System resources
free -h && df -h

# Network connectivity
ping -c 4 8.8.8.8

# Services running
systemctl status xrdp
systemctl status ssh

# Port listening
ss -tlnp | grep -E '3389|22'

# User exists
id devuser

# Desktop installed
dpkg -l | grep xfce4
```

---

## Appendix: Error Codes

| Code | Meaning             | Common Causes                   |
| ---- | ------------------- | ------------------------------- |
| 0    | Success             | Provisioning completed          |
| 1    | Validation Failed   | OS version, disk space, RAM     |
| 2    | Provisioning Failed | Network, packages, dependencies |
| 3    | Rollback Failed     | Corrupted transaction log       |
| 4    | Verification Failed | Services not starting           |
| 5    | Config Error        | Invalid config file             |
| 6    | Permission Denied   | Not running as root             |
| 127  | Command Not Found   | Missing dependency              |

---

**Last Updated**: December 24, 2025  
**Version**: 1.0.0
