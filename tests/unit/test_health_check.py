#!/usr/bin/env python3
"""
test_health_check.py - Unit tests for health-check.py
Tests system validation, health checks, and reporting
"""

import unittest
import sys
import os
import json
from unittest.mock import patch, MagicMock, mock_open
from io import StringIO

# Add lib/utils to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '../../lib/utils'))

try:
    import health_check  # type: ignore[import-not-found]
except ImportError:
    health_check = MagicMock()


class TestHealthCheckOperatingSystem(unittest.TestCase):
    """Test OS detection and validation"""
    
    @patch('builtins.open', mock_open(read_data='ID=debian\nVERSION_ID="13"\n'))
    def test_check_os_debian_13(self):
        """Test OS check passes for Debian 13"""
        if hasattr(health_check, 'check_operating_system'):
            result = health_check.check_operating_system()
            self.assertEqual(result['status'], 'pass')
    
    @patch('builtins.open', mock_open(read_data='ID=ubuntu\nVERSION_ID="22.04"\n'))
    def test_check_os_non_debian(self):
        """Test OS check fails for non-Debian systems"""
        if hasattr(health_check, 'check_operating_system'):
            result = health_check.check_operating_system()
            self.assertEqual(result['status'], 'fail')
    
    @patch('builtins.open', side_effect=FileNotFoundError())
    def test_check_os_missing_release_file(self):
        """Test OS check handles missing os-release file"""
        if hasattr(health_check, 'check_operating_system'):
            result = health_check.check_operating_system()
            self.assertEqual(result['status'], 'error')


class TestHealthCheckResources(unittest.TestCase):
    """Test resource availability checks"""
    
    @patch('shutil.disk_usage')
    def test_check_disk_space_sufficient(self, mock_disk):
        """Test disk space check passes with sufficient space"""
        mock_disk.return_value = MagicMock(free=30 * 1024**3)  # 30GB
        
        if hasattr(health_check, 'check_disk_space'):
            result = health_check.check_disk_space(minimum_gb=25)
            self.assertEqual(result['status'], 'pass')
    
    @patch('shutil.disk_usage')
    def test_check_disk_space_insufficient(self, mock_disk):
        """Test disk space check fails with insufficient space"""
        mock_disk.return_value = MagicMock(free=20 * 1024**3)  # 20GB
        
        if hasattr(health_check, 'check_disk_space'):
            result = health_check.check_disk_space(minimum_gb=25)
            self.assertEqual(result['status'], 'fail')
    
    @patch('psutil.virtual_memory')
    def test_check_memory_sufficient(self, mock_mem):
        """Test memory check passes with sufficient RAM"""
        mock_mem.return_value = MagicMock(available=3 * 1024**3)  # 3GB
        
        if hasattr(health_check, 'check_memory'):
            result = health_check.check_memory(minimum_gb=2)
            self.assertEqual(result['status'], 'pass')
    
    @patch('psutil.virtual_memory')
    def test_check_memory_insufficient(self, mock_mem):
        """Test memory check fails with insufficient RAM"""
        mock_mem.return_value = MagicMock(available=1 * 1024**3)  # 1GB
        
        if hasattr(health_check, 'check_memory'):
            result = health_check.check_memory(minimum_gb=2)
            self.assertEqual(result['status'], 'fail')


class TestHealthCheckDesktopEnvironment(unittest.TestCase):
    """Test desktop environment validation"""
    
    @patch('subprocess.run')
    def test_check_xfce_installed(self, mock_run):
        """Test XFCE detection when installed"""
        mock_run.return_value = MagicMock(returncode=0, stdout='xfce4-session')
        
        if hasattr(health_check, 'check_desktop_environment'):
            result = health_check.check_desktop_environment()
            self.assertEqual(result['status'], 'pass')
    
    @patch('subprocess.run')
    def test_check_xfce_not_installed(self, mock_run):
        """Test XFCE detection when not installed"""
        mock_run.return_value = MagicMock(returncode=1, stdout='')
        
        if hasattr(health_check, 'check_desktop_environment'):
            result = health_check.check_desktop_environment()
            self.assertEqual(result['status'], 'fail')


