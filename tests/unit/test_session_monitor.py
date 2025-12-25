#!/usr/bin/env python3
"""
test_session_monitor.py - Unit tests for session-monitor.py
Tests RDP session resource monitoring and reporting
"""

import unittest
import subprocess
import sys
import os
import json
from unittest.mock import patch, MagicMock

# Import using importlib to handle hyphenated filenames
import importlib.util

# Load session-monitor module
spec = importlib.util.spec_from_file_location(
    "session_monitor",
    os.path.join(os.path.dirname(__file__), "../../lib/utils/session-monitor.py"),
)
if spec is None or spec.loader is None:
    raise ImportError("Failed to load session-monitor module")
session_monitor_module = importlib.util.module_from_spec(spec)
sys.modules["session_monitor"] = (
    session_monitor_module  # Register for @patch compatibility
)
spec.loader.exec_module(session_monitor_module)

SessionMonitor = session_monitor_module.SessionMonitor


class TestSessionMonitorInitialization(unittest.TestCase):
    """Test SessionMonitor initialization"""

    def test_create_monitor(self):
        """Test creating SessionMonitor instance"""
        monitor = SessionMonitor()
        self.assertIsInstance(monitor, SessionMonitor)
        self.assertEqual(monitor.MAX_MEMORY_MB, 4096)
        self.assertEqual(monitor.TARGET_SESSIONS, 3)


class TestSessionMonitorGetActiveSessions(unittest.TestCase):
    """Test active session detection"""

    @patch("subprocess.run")
    def test_get_active_sessions_with_xrdp(self, mock_run):
        """Test detecting active xrdp sessions"""
        # Mock ps aux output with Xorg processes
        ps_output = """USER       PID %CPU %MEM    VSZ   RSS TTY      STAT START   TIME COMMAND
root         1  0.0  0.1  12345  6789 ?        Ss   Dec24   0:00 /sbin/init
devuser   1234  2.5  5.2 234567 89012 ?        Sl   10:00   1:23 Xorg :10 -auth /var/run/xrdp/xrdp-sesman.auth
devuser   1235  1.8  4.1 198765 67890 ?        Sl   10:05   0:45 Xorg :11 -auth /var/run/xrdp/xrdp-sesman.auth"""

        mock_run.return_value = MagicMock(returncode=0, stdout=ps_output)

        monitor = SessionMonitor()
        sessions = monitor.get_active_sessions()

        # Should detect 2 sessions
        self.assertEqual(len(sessions), 2)
        self.assertEqual(sessions[0]["display"], ":10")
        self.assertEqual(sessions[1]["display"], ":11")
        self.assertEqual(sessions[0]["user"], "devuser")

    @patch("subprocess.run")
    def test_get_active_sessions_empty(self, mock_run):
        """Test when no xrdp sessions are active"""
        ps_output = """USER       PID %CPU %MEM    VSZ   RSS TTY      STAT START   TIME COMMAND
root         1  0.0  0.1  12345  6789 ?        Ss   Dec24   0:00 /sbin/init"""

        mock_run.return_value = MagicMock(returncode=0, stdout=ps_output)

        monitor = SessionMonitor()
        sessions = monitor.get_active_sessions()

        self.assertEqual(len(sessions), 0)

    @patch("subprocess.run")
    @patch("sys.stderr", new_callable=lambda: open(os.devnull, "w"))
    def test_get_active_sessions_error(self, mock_stderr, mock_run):
        """Test handling errors when getting sessions"""
        mock_run.side_effect = subprocess.CalledProcessError(1, "ps")

        monitor = SessionMonitor()
        sessions = monitor.get_active_sessions()

        # Should return empty list on error
        self.assertEqual(len(sessions), 0)


class TestSessionMonitorGetSystemMemory(unittest.TestCase):
    """Test system memory retrieval"""

    @patch("subprocess.run")
    def test_get_system_memory_success(self, mock_run):
        """Test getting system memory statistics"""
        free_output = """              total        used        free      shared  buff/cache   available
Mem:           4096        2048        1024          64        1024        1536
Swap:          2048           0        2048"""

        mock_run.return_value = MagicMock(returncode=0, stdout=free_output)

        monitor = SessionMonitor()
        mem_stats = monitor.get_system_memory()

        self.assertEqual(mem_stats["total_mb"], 4096.0)
        self.assertEqual(mem_stats["used_mb"], 2048.0)
        self.assertEqual(mem_stats["free_mb"], 1024.0)
        self.assertEqual(mem_stats["available_mb"], 1536.0)

    @patch("subprocess.run")
    @patch("sys.stderr", new_callable=lambda: open(os.devnull, "w"))
    def test_get_system_memory_error(self, mock_stderr, mock_run):
        """Test handling errors when getting memory stats"""
        mock_run.side_effect = subprocess.CalledProcessError(1, "free")

        monitor = SessionMonitor()
        mem_stats = monitor.get_system_memory()

        # Should return empty dict on error
        self.assertEqual(mem_stats, {})


