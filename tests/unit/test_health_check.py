#!/usr/bin/env python3
"""
test_health_check.py - Unit tests for health-check.py
Tests system validation, health checks, and reporting
"""

import unittest
import sys
import os
from unittest.mock import patch, MagicMock, mock_open

# Import using importlib to handle hyphenated filenames
import importlib.util

# Load health-check module
spec = importlib.util.spec_from_file_location(
    "health_check",
    os.path.join(os.path.dirname(__file__), "../../lib/utils/health-check.py"),
)
if spec is None or spec.loader is None:
    raise ImportError("Failed to load health-check module")
health_check_module = importlib.util.module_from_spec(spec)
sys.modules["health_check"] = health_check_module  # Register for @patch compatibility
spec.loader.exec_module(health_check_module)

HealthCheck = health_check_module.HealthCheck
format_text_output = health_check_module.format_text_output


class TestHealthCheckOperatingSystem(unittest.TestCase):
    """Test OS detection and validation"""

    @patch(
        "builtins.open",
        mock_open(read_data='ID=debian\nNAME="Debian GNU/Linux"\nVERSION_ID="13"\n'),
    )
    def test_check_os_debian_13(self):
        """Test OS check passes for Debian 13"""
        checker = HealthCheck()
        result = checker.check_os_version()
        self.assertEqual(result["status"], "pass")
        self.assertEqual(result["category"], "system")

    @patch(
        "builtins.open",
        mock_open(read_data='ID=ubuntu\nNAME="Ubuntu"\nVERSION_ID="22.04"\n'),
    )
    def test_check_os_non_debian(self):
        """Test OS check fails for non-Debian systems"""
        checker = HealthCheck()
        result = checker.check_os_version()
        self.assertEqual(result["status"], "fail")

    @patch("builtins.open", side_effect=FileNotFoundError())
    def test_check_os_missing_release_file(self, mock_file):
        """Test OS check handles missing os-release file"""
        checker = HealthCheck()
        result = checker.check_os_version()
        self.assertEqual(result["status"], "error")


class TestHealthCheckResources(unittest.TestCase):
    """Test resource availability checks"""

    @patch("builtins.open", mock_open(read_data="MemTotal:       4194304 kB\n"))
    @patch("health_check.HealthCheck.run_command")
    def test_check_resources_sufficient(self, mock_run):
        """Test resource check passes with sufficient resources"""
        # Mock df output (disk space)
        df_output = (
            "Filesystem     1G-blocks  Used Available Use% Mounted on\n"
            "/dev/sda1             50G   10G       40G  20% /"
        )
        mock_run.return_value = (True, df_output, "")

        checker = HealthCheck()
        result = checker.check_resources()

        # Should have RAM and disk info
        self.assertIn("ram_mb", result["details"])
        self.assertEqual(result["category"], "system")

    @patch("builtins.open", mock_open(read_data="MemTotal:       1048576 kB\n"))
    @patch("health_check.HealthCheck.run_command")
    def test_check_resources_insufficient_ram(self, mock_run):
        """Test resource check fails with insufficient RAM"""
        # Mock df command to return valid data
        df_output = (
            "Filesystem     1G-blocks  Used Available Use% Mounted on\n"
            "/dev/sda1             50G   10G       40G  20% /"
        )
        mock_run.return_value = (True, df_output, "")

        checker = HealthCheck()
        result = checker.check_resources()

        # 1GB RAM should fail (minimum 2GB)
        self.assertEqual(result["status"], "fail")
        self.assertIn("RAM", result["message"])


class TestHealthCheckServices(unittest.TestCase):
    """Test service validation"""

    @patch("health_check.HealthCheck.run_command")
    def test_check_service_running(self, mock_run):
        """Test service check when service is active"""
        mock_run.return_value = (True, "active", "")

        checker = HealthCheck()
        result = checker.check_service("xrdp", "XRDP Server")

        self.assertEqual(result["status"], "pass")
        self.assertEqual(result["category"], "services")

    @patch("health_check.HealthCheck.run_command")
    def test_check_service_not_running(self, mock_run):
        """Test service check when service is inactive"""
        mock_run.return_value = (False, "inactive", "")

        checker = HealthCheck()
        result = checker.check_service("xrdp", "XRDP Server")

        self.assertEqual(result["status"], "fail")


class TestHealthCheckPorts(unittest.TestCase):
    """Test port availability checking"""

    @patch("socket.socket")
    def test_check_port_listening(self, mock_socket):
        """Test port check when port is listening"""
        mock_sock = MagicMock()
        mock_sock.connect_ex.return_value = 0  # Success
        mock_socket.return_value = mock_sock

        checker = HealthCheck()
        result = checker.check_port(3389, "RDP")

        self.assertEqual(result["status"], "pass")
        self.assertEqual(result["category"], "network")

    @patch("socket.socket")
    def test_check_port_not_listening(self, mock_socket):
        """Test port check when port is not listening"""
        mock_sock = MagicMock()
        mock_sock.connect_ex.return_value = 1  # Connection refused
        mock_socket.return_value = mock_sock

        checker = HealthCheck()
        result = checker.check_port(3389, "RDP")

        self.assertEqual(result["status"], "fail")