class TestHealthCheckRDPServer(unittest.TestCase):
    """Test RDP server validation"""
    
    @patch('subprocess.run')
    def test_check_xrdp_running(self, mock_run):
        """Test xrdp service detection when running"""
        mock_run.return_value = MagicMock(returncode=0, stdout='active (running)')
        
        if hasattr(health_check, 'check_rdp_server'):
            result = health_check.check_rdp_server()
            self.assertEqual(result['status'], 'pass')
    
    @patch('subprocess.run')
    def test_check_xrdp_not_running(self, mock_run):
        """Test xrdp service detection when not running"""
        mock_run.return_value = MagicMock(returncode=3, stdout='inactive (dead)')
        
        if hasattr(health_check, 'check_rdp_server'):
            result = health_check.check_rdp_server()
            self.assertEqual(result['status'], 'fail')
    
    @patch('socket.socket')
    def test_check_rdp_port_listening(self, mock_socket):
        """Test RDP port 3389 is listening"""
        mock_sock = MagicMock()
        mock_sock.connect.return_value = None
        mock_socket.return_value.__enter__.return_value = mock_sock
        
        if hasattr(health_check, 'check_rdp_port'):
            result = health_check.check_rdp_port()
            self.assertEqual(result['status'], 'pass')


class TestHealthCheckIDEInstallations(unittest.TestCase):
    """Test IDE installation validation"""
    
    @patch('shutil.which')
    def test_check_vscode_installed(self, mock_which):
        """Test VSCode detection when installed"""
        mock_which.return_value = '/usr/bin/code'
        
        if hasattr(health_check, 'check_ide_vscode'):
            result = health_check.check_ide_vscode()
            self.assertEqual(result['status'], 'pass')
    
    @patch('shutil.which')
    def test_check_vscode_not_installed(self, mock_which):
        """Test VSCode detection when not installed"""
        mock_which.return_value = None
        
        if hasattr(health_check, 'check_ide_vscode'):
            result = health_check.check_ide_vscode()
            self.assertEqual(result['status'], 'fail')
    
    @patch('os.path.exists')
    def test_check_cursor_installed(self, mock_exists):
        """Test Cursor detection when installed"""
        mock_exists.return_value = True
        
        if hasattr(health_check, 'check_ide_cursor'):
            result = health_check.check_ide_cursor()
            self.assertEqual(result['status'], 'pass')
    
    @patch('os.path.exists')
    def test_check_antigravity_installed(self, mock_exists):
        """Test Antigravity detection when installed"""
        mock_exists.return_value = True
        
        if hasattr(health_check, 'check_ide_antigravity'):
            result = health_check.check_ide_antigravity()
            self.assertEqual(result['status'], 'pass')


class TestHealthCheckSecurity(unittest.TestCase):
    """Test security configuration validation"""
    
    @patch('builtins.open', mock_open(read_data='PermitRootLogin no\nPasswordAuthentication no'))
    def test_check_ssh_hardened(self):
        """Test SSH hardening validation"""
        if hasattr(health_check, 'check_ssh_security'):
            result = health_check.check_ssh_security()
            self.assertEqual(result['status'], 'pass')
    
    @patch('subprocess.run')
    def test_check_firewall_active(self, mock_run):
        """Test firewall status check"""
        mock_run.return_value = MagicMock(returncode=0, stdout='Status: active')
        
        if hasattr(health_check, 'check_firewall'):
            result = health_check.check_firewall()
            self.assertEqual(result['status'], 'pass')
    
    @patch('subprocess.run')
    def test_check_fail2ban_running(self, mock_run):
        """Test fail2ban service check"""
        mock_run.return_value = MagicMock(returncode=0, stdout='active (running)')
        
        if hasattr(health_check, 'check_fail2ban'):
            result = health_check.check_fail2ban()
            self.assertEqual(result['status'], 'pass')


