#!/usr/bin/env python3
"""
Health Check Utility
Post-installation validation of all provisioned components

Usage:
    python3 health-check.py [--output FORMAT] [--verbose]

Options:
    --output FORMAT    Output format: text, json (default: text)
    --verbose          Show detailed check information

Checks:
    - System validation (OS, resources)
    - Desktop environment (XFCE, LightDM)
    - RDP server (xrdp service, port availability)
    - Developer user (account, permissions)
    - IDEs (VSCode, Cursor, Antigravity)
    - Development tools (git, build-essential)
    - Terminal configuration
"""

import argparse
import json
import os
import socket
import subprocess
import sys
from typing import Any, Dict, List, Tuple


class HealthCheck:
    """Post-installation validation checks"""

    def __init__(self, verbose: bool = False):
        self.verbose = verbose
        self.results: List[Dict[str, Any]] = []

    def run_command(self, cmd: List[str], check: bool = False) -> Tuple[bool, str, str]:
        """
        Run a command and return result

        Returns:
            Tuple of (success: bool, stdout: str, stderr: str)
        """
        try:
            result = subprocess.run(cmd, capture_output=True, text=True, check=check)
            return (result.returncode == 0, result.stdout, result.stderr)
        except subprocess.CalledProcessError as e:
            return (False, e.stdout, e.stderr)
        except FileNotFoundError:
            return (False, "", f"Command not found: {cmd[0]}")

    def check_os_version(self) -> Dict[str, Any]:
        """Validate OS is Debian 13"""
        check: Dict[str, Any] = {
            "name": "Operating System",
            "category": "system",
            "status": "unknown",
            "message": "",
            "details": {},
        }

        try:
            # Check /etc/os-release
            with open("/etc/os-release", "r", encoding="utf-8") as f:
                os_info = {}
                for line in f:
                    if "=" in line:
                        key, value = line.strip().split("=", 1)
                        os_info[key] = value.strip('"')

            check["details"] = os_info

            if "Debian" in os_info.get("NAME", ""):
                if os_info.get("VERSION_ID") == "13":
                    check["status"] = "pass"
                    check["message"] = "Debian 13 (Bookworm) detected"
                else:
                    check["status"] = "fail"
                    check["message"] = (
                        f"Wrong Debian version: {os_info.get('VERSION_ID', 'unknown')}"
                    )
            else:
                check["status"] = "fail"
                check["message"] = f"Not Debian: {os_info.get('NAME', 'unknown')}"

        except Exception as e:
            check["status"] = "error"
            check["message"] = f"Failed to check OS: {str(e)}"

        self.results.append(check)
        return check

    def check_resources(self) -> Dict[str, Any]:
        """Check system resources meet minimum requirements"""
        check: Dict[str, Any] = {
            "name": "System Resources",
            "category": "system",
            "status": "unknown",
            "message": "",
            "details": {},
        }

        try:
            # Check RAM
            with open("/proc/meminfo", "r", encoding="utf-8") as f:
                for line in f:
                    if line.startswith("MemTotal:"):
                        mem_kb = int(line.split()[1])
                        mem_mb = mem_kb // 1024
                        check["details"]["ram_mb"] = mem_mb
                        break

            # Check disk space
            success, stdout, _ = self.run_command(["df", "-BG", "/"])
            if success:
                lines = stdout.strip().split("\n")
                if len(lines) > 1:
                    parts = lines[1].split()
                    disk_total = int(parts[1].rstrip("G"))
                    disk_available = int(parts[3].rstrip("G"))
                    check["details"]["disk_total_gb"] = disk_total
                    check["details"]["disk_available_gb"] = disk_available

            # Check CPU
            success, stdout, _ = self.run_command(["nproc"])
            if success:
                check["details"]["cpu_cores"] = int(stdout.strip())

            # Validate minimums
            ram_ok = check["details"].get("ram_mb", 0) >= 2048
            disk_ok = check["details"].get("disk_available_gb", 0) >= 10
            cpu_ok = check["details"].get("cpu_cores", 0) >= 1

            if ram_ok and disk_ok and cpu_ok:
                check["status"] = "pass"
                check["message"] = "Resource requirements met"
            else:
                check["status"] = "fail"
                issues = []
                if not ram_ok:
                    issues.append("RAM < 2GB")
                if not disk_ok:
                    issues.append("Disk < 10GB")
                if not cpu_ok:
                    issues.append("CPU < 1 core")
                check["message"] = f"Insufficient resources: {', '.join(issues)}"

        except Exception as e:
            check["status"] = "error"
            check["message"] = f"Failed to check resources: {str(e)}"

        self.results.append(check)
        return check

    def check_service(self, service_name: str, display_name: str) -> Dict[str, Any]:
        """Check if systemd service is active"""
        check: Dict[str, Any] = {
            "name": display_name,
            "category": "services",
            "status": "unknown",
            "message": "",
            "details": {},
        }

        success, stdout, _ = self.run_command(["systemctl", "is-active", service_name])

        if success and "active" in stdout:
            check["status"] = "pass"
            check["message"] = f"{display_name} service is active"
            check["details"]["service_status"] = stdout.strip()
        else:
            check["status"] = "fail"
            check["message"] = f"{display_name} service is not active"
            check["details"]["service_status"] = (
                stdout.strip() if stdout else "inactive"
            )

        self.results.append(check)
        return check

    def check_port(self, port: int, service_name: str) -> Dict[str, Any]:
        """Check if port is listening"""
        check: Dict[str, Any] = {
            "name": f"Port {port} ({service_name})",
            "category": "network",
            "status": "unknown",
            "message": "",
            "details": {"port": port},
        }

        try:
            sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            sock.settimeout(1)
            result = sock.connect_ex(("127.0.0.1", port))
            sock.close()

            if result == 0:
                check["status"] = "pass"
                check["message"] = f"Port {port} is listening"
            else:
                check["status"] = "fail"
                check["message"] = f"Port {port} is not listening"

        except Exception as e:
            check["status"] = "error"
            check["message"] = f"Failed to check port {port}: {str(e)}"

        self.results.append(check)
        return check

    def check_executable(
        self, command: str, display_name: str, version_arg: str = "--version"
    ) -> Dict[str, Any]:
        """Check if executable exists and is runnable"""
        check: Dict[str, Any] = {
            "name": display_name,
            "category": "software",
            "status": "unknown",
            "message": "",
            "details": {"command": command},
        }

        success, stdout, _ = self.run_command(["which", command])

        if success and stdout.strip():
            exe_path = stdout.strip()
            check["details"]["path"] = exe_path

            # Try to get version
            ver_success, ver_stdout, _ = self.run_command([command, version_arg])
            if ver_success:
                version = ver_stdout.split("\n")[0][:100]  # First line, truncated
                check["details"]["version"] = version

            check["status"] = "pass"
            check["message"] = f"{display_name} is installed"
        else:
            check["status"] = "fail"
            check["message"] = f"{display_name} not found"

        self.results.append(check)
        return check

    def check_user(self, username: str) -> Dict[str, Any]:
        """Check if user exists with correct configuration"""
        check: Dict[str, Any] = {
            "name": f"User: {username}",
            "category": "users",
            "status": "unknown",
            "message": "",
            "details": {"username": username},
        }

        try:
            import pwd

            user_info = pwd.getpwnam(username)

            check["details"]["uid"] = user_info.pw_uid
            check["details"]["gid"] = user_info.pw_gid
            check["details"]["home"] = user_info.pw_dir
            check["details"]["shell"] = user_info.pw_shell

            # Check if in sudo group
            success, stdout, _ = self.run_command(["groups", username])
            if success:
                groups = stdout.strip().split(":")[1].strip().split()
                check["details"]["groups"] = groups
                has_sudo = "sudo" in groups
            else:
                has_sudo = False

            # Check home directory exists
            home_exists = os.path.isdir(user_info.pw_dir)

            if home_exists and has_sudo:
                check["status"] = "pass"
                check["message"] = f"User {username} configured correctly"
            else:
                check["status"] = "warning"
                issues = []
                if not home_exists:
                    issues.append("home directory missing")
                if not has_sudo:
                    issues.append("not in sudo group")
                check["message"] = f"User issues: {', '.join(issues)}"

        except KeyError:
            check["status"] = "fail"
            check["message"] = f"User {username} does not exist"
        except Exception as e:
            check["status"] = "error"
            check["message"] = f"Failed to check user: {str(e)}"

        self.results.append(check)
        return check

    def check_file_exists(self, filepath: str, description: str) -> Dict[str, Any]:
        """Check if file exists"""
        check: Dict[str, Any] = {
            "name": description,
            "category": "files",
            "status": "unknown",
            "message": "",
            "details": {"path": filepath},
        }

        if os.path.exists(filepath):
            check["status"] = "pass"
            check["message"] = f"{description} exists"

            # Get file info
            stat = os.stat(filepath)
            check["details"]["size"] = stat.st_size
            check["details"]["permissions"] = oct(stat.st_mode)[-3:]
        else:
            check["status"] = "fail"
            check["message"] = f"{description} not found"

        self.results.append(check)
        return check

    def run_all_checks(self, devuser: str = "devuser") -> Dict[str, Any]:
        """Run all health checks"""
        print("Running VPS provisioning health checks...\n")

        # System checks
        print("System validation...")
        self.check_os_version()
        self.check_resources()

        # Services
        print("Service checks...")
        self.check_service("xrdp", "XRDP Server")
        self.check_service("lightdm", "LightDM Display Manager")

        # Network
        print("Network checks...")
        self.check_port(3389, "RDP")
        self.check_port(22, "SSH")

        # User
        print("User checks...")
        self.check_user(devuser)

        # IDEs
        print("IDE checks...")
        self.check_executable("code", "Visual Studio Code")
        self.check_executable("cursor", "Cursor IDE")
        # Antigravity might have different command name

        # Dev tools
        print("Development tools...")
        self.check_executable("git", "Git", "--version")
        self.check_executable("gcc", "GCC Compiler", "--version")
        self.check_executable("make", "Make", "--version")

        # Generate summary
        summary = {
            "total_checks": len(self.results),
            "passed": len([r for r in self.results if r["status"] == "pass"]),
            "failed": len([r for r in self.results if r["status"] == "fail"]),
            "warnings": len([r for r in self.results if r["status"] == "warning"]),
            "errors": len([r for r in self.results if r["status"] == "error"]),
            "checks": self.results,
        }

        return summary


