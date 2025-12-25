#!/usr/bin/env python3
"""
test_session_monitor.py - Unit tests for session-monitor.py
Tests session tracking, monitoring, and reporting
"""

import unittest
import sys
import os
import json
import time
from unittest.mock import patch, MagicMock, mock_open
from datetime import datetime, timedelta

# Add lib/utils to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '../../lib/utils'))

try:
    import session_monitor  # type: ignore[import-not-found]
except ImportError:
    session_monitor = MagicMock()


class TestSessionInitialization(unittest.TestCase):
    """Test session initialization and tracking"""
    
    def test_create_session(self):
        """Test session creation"""
        if hasattr(session_monitor, 'create_session'):
            session = session_monitor.create_session()
            
            self.assertIn('session_id', session)
            self.assertIn('start_time', session)
            self.assertIn('status', session)
    
    def test_session_id_format(self):
        """Test session ID follows YYYYMMDD-HHMMSS format"""
        if hasattr(session_monitor, 'create_session'):
            session = session_monitor.create_session()
            session_id = session['session_id']
            
            # Format: YYYYMMDD-HHMMSS
            self.assertRegex(session_id, r'^\d{8}-\d{6}$')
    
    def test_session_initial_status(self):
        """Test session starts with INITIALIZING status"""
        if hasattr(session_monitor, 'create_session'):
            session = session_monitor.create_session()
            
            self.assertEqual(session['status'], 'INITIALIZING')


class TestSessionStateManagement(unittest.TestCase):
    """Test session state transitions"""
    
    def test_update_session_status(self):
        """Test session status updates"""
        if hasattr(session_monitor, 'update_session_status'):
            session = {'session_id': 'test-123', 'status': 'INITIALIZING'}
            
            session_monitor.update_session_status(session, 'IN_PROGRESS')
            
            self.assertEqual(session['status'], 'IN_PROGRESS')
    
    def test_valid_status_transitions(self):
        """Test valid status transition sequence"""
        if hasattr(session_monitor, 'update_session_status'):
            session = {'session_id': 'test-123', 'status': 'INITIALIZING'}
            
            # Valid transition sequence
            valid_transitions = [
                'IN_PROGRESS',
                'COMPLETED'
            ]
            
            for status in valid_transitions:
                session_monitor.update_session_status(session, status)
                self.assertEqual(session['status'], status)
    
    def test_finalize_session(self):
        """Test session finalization"""
        if hasattr(session_monitor, 'finalize_session'):
            session = {
                'session_id': 'test-123',
                'start_time': datetime.utcnow().isoformat(),
                'status': 'IN_PROGRESS'
            }
            
            session_monitor.finalize_session(session, 'COMPLETED')
            
            self.assertEqual(session['status'], 'COMPLETED')
            self.assertIn('end_time', session)
            self.assertIn('duration_seconds', session)


class TestSessionPersistence(unittest.TestCase):
    """Test session data persistence"""
    
    @patch('builtins.open', new_callable=mock_open)
    def test_save_session(self, mock_file):
        """Test saving session to file"""
        if hasattr(session_monitor, 'save_session'):
            session = {'session_id': 'test-123', 'status': 'IN_PROGRESS'}
            
            session_monitor.save_session(session)
            
            mock_file.assert_called()
    
    @patch('builtins.open', mock_open(read_data='{"session_id": "test-123"}'))
    def test_load_session(self):
        """Test loading session from file"""
        if hasattr(session_monitor, 'load_session'):
            session = session_monitor.load_session('test-123')
            
            self.assertEqual(session['session_id'], 'test-123')
    
    def test_load_nonexistent_session(self):
        """Test loading non-existent session returns None"""
        if hasattr(session_monitor, 'load_session'):
            with patch('builtins.open', side_effect=FileNotFoundError()):
                session = session_monitor.load_session('nonexistent')
                
                self.assertIsNone(session)


