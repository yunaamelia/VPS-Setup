#!/usr/bin/env python3
"""
Package Manager Utility
Advanced APT operations, dependency resolution, and package verification

Usage:
    python3 package-manager.py install <package_name>
    python3 package-manager.py verify <package_name>
    python3 package-manager.py resolve-deps <package_name>
    python3 package-manager.py list-upgradable
    python3 package-manager.py check-lock
    python3 package-manager.py check-repos
    python3 package-manager.py fix-broken
"""

import json
import os
import re
import subprocess
import sys
from typing import Any, Dict, List, Optional, Tuple

import psutil


class PackageManager:
    """Advanced APT package management operations"""

    LOCK_FILES = [
        "/var/lib/dpkg/lock",
        "/var/lib/dpkg/lock-frontend",
        "/var/cache/apt/archives/lock",
    ]

    def __init__(self):
        self.apt_cache_updated = False

    def check_stale_lock(self) -> Tuple[bool, List[str]]:
        """
        Check for stale lock files and attempt to release them

        Returns:
            Tuple of (has_stale_locks: bool, stale_files: List[str])
        """
        stale_locks = []

        for lock_file in self.LOCK_FILES:
            if not os.path.exists(lock_file):
                continue

            try:
                # Try to open lock file to check if process is holding it
                with open(f"{lock_file}.lock", "r", encoding="utf-8") as f:
                    pid = f.read().strip()

                    if pid and pid.isdigit():
                        try:
                            # Check if process is still running
                            process = psutil.Process(int(pid))
                            process_name = process.name()
                            print(
                                f"Lock file {lock_file} held by active process "
                                f"(PID: {pid}, name: {process_name})"
                            )
                        except psutil.NoSuchProcess:
                            # Process is dead, lock is stale
                            stale_locks.append(lock_file)
                            print(
                                f"Stale lock file detected: {lock_file} (PID {pid} not found)"
                            )
            except (FileNotFoundError, PermissionError):
                # No lock file or can't read it
                pass

        return (len(stale_locks) > 0, stale_locks)

    def release_stale_locks(self) -> bool:
        """
        Release stale lock files (requires root)

        Returns:
            True if locks were released, False otherwise
        """
        has_stale, stale_files = self.check_stale_lock()

        if not has_stale:
            return True

        if os.geteuid() != 0:
            print(
                "Error: Root privileges required to release lock files", file=sys.stderr
            )
            return False

        for lock_file in stale_files:
            try:
                os.remove(lock_file)
                print(f"Released stale lock: {lock_file}")
            except OSError as e:
                print(f"Failed to release {lock_file}: {e}", file=sys.stderr)
                return False

        # Run dpkg --configure -a to ensure consistent state
        try:
            subprocess.run(
                ["dpkg", "--configure", "-a"],
                capture_output=True,
                text=True,
                check=True,
            )
            print("Reconfigured packages after lock release")
        except subprocess.CalledProcessError as e:
            print(f"Warning: dpkg --configure failed: {e.stderr}", file=sys.stderr)

        return True

    def check_repository_connectivity(self) -> Dict[str, Any]:
        """
        Check connectivity to configured APT repositories

        Returns:
            Dict with repository check results
        """
        result: Dict[str, Any] = {
            "all_accessible": True,
            "repositories": [],
            "failures": [],
        }

        try:
            # Get list of repositories
            sources_result = subprocess.run(
                ["apt-cache", "policy"], capture_output=True, text=True, check=True
            )

            # Extract repository URLs
            repos = set()
            for line in sources_result.stdout.split("\n"):
                if line.strip().startswith("http"):
                    url = line.strip().split()[0]
                    repos.add(url)

            # Test connectivity to each repository
            for repo_url in repos:
                try:
                    # Try HTTP HEAD request to repository
                    test_result = subprocess.run(
                        [
                            "curl",
                            "-I",
                            "-s",
                            "-o",
                            "/dev/null",
                            "-w",
                            "%{http_code}",
                            repo_url,
                        ],
                        capture_output=True,
                        text=True,
                        timeout=10,
                        check=False,
                    )

                    http_code = test_result.stdout.strip()

                    if http_code.startswith("2") or http_code.startswith("3"):
                        result["repositories"].append(
                            {
                                "url": repo_url,
                                "accessible": True,
                                "http_code": http_code,
                            }
                        )
                    else:
                        result["all_accessible"] = False
                        result["failures"].append(repo_url)
                        result["repositories"].append(
                            {
                                "url": repo_url,
                                "accessible": False,
                                "http_code": http_code,
                            }
                        )

                except (subprocess.TimeoutExpired, subprocess.CalledProcessError) as e:
                    result["all_accessible"] = False
                    result["failures"].append(repo_url)
                    result["repositories"].append(
                        {"url": repo_url, "accessible": False, "error": str(e)}
                    )

        except subprocess.CalledProcessError as e:
            result["error"] = f"Failed to check repositories: {e.stderr}"

        return result

    def fix_broken_dependencies(self) -> Tuple[bool, str]:
        """
        Attempt to fix broken package dependencies

        Returns:
            Tuple of (success: bool, output: str)
        """
        try:
            # First, try apt-get --fix-broken install
            result = subprocess.run(
                ["apt-get", "--fix-broken", "install", "-y"],
                capture_output=True,
                text=True,
                check=True,
                env={"DEBIAN_FRONTEND": "noninteractive"},
            )

            return (True, result.stdout)

        except subprocess.CalledProcessError as e:
            # If that fails, try dpkg --configure -a
            try:
                subprocess.run(
                    ["dpkg", "--configure", "-a"],
                    capture_output=True,
                    text=True,
                    check=True,
                )

                # Try fix-broken again
                result = subprocess.run(
                    ["apt-get", "--fix-broken", "install", "-y"],
                    capture_output=True,
                    text=True,
                    check=True,
                    env={"DEBIAN_FRONTEND": "noninteractive"},
                )

                return (True, result.stdout)

            except subprocess.CalledProcessError as e2:
                return (False, f"Failed to fix dependencies: {e.stderr}\n{e2.stderr}")

    def update_cache(self, force: bool = False) -> bool:
        """Update APT package cache if not already updated"""
        if self.apt_cache_updated and not force:
            return True

        try:
            subprocess.run(
                ["apt-get", "update", "-qq"], capture_output=True, text=True, check=True
            )
            self.apt_cache_updated = True
            return True
        except subprocess.CalledProcessError as e:
            print(f"Error updating APT cache: {e.stderr}", file=sys.stderr)
            return False

    def install_package(
        self, package_name: str, auto_yes: bool = True
    ) -> Tuple[bool, str]:
        """
        Install a package with automatic yes and error handling

        Returns:
            Tuple of (success: bool, output: str)
        """
        self.update_cache()

        cmd = ["apt-get", "install"]
        if auto_yes:
            cmd.append("-y")
        cmd.append(package_name)

        try:
            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                check=True,
                env={"DEBIAN_FRONTEND": "noninteractive"},
            )
            return (True, result.stdout)
        except subprocess.CalledProcessError as e:
            error_msg = f"Failed to install {package_name}: {e.stderr}"
            return (False, error_msg)

    def verify_package(self, package_name: str) -> Dict[str, Any]:
        """
        Verify package installation and integrity

        Returns:
            Dict with verification results:
            {
                "installed": bool,
                "version": str or None,
                "files_intact": bool,
                "dependencies_met": bool
            }
        """
        result: Dict[str, Any] = {
            "installed": False,
            "version": None,
            "files_intact": None,
            "dependencies_met": False,
        }

        # Check if installed
        try:
            check_result = subprocess.run(
                ["dpkg", "-s", package_name], capture_output=True, text=True, check=True
            )

            result["installed"] = True

            # Extract version
            version_match = re.search(
                r"^Version:\s+(.+)$", check_result.stdout, re.MULTILINE
            )
            if version_match:
                result["version"] = version_match.group(1)

            # Check status
            status_match = re.search(
                r"^Status:\s+(.+)$", check_result.stdout, re.MULTILINE
            )
            if status_match and "installed" in status_match.group(1):
                result["files_intact"] = True

        except subprocess.CalledProcessError:
            return result

        # Check dependencies
        try:
            dep_result = subprocess.run(
                ["apt-cache", "depends", package_name],
                capture_output=True,
                text=True,
                check=True,
            )

            # Extract dependencies
            dependencies = []
            for line in dep_result.stdout.split("\n"):
                if line.strip().startswith("Depends:"):
                    dep = line.split("Depends:")[1].strip()
                    dependencies.append(dep)

            # Check if all dependencies are met
            all_deps_met = True
            for dep in dependencies:
                try:
                    subprocess.run(["dpkg", "-s", dep], capture_output=True, check=True)
                except subprocess.CalledProcessError:
                    all_deps_met = False
                    break

            result["dependencies_met"] = all_deps_met

        except subprocess.CalledProcessError:
            pass

        return result

    def resolve_dependencies(self, package_name: str) -> List[str]:
        """
        Resolve all dependencies for a package

        Returns:
            List of package names that are dependencies
        """
        self.update_cache()

        dependencies = []

        try:
            result = subprocess.run(
                [
                    "apt-cache",
                    "depends",
                    package_name,
                    "--recurse",
                    "--no-recommends",
                    "--no-suggests",
                    "--no-conflicts",
                    "--no-breaks",
                    "--no-replaces",
                    "--no-enhances",
                ],
                capture_output=True,
                text=True,
                check=True,
            )

            for line in result.stdout.split("\n"):
                # Parse dependency lines
                if line.strip() and not line.startswith(" "):
                    continue

                if "Depends:" in line:
                    dep = line.split("Depends:")[1].strip()
                    # Remove version constraints
                    dep = re.sub(r"\s*\(.*\)", "", dep)
                    if dep and dep not in dependencies:
                        dependencies.append(dep)

        except subprocess.CalledProcessError as e:
            print(f"Error resolving dependencies: {e.stderr}", file=sys.stderr)

        return dependencies

    def list_upgradable(self) -> List[Dict[str, str]]:
        """
        List all upgradable packages

        Returns:
            List of dicts with package info: [{"name": str, "current": str, "available": str}]
        """
        self.update_cache()

        upgradable = []

        try:
            result = subprocess.run(
                ["apt", "list", "--upgradable"],
                capture_output=True,
                text=True,
                check=True,
            )

            for line in result.stdout.split("\n"):
                if "/" not in line or line.startswith("Listing"):
                    continue

                # Parse: package/suite version arch [upgradable from: old_version]
                match = re.match(
                    r"^(\S+)/\S+\s+(\S+)\s+\S+\s+\[upgradable from:\s+(\S+)\]", line
                )
                if match:
                    upgradable.append(
                        {
                            "name": match.group(1),
                            "available": match.group(2),
                            "current": match.group(3),
                        }
                    )

        except subprocess.CalledProcessError as e:
            print(f"Error listing upgradable packages: {e.stderr}", file=sys.stderr)

        return upgradable

    def package_info(self, package_name: str) -> Optional[Dict[str, str]]:
        """
        Get detailed package information

        Returns:
            Dict with package details or None if not found
        """
        try:
            result = subprocess.run(
                ["apt-cache", "show", package_name],
                capture_output=True,
                text=True,
                check=True,
            )

            info = {}
            for line in result.stdout.split("\n"):
                if ":" in line:
                    key, value = line.split(":", 1)
                    info[key.strip()] = value.strip()

            return info

        except subprocess.CalledProcessError:
            return None