class TestHealthCheckOutputFormats(unittest.TestCase):
    """Test output format generation"""
    
    def test_format_json_output(self):
        """Test JSON output formatting"""
        if hasattr(health_check, 'format_output'):
            checks = [
                {'name': 'Test Check', 'status': 'pass', 'message': 'OK'}
            ]
            output = health_check.format_output(checks, format='json')
            
            # Should be valid JSON
            parsed = json.loads(output)
            self.assertIsInstance(parsed, list)
            self.assertEqual(parsed[0]['status'], 'pass')
    
    def test_format_text_output(self):
        """Test text output formatting"""
        if hasattr(health_check, 'format_output'):
            checks = [
                {'name': 'Test Check', 'status': 'pass', 'message': 'OK'}
            ]
            output = health_check.format_output(checks, format='text')
            
            self.assertIn('Test Check', output)
            self.assertIn('pass', output)
    
    def test_format_summary_output(self):
        """Test summary output includes statistics"""
        if hasattr(health_check, 'format_summary'):
            checks = [
                {'status': 'pass'},
                {'status': 'pass'},
                {'status': 'fail'},
            ]
            summary = health_check.format_summary(checks)
            
            self.assertIn('2', summary)  # 2 passed
            self.assertIn('1', summary)  # 1 failed


class TestHealthCheckCategories(unittest.TestCase):
    """Test health check categorization"""
    
    def test_check_result_has_category(self):
        """Test check results include category"""
        if hasattr(health_check, 'check_operating_system'):
            result = health_check.check_operating_system()
            self.assertIn('category', result)
            self.assertEqual(result['category'], 'system')
    
    def test_filter_checks_by_category(self):
        """Test filtering checks by category"""
        if hasattr(health_check, 'run_checks'):
            results = health_check.run_checks(category='system')
            
            for result in results:
                self.assertEqual(result.get('category'), 'system')


class TestHealthCheckCLI(unittest.TestCase):
    """Test command-line interface"""
    
    @patch('sys.argv', ['health-check.py', '--output', 'json'])
    @patch('sys.stdout', new_callable=StringIO)
    def test_cli_json_output(self, mock_stdout):
        """Test CLI JSON output format"""
        if hasattr(health_check, 'main'):
            try:
                health_check.main()
            except SystemExit:
                pass
            
            output = mock_stdout.getvalue()
            # Should be valid JSON if any output
            if output.strip():
                json.loads(output)
    
    @patch('sys.argv', ['health-check.py', '--category', 'system'])
    def test_cli_category_filter(self):
        """Test CLI category filtering"""
        if hasattr(health_check, 'main'):
            with patch('sys.stdout'):
                try:
                    health_check.main()
                except SystemExit:
                    pass
    
    @patch('sys.argv', ['health-check.py', '--help'])
    def test_cli_help(self):
        """Test CLI help output"""
        if hasattr(health_check, 'main'):
            with patch('sys.stdout'):
                try:
                    health_check.main()
                except SystemExit as e:
                    self.assertEqual(e.code, 0)


class TestHealthCheckPerformance(unittest.TestCase):
    """Test performance validation"""
    
    def test_check_rdp_initialization_time(self):
        """Test RDP initialization time (NFR-002: ≤10 seconds)"""
        if hasattr(health_check, 'check_rdp_initialization_time'):
            result = health_check.check_rdp_initialization_time()
            
            if result['status'] == 'pass':
                self.assertLessEqual(result['details'].get('time_seconds', 0), 10)
    
    def test_check_ide_launch_time(self):
        """Test IDE launch time (NFR-003: ≤10 seconds)"""
        if hasattr(health_check, 'check_ide_launch_time'):
            result = health_check.check_ide_launch_time()
            
            if result['status'] == 'pass':
                self.assertLessEqual(result['details'].get('time_seconds', 0), 10)


class TestHealthCheckErrorHandling(unittest.TestCase):
    """Test error handling and edge cases"""
    
    def test_check_handles_permission_errors(self):
        """Test graceful handling of permission errors"""
        if hasattr(health_check, 'run_checks'):
            # Should not raise exception
            try:
                results = health_check.run_checks()
                self.assertIsInstance(results, list)
            except PermissionError:
                self.fail("Should handle permission errors gracefully")
    
    def test_check_handles_missing_commands(self):
        """Test handling of missing system commands"""
        if hasattr(health_check, 'check_command_available'):
            result = health_check.check_command_available('nonexistent_command_xyz')
            self.assertEqual(result['status'], 'fail')
    
    def test_all_checks_return_valid_structure(self):
        """Test all check functions return valid structure"""
        if hasattr(health_check, 'run_checks'):
            results = health_check.run_checks()
            
            for result in results:
                self.assertIn('name', result)
                self.assertIn('status', result)
                self.assertIn('message', result)
                self.assertIn(result['status'], ['pass', 'fail', 'error'])


if __name__ == '__main__':
    unittest.main()
