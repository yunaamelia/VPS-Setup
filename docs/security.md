# VPS Provision Security Guide

## Overview

Security is a critical aspect of the VPS provisioning tool. This document outlines the security measures implemented, best practices, and hardening procedures.

## Table of Contents

1. [Security Principles](#security-principles)
2. [Authentication & Authorization](#authentication--authorization)
3. [Network Security](#network-security)
4. [Data Protection](#data-protection)
5. [Secure Coding Practices](#secure-coding-practices)
6. [Audit Logging](#audit-logging)
7. [Vulnerability Management](#vulnerability-management)
8. [Incident Response](#incident-response)
9. [Compliance](#compliance)

## Security Principles

### Defense in Depth

Multiple layers of security controls protect the system:

- Network: Firewall rules (UFW), fail2ban
- System: Minimal privileges, hardened SSH
- Application: Input validation, sanitization
- Data: Encryption at rest and in transit

### Least Privilege

Every component runs with minimum necessary permissions:

- Developer user: Limited sudo access (no root password)
- Services: Dedicated non-privileged accounts
- Files: Restrictive permissions (640 for logs, 600 for secrets)

### Secure by Default

Security features enabled automatically:

- Strong password generation (16+ chars, CSPRNG)
- SSH key-only authentication (password auth disabled)
- Firewall enabled with restrictive rules
- Automatic security updates

### Zero Trust

Validate all inputs, never trust user-provided data:

- All arguments sanitized via `lib/core/sanitize.sh`
- File paths checked for traversal attacks
- Command injection prevented via parameterization

## Authentication & Authorization

### Password Security (SEC-001, SEC-002, SEC-003)

**Generation**:

```python
# lib/utils/credential-gen.py
import secrets
import string

def generate_password(length=16):
    """Generate cryptographically secure random password."""
    alphabet = string.ascii_letters + string.digits + string.punctuation
    password = ''.join(secrets.choice(alphabet) for _ in range(length))
    return password
```

**Requirements**:

- Minimum 16 characters (SEC-001)
- Mixed case, digits, and symbols
- Generated using CSPRNG (secrets module) (SEC-002)
- Never logged or persisted unencrypted (SEC-003)

**Display**:

```bash
# Shown once to terminal, redacted in all logs
echo "Temporary password: ${password}"
log_info "Password set for ${username} (password: [REDACTED])"
```

**Best Practice**: User must change password on first login

---

### SSH Hardening (SEC-004, SEC-005)

**Configuration** (`/etc/ssh/sshd_config`):

```
PermitRootLogin no                    # SEC-004: Disable root SSH login
PasswordAuthentication no             # SEC-005: Key-only authentication
PubkeyAuthentication yes
ChallengeResponseAuthentication no
UsePAM yes
X11Forwarding yes                     # Required for desktop apps
PrintMotd no
AcceptEnv LANG LC_*
Subsystem sftp /usr/lib/openssh/sftp-server
```

**Key Management**:

```bash
# Generate SSH key pair (client-side)
ssh-keygen -t ed25519 -C "user@example.com"

# Add public key to VPS (before provisioning)
ssh-copy-id root@vps-ip

# Verify key-based login works
ssh root@vps-ip
```

**Post-Provisioning**: Root SSH disabled, developer user uses key-only auth

---

### Sudo Configuration (SEC-006)

**Developer User Sudo Rules**:

```
# /etc/sudoers.d/developer-user
devuser ALL=(ALL) NOPASSWD: ALL
```

**Why NOPASSWD**:

- Convenience for development tasks
- User already authenticated via SSH key
- Alternative: Require password for sensitive commands

**Hardening Option** (Production):

```
# Require password for destructive operations
devuser ALL=(ALL) NOPASSWD: /usr/bin/apt-get, /usr/bin/systemctl status
devuser ALL=(ALL) PASSWD: /usr/bin/systemctl stop, /bin/rm -rf
```

---

## Network Security

### Firewall Configuration (SEC-007, SEC-008)

**UFW Rules**:

```bash
# Default policies
ufw default deny incoming
ufw default allow outgoing

# Allow SSH (SEC-007)
ufw allow 22/tcp comment 'SSH'

# Allow RDP (SEC-008)
ufw allow 3389/tcp comment 'RDP'

# Enable firewall
ufw --force enable
```

**Verification**:

```bash
ufw status verbose
```

**Expected Output**:

```
Status: active
Logging: on (low)
Default: deny (incoming), allow (outgoing), disabled (routed)

To                         Action      From
--                         ------      ----
22/tcp                     ALLOW IN    Anywhere                  # SSH
3389/tcp                   ALLOW IN    Anywhere                  # RDP
```

---

### Rate Limiting (SEC-009)

**fail2ban Configuration**:

**/etc/fail2ban/jail.local**:

```ini
[sshd]
enabled = true
port = 22
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 3600
findtime = 600

[xrdp]
enabled = true
port = 3389
filter = xrdp
logpath = /var/log/xrdp.log
maxretry = 5
bantime = 1800
findtime = 600
```

**Custom Filter** (`/etc/fail2ban/filter.d/xrdp.conf`):

```ini
[Definition]
failregex = .*Failed login attempt from <HOST>.*
ignoreregex =
```

**Monitoring**:

```bash
# Check fail2ban status
fail2ban-client status

# Check banned IPs
fail2ban-client status sshd
fail2ban-client status xrdp

# Unban IP if needed
fail2ban-client set sshd unbanip 1.2.3.4
```

---

### Network Segmentation

**Recommendations** (for multi-user environments):

- Use VLANs to isolate workstations
- Implement network ACLs for inter-workstation communication
- Deploy VPN for remote access (alternative to direct RDP)

---

## Data Protection

### Encryption at Rest

**Sensitive Files**:

- `/etc/ssh/ssh_host_*_key`: SSH host keys (600 permissions)
- `/home/devuser/.ssh/authorized_keys`: SSH keys (600)
- `/etc/shadow`: Password hashes (640)

**Full Disk Encryption** (Recommended for Production):

```bash
# LUKS encryption (setup during OS installation)
cryptsetup luksFormat /dev/sda1
cryptsetup luksOpen /dev/sda1 encrypted_root
```

---

### Encryption in Transit

**SSH**: All SSH connections encrypted with modern ciphers

```
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com
MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com
KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org
```

**RDP**: TLS encryption enabled by default in xrdp

```
# /etc/xrdp/xrdp.ini
security_layer=tls
crypt_level=high
```

---

### Secret Management (SEC-010, UX-024)

**Redaction Function** (`lib/core/logger.sh`):

```bash
log_redact() {
  local text="$1"

  # Redact password patterns
  text=$(echo "$text" | sed -E 's/(password[=: ]+)[^ ]*/\1[REDACTED]/gi')

  # Redact API keys
  text=$(echo "$text" | sed -E 's/(api[_-]?key[=: ]+)[^ ]*/\1[REDACTED]/gi')

  # Redact tokens
  text=$(echo "$text" | sed -E 's/(token[=: ]+)[^ ]*/\1[REDACTED]/gi')

  echo "$text"
}
```

**Usage**:

```bash
# Automatic redaction in logs
log_info "User password set (password: [REDACTED])"

# Manual redaction
sensitive_data="password=secret123 api_key=abc123"
log_redacted INFO "$sensitive_data"
# Output: "password=[REDACTED] api_key=[REDACTED]"
```

**Secrets Storage** (Future Enhancement):

- Use HashiCorp Vault for centralized secret management
- Integrate with cloud provider secret stores (AWS Secrets Manager, Azure Key Vault)

---

## Secure Coding Practices

### Input Validation & Sanitization (SEC-018)

**Username Validation**:

```bash
sanitize_username() {
  local username="$1"

  # Must start with lowercase letter
  # Can contain lowercase letters, digits, underscore, hyphen
  # Length: 3-32 characters
  if [[ ! "$username" =~ ^[a-z][a-z0-9_-]{2,31}$ ]]; then
    log_error "Invalid username format: $username"
    return 1
  fi

  echo "$username"
}
```

**Path Sanitization**:

```bash
sanitize_path() {
  local path="$1"

  # Prevent directory traversal
  if [[ "$path" =~ \.\. ]]; then
    log_error "Path traversal detected: $path"
    return 1
  fi

  # Resolve to absolute path
  realpath -m "$path"
}
```

**Command Injection Prevention**:

```bash
# BAD: Command injection vulnerability
username="$1"
su - "$username" -c "ls $HOME"  # User could inject: ; rm -rf /

# GOOD: Proper quoting and validation
username=$(sanitize_username "$1") || exit 1
su - "$username" -c "ls \"\$HOME\""  # Escaped variable
```

---

### Error Handling

**Fail Securely**:

```bash
set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Check exit codes
if ! critical_operation; then
  log_error "Critical operation failed"
  rollback_all_changes
  exit 2
fi
```

**No Information Disclosure**:

```bash
# BAD: Reveals system details
log_error "Database connection failed: host=10.0.0.5 port=5432 user=admin"

# GOOD: Generic error message
log_error "Database connection failed (check logs for details)"
log_debug "Database details: host=10.0.0.5 port=5432"  # Debug log only
```

---

### Dependency Management

**Pinned Versions** (Future Enhancement):

```bash
# Pin package versions for reproducibility
apt-get install -y xfce4=4.18.0 xrdp=0.9.20
```

**Vulnerability Scanning**:

```bash
# Scan installed packages
apt-get install -y debsecan
debsecan --suite bookworm --only-fixed

# Update packages regularly
apt-get update && apt-get upgrade -y
```

---

## Audit Logging (SEC-017)

### Structured Logging

**Log Format**:

```
[TIMESTAMP] [LEVEL] [LABEL] MESSAGE
[2025-12-24 10:30:45] [INFO] [OK] System preparation completed
[2025-12-24 10:31:12] [ERROR] [ERR] Package installation failed: xfce4
```

**Log Levels**:

- **DEBUG**: Detailed diagnostic information (only in debug mode)
- **INFO**: General informational messages with [OK] label
- **WARNING**: Warnings with [WARN] label
- **ERROR**: Errors with [ERR] label
- **FATAL**: Critical errors that abort execution

---

### Audit Trail

**Transaction Log** (`/var/log/vps-provision/transactions.log`):

```
2025-12-24T10:30:00Z    Added user devuser    userdel -r devuser
2025-12-24T10:30:15Z    Installed xrdp        apt-get remove -y xrdp
2025-12-24T10:30:30Z    Modified /etc/ssh/sshd_config    cp /etc/ssh/sshd_config.bak /etc/ssh/sshd_config
```

**Purpose**:

- Forensic analysis after security incidents
- Rollback capability on failures
- Compliance audit trails

---

### System Audit Logs (auditd)

**Installation**:

```bash
apt-get install -y auditd
systemctl enable auditd
systemctl start auditd
```

**Audit Rules** (`/etc/audit/rules.d/vps-provision.rules`):

```
# Monitor user creation/deletion
-w /usr/sbin/useradd -p x -k user_modification
-w /usr/sbin/userdel -p x -k user_modification

# Monitor sudo usage
-w /etc/sudoers -p wa -k sudoers_changes
-w /etc/sudoers.d/ -p wa -k sudoers_changes

# Monitor SSH configuration
-w /etc/ssh/sshd_config -p wa -k sshd_config

# Monitor sensitive files
-w /etc/shadow -p wa -k shadow_file
-w /etc/passwd -p wa -k passwd_file
```

**Querying Audit Logs**:

```bash
# Search for user modifications
ausearch -k user_modification

# Search for sudo changes
ausearch -k sudoers_changes

# Generate report
aureport --summary
```

---

## Vulnerability Management

### Patching Strategy

**Automatic Security Updates**:

```bash
# Install unattended-upgrades
apt-get install -y unattended-upgrades apt-listchanges

# Configure
dpkg-reconfigure -plow unattended-upgrades

# Check configuration
cat /etc/apt/apt.conf.d/50unattended-upgrades
```

**Configuration**:

```
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}-security";
};
Unattended-Upgrade::AutoFixInterruptedDpkg "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "false";
```

---

### Vulnerability Scanning

**Periodic Scans**:

```bash
#!/bin/bash
# /usr/local/bin/vulnerability-scan.sh

# Update vulnerability database
apt-get update

# Scan for CVEs
debsecan --suite bookworm --format detail > /var/log/vulnerability-scan.log

# Send alert if vulnerabilities found
if grep -q "CVE" /var/log/vulnerability-scan.log; then
  mail -s "Vulnerability Alert: $(hostname)" admin@example.com < /var/log/vulnerability-scan.log
fi
```

**Cron Job**:

```
# /etc/cron.daily/vulnerability-scan
0 2 * * * /usr/local/bin/vulnerability-scan.sh
```

---

### Security Baseline

**CIS Debian Linux Benchmark** (Reference):

- Disable unused services
- Configure kernel parameters (/etc/sysctl.conf)
- Set file permissions on critical files
- Enable process accounting

**Automated Compliance**:

```bash
# Use Lynis for security auditing
apt-get install -y lynis
lynis audit system
```

---

## Incident Response

### Detection

**Signs of Compromise**:

- Unexpected user accounts in `/etc/passwd`
- Unknown processes (check with `ps aux`)
- Unusual network connections (`netstat -tulpn`)
- Failed login attempts (`grep "Failed password" /var/log/auth.log`)
- Modified system files (use `aide` for integrity checking)

---

### Containment

**Immediate Actions**:

```bash
# Isolate system from network
iptables -P INPUT DROP
iptables -P OUTPUT DROP
iptables -P FORWARD DROP

# Or shutdown network interface
ip link set eth0 down

# Preserve evidence
dd if=/dev/sda of=/mnt/evidence/disk.img bs=4M
tar -czf /mnt/evidence/logs-$(date +%Y%m%d).tar.gz /var/log
```

---

### Recovery

**Clean Reinstall** (Recommended):

1. Take snapshot of compromised system for forensics
2. Provision fresh VPS
3. Restore application data from backups (verify integrity)
4. Update all credentials (passwords, SSH keys, API keys)
5. Apply security patches

**Hardening Post-Incident**:

- Implement additional monitoring
- Restrict network access further
- Enable two-factor authentication (future feature)

---

## Compliance

### GDPR Considerations

**Data Minimization**:

- Only collect necessary user information (username, SSH key)
- No personal data stored by default

**Right to be Forgotten**:

```bash
# Complete user data deletion
userdel -r devuser
rm -rf /var/log/vps-provision/*devuser*
```

**Data Breach Notification**:

- Implement alerting for security events
- Maintain incident response plan
- Document breach notification procedures

---

### SOC 2 Type II (for Service Providers)

**Access Controls**:

- Multi-factor authentication for admin access (future)
- Regular access reviews
- Principle of least privilege

**Change Management**:

- All changes logged in transaction log
- Rollback capability for all modifications
- Testing in staging environment before production

**Monitoring & Logging**:

- Centralized log collection
- Automated alerting for anomalies
- Log retention for minimum 1 year

---

## Security Checklist

### Pre-Provisioning

- [ ] VPS hosted with reputable provider (Digital Ocean)
- [ ] SSH key pair generated (ed25519 recommended)
- [ ] Root SSH access via key (password disabled)
- [ ] Firewall rules planned (if custom requirements)

### During Provisioning

- [ ] Strong password generated (16+ chars, CSPRNG)
- [ ] Firewall enabled (UFW)
- [ ] fail2ban configured for SSH and RDP
- [ ] Root SSH login disabled
- [ ] Developer user created with sudo access

### Post-Provisioning

- [ ] Change developer user password on first login
- [ ] Verify SSH key-only authentication works
- [ ] Test RDP connection with encryption
- [ ] Review audit logs for any anomalies
- [ ] Enable automatic security updates
- [ ] Configure backup strategy
- [ ] Document credentials in secure password manager

### Ongoing Maintenance

- [ ] Apply security updates regularly
- [ ] Review audit logs weekly
- [ ] Scan for vulnerabilities monthly
- [ ] Rotate credentials quarterly
- [ ] Test incident response procedures annually

---

## References

- [Debian Security Manual](https://www.debian.org/doc/manuals/securing-debian-manual/)
- [NIST Cybersecurity Framework](https://www.nist.gov/cyberframework)
- [OWASP Top 10](https://owasp.org/www-project-top-ten/)
- [CIS Benchmarks](https://www.cisecurity.org/cis-benchmarks/)
- [OpenSSH Security Best Practices](https://www.openssh.com/security.html)

---

**Last Updated**: December 24, 2025  
**Version**: 1.0.0