def main():
    """CLI entry point"""
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)

    pm = PackageManager()
    command = sys.argv[1]

    if command == "install" and len(sys.argv) >= 3:
        package = sys.argv[2]
        success, output = pm.install_package(package)
        if success:
            print(f"Successfully installed {package}")
            sys.exit(0)
        else:
            print(output, file=sys.stderr)
            sys.exit(1)

    elif command == "verify" and len(sys.argv) >= 3:
        package = sys.argv[2]
        result = pm.verify_package(package)
        print(json.dumps(result, indent=2))
        sys.exit(0 if result["installed"] else 1)

    elif command == "resolve-deps" and len(sys.argv) >= 3:
        package = sys.argv[2]
        deps = pm.resolve_dependencies(package)
        print(json.dumps(deps, indent=2))
        sys.exit(0)

    elif command == "list-upgradable":
        upgradable = pm.list_upgradable()
        print(json.dumps(upgradable, indent=2))
        sys.exit(0)

    elif command == "info" and len(sys.argv) >= 3:
        package = sys.argv[2]
        info = pm.package_info(package)
        if info:
            print(json.dumps(info, indent=2))
            sys.exit(0)
        else:
            print(f"Package not found: {package}", file=sys.stderr)
            sys.exit(1)

    elif command == "check-lock":
        has_stale, stale_files = pm.check_stale_lock()
        result = {"has_stale_locks": has_stale, "stale_files": stale_files}
        print(json.dumps(result, indent=2))
        sys.exit(1 if has_stale else 0)

    elif command == "release-locks":
        if pm.release_stale_locks():
            print("Lock files released successfully")
            sys.exit(0)
        else:
            print("Failed to release lock files", file=sys.stderr)
            sys.exit(1)

    elif command == "check-repos":
        result = pm.check_repository_connectivity()
        print(json.dumps(result, indent=2))
        sys.exit(0 if result["all_accessible"] else 1)

    elif command == "fix-broken":
        success, output = pm.fix_broken_dependencies()
        print(output)
        sys.exit(0 if success else 1)

    else:
        print(__doc__)
        sys.exit(1)


if __name__ == "__main__":
    main()