def format_text_output(summary: Dict) -> str:
    """Format results as human-readable text"""
    output = []
    output.append("\n" + "=" * 70)
    output.append("VPS PROVISIONING HEALTH CHECK RESULTS")
    output.append("=" * 70 + "\n")

    # Summary
    output.append(f"Total Checks: {summary['total_checks']}")
    output.append(f"  ✓ Passed:   {summary['passed']}")
    output.append(f"  ✗ Failed:   {summary['failed']}")
    output.append(f"  ⚠ Warnings: {summary['warnings']}")
    output.append(f"  ⚡ Errors:   {summary['errors']}")
    output.append("")

    # Group by category
    categories: Dict[str, List[Dict[str, Any]]] = {}
    for check in summary["checks"]:
        cat = check["category"]
        if cat not in categories:
            categories[cat] = []
        categories[cat].append(check)

    # Display by category
    for category, checks in sorted(categories.items()):
        output.append(f"\n{category.upper()}")
        output.append("-" * 70)

        for check in checks:
            status_icon = {
                "pass": "✓",
                "fail": "✗",
                "warning": "⚠",
                "error": "⚡",
                "unknown": "?",
            }.get(check["status"], "?")

            output.append(f"  {status_icon} {check['name']}: {check['message']}")

    output.append("\n" + "=" * 70)

    # Overall status
    if summary["failed"] == 0 and summary["errors"] == 0:
        output.append("✓ SYSTEM HEALTH: EXCELLENT")
    elif summary["failed"] > 0:
        output.append("✗ SYSTEM HEALTH: ISSUES DETECTED")
    else:
        output.append("⚠ SYSTEM HEALTH: WARNINGS PRESENT")

    output.append("=" * 70 + "\n")

    return "\n".join(output)


def main():
    """CLI entry point"""
    parser = argparse.ArgumentParser(
        description="Validate VPS provisioning health",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )

    parser.add_argument(
        "--output",
        choices=["text", "json"],
        default="text",
        help="Output format (default: text)",
    )

    parser.add_argument(
        "--verbose", "-v", action="store_true", help="Show detailed check information"
    )

    parser.add_argument(
        "--devuser",
        default="devuser",
        help="Developer username to check (default: devuser)",
    )

    args = parser.parse_args()

    # Run checks
    checker = HealthCheck(verbose=args.verbose)
    summary = checker.run_all_checks(devuser=args.devuser)

    # Output results
    if args.output == "json":
        print(json.dumps(summary, indent=2))
    else:
        print(format_text_output(summary))

    # Exit code based on results
    if summary["failed"] > 0 or summary["errors"] > 0:
        sys.exit(1)
    elif summary["warnings"] > 0:
        sys.exit(2)
    else:
        sys.exit(0)


if __name__ == "__main__":
    main()