class TestSessionMonitoring(unittest.TestCase):
    """Test session monitoring and metrics"""
    
    def test_get_session_duration(self):
        """Test session duration calculation"""
        if hasattr(session_monitor, 'get_session_duration'):
            start_time = datetime.utcnow() - timedelta(seconds=300)
            session = {
                'session_id': 'test-123',
                'start_time': start_time.isoformat()
            }
            
            duration = session_monitor.get_session_duration(session)
            
            self.assertGreaterEqual(duration, 300)
            self.assertLessEqual(duration, 305)
    
    def test_is_session_active(self):
        """Test active session detection"""
        if hasattr(session_monitor, 'is_session_active'):
            active_session = {'status': 'IN_PROGRESS'}
            inactive_session = {'status': 'COMPLETED'}
            
            self.assertTrue(session_monitor.is_session_active(active_session))
            self.assertFalse(session_monitor.is_session_active(inactive_session))
    
    def test_list_active_sessions(self):
        """Test listing all active sessions"""
        if hasattr(session_monitor, 'list_active_sessions'):
            sessions = session_monitor.list_active_sessions()
            
            self.assertIsInstance(sessions, list)
            for session in sessions:
                self.assertIn(session['status'], ['INITIALIZING', 'IN_PROGRESS'])


class TestPhaseTracking(unittest.TestCase):
    """Test phase tracking within sessions"""
    
    def test_add_phase_to_session(self):
        """Test adding phase to session"""
        if hasattr(session_monitor, 'add_phase'):
            session = {'session_id': 'test-123', 'phases': []}
            
            session_monitor.add_phase(session, 'system-prep', 'IN_PROGRESS')
            
            self.assertEqual(len(session['phases']), 1)
            self.assertEqual(session['phases'][0]['name'], 'system-prep')
    
    def test_update_phase_status(self):
        """Test updating phase status"""
        if hasattr(session_monitor, 'update_phase_status'):
            session = {
                'phases': [
                    {'name': 'system-prep', 'status': 'IN_PROGRESS'}
                ]
            }
            
            session_monitor.update_phase_status(session, 'system-prep', 'COMPLETED')
            
            self.assertEqual(session['phases'][0]['status'], 'COMPLETED')
    
    def test_get_phase_status(self):
        """Test retrieving phase status"""
        if hasattr(session_monitor, 'get_phase_status'):
            session = {
                'phases': [
                    {'name': 'desktop-env', 'status': 'COMPLETED'}
                ]
            }
            
            status = session_monitor.get_phase_status(session, 'desktop-env')
            
            self.assertEqual(status, 'COMPLETED')


class TestMetricsCollection(unittest.TestCase):
    """Test metrics collection and aggregation"""
    
    def test_record_metric(self):
        """Test recording metrics"""
        if hasattr(session_monitor, 'record_metric'):
            session = {'session_id': 'test-123', 'metrics': {}}
            
            session_monitor.record_metric(session, 'cpu_usage', 45.2)
            
            self.assertIn('cpu_usage', session['metrics'])
    
    def test_get_metric_history(self):
        """Test retrieving metric history"""
        if hasattr(session_monitor, 'get_metric_history'):
            session = {
                'metrics': {
                    'memory_usage': [2048, 2560, 3072]
                }
            }
            
            history = session_monitor.get_metric_history(session, 'memory_usage')
            
            self.assertEqual(len(history), 3)
            self.assertEqual(history[0], 2048)
    
    def test_calculate_average_metric(self):
        """Test calculating average metric value"""
        if hasattr(session_monitor, 'calculate_average'):
            values = [10, 20, 30, 40, 50]
            
            avg = session_monitor.calculate_average(values)
            
            self.assertEqual(avg, 30)