class TestSessionMonitorCheckThresholds(unittest.TestCase):
    """Test resource threshold checking"""

    @patch("session_monitor.SessionMonitor.get_system_memory")
    @patch("session_monitor.SessionMonitor.get_active_sessions")
    def test_check_thresholds_within_limits(self, mock_sessions, mock_memory):
        """Test threshold check when resources are within limits"""
        # Mock system memory at 50% usage
        mock_memory.return_value = {
            "total_mb": 4096.0,
            "used_mb": 2048.0,
            "free_mb": 2048.0,
            "available_mb": 2048.0,
        }

        # Mock 2 sessions with normal memory usage
        mock_sessions.return_value = [
            {
                "display": ":10",
                "user": "user1",
                "pid": 1234,
                "memory_mb": 800.0,
                "memory_percent": 19.5,
            },
            {
                "display": ":11",
                "user": "user2",
                "pid": 1235,
                "memory_mb": 750.0,
                "memory_percent": 18.3,
            },
        ]

        monitor = SessionMonitor()
        result = monitor.check_thresholds(threshold_percent=75)

        self.assertTrue(result)

    @patch("session_monitor.SessionMonitor.get_system_memory")
    @patch("session_monitor.SessionMonitor.get_active_sessions")
    def test_check_thresholds_exceeds_system_memory(self, mock_sessions, mock_memory):
        """Test threshold check when system memory exceeds limit"""
        # Mock system memory at 80% usage (over 75% threshold)
        mock_memory.return_value = {
            "total_mb": 4096.0,
            "used_mb": 3276.8,
            "free_mb": 819.2,
            "available_mb": 819.2,
        }

        mock_sessions.return_value = []

        monitor = SessionMonitor()
        result = monitor.check_thresholds(threshold_percent=75)

        self.assertFalse(result)

    @patch("session_monitor.SessionMonitor.get_system_memory")
    @patch("session_monitor.SessionMonitor.get_active_sessions")
    def test_check_thresholds_exceeds_per_session(self, mock_sessions, mock_memory):
        """Test threshold check when a session exceeds expected memory"""
        mock_memory.return_value = {
            "total_mb": 4096.0,
            "used_mb": 2048.0,
            "free_mb": 2048.0,
            "available_mb": 2048.0,
        }

        # One session using 2GB (way over expected ~1GB)
        mock_sessions.return_value = [
            {
                "display": ":10",
                "user": "user1",
                "pid": 1234,
                "memory_mb": 2048.0,
                "memory_percent": 50.0,
            },
        ]

        monitor = SessionMonitor()
        result = monitor.check_thresholds(threshold_percent=75)

        # Should fail because session exceeds expected memory by >50%
        self.assertFalse(result)


class TestSessionMonitorGenerateReport(unittest.TestCase):
    """Test report generation"""

    @patch("session_monitor.SessionMonitor.check_thresholds")
    @patch("session_monitor.SessionMonitor.get_active_sessions")
    @patch("session_monitor.SessionMonitor.get_system_memory")
    def test_generate_report_json(self, mock_memory, mock_sessions, mock_check):
        """Test generating JSON report"""
        mock_memory.return_value = {
            "total_mb": 4096.0,
            "used_mb": 2048.0,
            "free_mb": 2048.0,
            "available_mb": 2048.0,
        }

        mock_sessions.return_value = [
            {
                "display": ":10",
                "user": "user1",
                "pid": 1234,
                "memory_mb": 800.0,
                "memory_percent": 19.5,
            },
        ]

        mock_check.return_value = True

        monitor = SessionMonitor()
        report = monitor.generate_report(output_json=True, threshold=75)

        # Should be valid JSON
        parsed = json.loads(report)
        self.assertIn("system_memory", parsed)
        self.assertIn("active_sessions", parsed)
        self.assertIn("thresholds_ok", parsed)
        self.assertTrue(parsed["thresholds_ok"])

    @patch("session_monitor.SessionMonitor.check_thresholds")
    @patch("session_monitor.SessionMonitor.get_active_sessions")
    @patch("session_monitor.SessionMonitor.get_system_memory")
    def test_generate_report_text(self, mock_memory, mock_sessions, mock_check):
        """Test generating human-readable report"""
        mock_memory.return_value = {
            "total_mb": 4096.0,
            "used_mb": 2048.0,
            "free_mb": 2048.0,
            "available_mb": 2048.0,
        }

        mock_sessions.return_value = [
            {
                "display": ":10",
                "user": "user1",
                "pid": 1234,
                "memory_mb": 800.0,
                "memory_percent": 19.5,
            },
        ]

        mock_check.return_value = True

        monitor = SessionMonitor()
        report = monitor.generate_report(output_json=False, threshold=75)

        # Should contain expected text
        self.assertIn("RDP Session Resource Monitor", report)
        self.assertIn("System Memory:", report)
        self.assertIn("Active RDP Sessions:", report)
        self.assertIn("Performance Targets", report)

    @patch("session_monitor.SessionMonitor.check_thresholds")
    @patch("session_monitor.SessionMonitor.get_active_sessions")
    @patch("session_monitor.SessionMonitor.get_system_memory")
    def test_generate_report_with_warnings(
        self, mock_memory, mock_sessions, mock_check
    ):
        """Test report shows warnings when thresholds exceeded"""
        mock_memory.return_value = {
            "total_mb": 4096.0,
            "used_mb": 3276.8,
            "free_mb": 819.2,
            "available_mb": 819.2,
        }

        mock_sessions.return_value = []
        mock_check.return_value = False

        monitor = SessionMonitor()
        report = monitor.generate_report(output_json=False, threshold=75)

        # Should show warning status
        self.assertIn("WARNING", report)
        self.assertIn("exceeds thresholds", report)


class TestSessionMonitorConstants(unittest.TestCase):
    """Test SessionMonitor constants and calculations"""

    def test_constants_defined(self):
        """Test that class constants are properly defined"""
        monitor = SessionMonitor()

        self.assertEqual(monitor.MAX_MEMORY_MB, 4096)
        self.assertEqual(monitor.TARGET_BUFFER_MB, 1024)
        self.assertEqual(monitor.TARGET_SESSIONS, 3)

        # Expected per session should be (4096 - 1024) / 3 = 1024MB
        expected_per_session = (4096 - 1024) / 3
        self.assertAlmostEqual(
            monitor.EXPECTED_PER_SESSION_MB, expected_per_session, places=1
        )


if __name__ == "__main__":
    unittest.main()