class TestHealthCheckExecutables(unittest.TestCase):
    """Test executable detection"""

    @patch("health_check.HealthCheck.run_command")
    def test_check_executable_installed(self, mock_run):
        """Test executable detection when installed"""
        # First call: which command succeeds
        # Second call: version command
        mock_run.side_effect = [
            (True, "/usr/bin/code", ""),
            (True, "Visual Studio Code 1.85.0", ""),
        ]

        checker = HealthCheck()
        result = checker.check_executable("code", "Visual Studio Code")

        self.assertEqual(result["status"], "pass")
        self.assertEqual(result["category"], "software")

    @patch("health_check.HealthCheck.run_command")
    def test_check_executable_not_installed(self, mock_run):
        """Test executable detection when not installed"""
        mock_run.return_value = (False, "", "not found")

        checker = HealthCheck()
        result = checker.check_executable("code", "Visual Studio Code")

        self.assertEqual(result["status"], "fail")


class TestHealthCheckUser(unittest.TestCase):
    """Test user account validation"""

    @patch("pwd.getpwnam")
    @patch("health_check.HealthCheck.run_command")
    def test_check_user_exists(self, mock_run, mock_pwd):
        """Test user check when user exists with correct config"""
        # Mock user info
        mock_user = MagicMock()
        mock_user.pw_uid = 1000
        mock_user.pw_gid = 1000
        mock_user.pw_dir = "/home/devuser"
        mock_user.pw_shell = "/bin/bash"
        mock_pwd.return_value = mock_user

        # Mock groups command
        mock_run.return_value = (True, "devuser : devuser sudo audio video", "")

        # Mock home directory exists
        with patch("os.path.isdir", return_value=True):
            checker = HealthCheck()
            result = checker.check_user("devuser")

            self.assertEqual(result["status"], "pass")
            self.assertEqual(result["category"], "users")

    @patch("pwd.getpwnam", side_effect=KeyError("User not found"))
    def test_check_user_not_exists(self, mock_pwd):
        """Test user check when user doesn't exist"""
        checker = HealthCheck()
        result = checker.check_user("nonexistent")

        self.assertEqual(result["status"], "fail")


class TestHealthCheckFileExists(unittest.TestCase):
    """Test file existence validation"""

    @patch("os.path.exists", return_value=True)
    @patch("os.stat")
    def test_check_file_exists(self, mock_stat, mock_exists):
        """Test file check when file exists"""
        mock_stat_result = MagicMock()
        mock_stat_result.st_size = 1024
        mock_stat_result.st_mode = 0o100644
        mock_stat.return_value = mock_stat_result

        checker = HealthCheck()
        result = checker.check_file_exists("/etc/test.conf", "Test Config")

        self.assertEqual(result["status"], "pass")
        self.assertEqual(result["category"], "files")

    @patch("os.path.exists", return_value=False)
    def test_check_file_not_exists(self, mock_exists):
        """Test file check when file doesn't exist"""
        checker = HealthCheck()
        result = checker.check_file_exists("/etc/missing.conf", "Missing Config")

        self.assertEqual(result["status"], "fail")


class TestHealthCheckRunAllChecks(unittest.TestCase):
    """Test comprehensive health check execution"""

    @patch("health_check.HealthCheck.check_os_version")
    @patch("health_check.HealthCheck.check_resources")
    @patch("health_check.HealthCheck.check_service")
    @patch("health_check.HealthCheck.check_port")
    @patch("health_check.HealthCheck.check_user")
    @patch("health_check.HealthCheck.check_executable")
    def test_run_all_checks(
        self, mock_exec, mock_user, mock_port, mock_service, mock_resources, mock_os
    ):
        """Test running all health checks"""
        # Mock all checks to return pass status
        mock_result = {"status": "pass", "message": "OK", "category": "test"}
        mock_os.return_value = mock_result
        mock_resources.return_value = mock_result
        mock_service.return_value = mock_result
        mock_port.return_value = mock_result
        mock_user.return_value = mock_result
        mock_exec.return_value = mock_result

        checker = HealthCheck()
        summary = checker.run_all_checks()

        # Should return summary with statistics
        self.assertIn("total_checks", summary)
        self.assertIn("passed", summary)
        self.assertIn("failed", summary)
        self.assertIn("checks", summary)


class TestOutputFormatting(unittest.TestCase):
    """Test output format generation"""

    def test_format_text_output(self):
        """Test text output formatting"""
        summary = {
            "total_checks": 3,
            "passed": 2,
            "failed": 1,
            "warnings": 0,
            "errors": 0,
            "checks": [
                {
                    "name": "Test 1",
                    "status": "pass",
                    "message": "OK",
                    "category": "system",
                },
                {
                    "name": "Test 2",
                    "status": "pass",
                    "message": "OK",
                    "category": "system",
                },
                {
                    "name": "Test 3",
                    "status": "fail",
                    "message": "Failed",
                    "category": "network",
                },
            ],
        }

        output = format_text_output(summary)

        # Check output contains expected elements
        self.assertIn("HEALTH CHECK RESULTS", output)
        self.assertIn("Total Checks: 3", output)
        self.assertIn("Passed:   2", output)
        self.assertIn("Failed:   1", output)


if __name__ == "__main__":
    unittest.main()