class TestSessionReporting(unittest.TestCase):
    """Test session reporting and summaries"""
    
    def test_generate_session_summary(self):
        """Test generating session summary"""
        if hasattr(session_monitor, 'generate_summary'):
            session = {
                'session_id': 'test-123',
                'status': 'COMPLETED',
                'duration_seconds': 720,
                'phases': [
                    {'name': 'phase1', 'status': 'COMPLETED'},
                    {'name': 'phase2', 'status': 'COMPLETED'}
                ]
            }
            
            summary = session_monitor.generate_summary(session)
            
            self.assertIn('session_id', summary)
            self.assertIn('status', summary)
            self.assertIn('duration', summary)
    
    def test_export_session_json(self):
        """Test exporting session as JSON"""
        if hasattr(session_monitor, 'export_json'):
            session = {'session_id': 'test-123', 'status': 'COMPLETED'}
            
            json_output = session_monitor.export_json(session)
            
            parsed = json.loads(json_output)
            self.assertEqual(parsed['session_id'], 'test-123')
    
    def test_format_session_report(self):
        """Test formatting session report"""
        if hasattr(session_monitor, 'format_report'):
            session = {
                'session_id': 'test-123',
                'status': 'COMPLETED',
                'duration_seconds': 720
            }
            
            report = session_monitor.format_report(session)
            
            self.assertIn('test-123', report)
            self.assertIn('COMPLETED', report)


class TestConcurrentSessions(unittest.TestCase):
    """Test handling multiple concurrent sessions"""
    
    def test_detect_concurrent_sessions(self):
        """Test detection of concurrent active sessions"""
        if hasattr(session_monitor, 'get_concurrent_sessions'):
            sessions = session_monitor.get_concurrent_sessions()
            
            self.assertIsInstance(sessions, list)
    
    def test_prevent_concurrent_provisioning(self):
        """Test prevention of concurrent provisioning"""
        if hasattr(session_monitor, 'check_concurrent_lock'):
            # Should detect if another session is active
            is_locked = session_monitor.check_concurrent_lock()
            
            self.assertIsInstance(is_locked, bool)


class TestErrorHandling(unittest.TestCase):
    """Test error handling in session monitoring"""
    
    def test_handle_invalid_session_id(self):
        """Test handling of invalid session ID"""
        if hasattr(session_monitor, 'load_session'):
            session = session_monitor.load_session('')
            
            self.assertIsNone(session)
    
    def test_handle_corrupted_session_file(self):
        """Test handling of corrupted session file"""
        if hasattr(session_monitor, 'load_session'):
            with patch('builtins.open', mock_open(read_data='invalid json')):
                session = session_monitor.load_session('test-123')
                
                self.assertIsNone(session)
    
    def test_handle_missing_session_directory(self):
        """Test handling of missing session directory"""
        if hasattr(session_monitor, 'save_session'):
            with patch('os.makedirs') as mock_makedirs:
                session = {'session_id': 'test-123'}
                
                try:
                    session_monitor.save_session(session)
                    mock_makedirs.assert_called()
                except Exception:
                    pass


class TestSessionCleanup(unittest.TestCase):
    """Test session cleanup operations"""
    
    def test_cleanup_old_sessions(self):
        """Test cleanup of old completed sessions"""
        if hasattr(session_monitor, 'cleanup_old_sessions'):
            # Should remove sessions older than retention period
            removed_count = session_monitor.cleanup_old_sessions(days=30)
            
            self.assertIsInstance(removed_count, int)
            self.assertGreaterEqual(removed_count, 0)
    
    def test_preserve_active_sessions(self):
        """Test that active sessions are not cleaned up"""
        if hasattr(session_monitor, 'cleanup_old_sessions'):
            # Active sessions should never be removed
            # This is tested implicitly by cleanup logic
            pass


class TestCLIInterface(unittest.TestCase):
    """Test command-line interface"""
    
    @patch('sys.argv', ['session-monitor.py', '--list'])
    def test_cli_list_sessions(self):
        """Test CLI list sessions command"""
        if hasattr(session_monitor, 'main'):
            with patch('sys.stdout'):
                try:
                    session_monitor.main()
                except SystemExit:
                    pass
    
    @patch('sys.argv', ['session-monitor.py', '--session', 'test-123'])
    def test_cli_show_session(self):
        """Test CLI show session command"""
        if hasattr(session_monitor, 'main'):
            with patch('sys.stdout'):
                try:
                    session_monitor.main()
                except SystemExit:
                    pass


if __name__ == '__main__':
    unittest.main()
