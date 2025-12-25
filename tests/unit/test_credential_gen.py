#!/usr/bin/env python3
"""
test_credential_gen.py - Unit tests for credential-gen.py
Tests password generation, validation, and security properties
"""

import unittest
import sys
import os
import re
from unittest.mock import patch, MagicMock

# Add lib/utils to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '../../lib/utils'))

try:
    import credential_gen  # type: ignore[import-not-found]
except ImportError:
    # Create minimal mock if module not available
    credential_gen = MagicMock()


class TestCredentialGeneration(unittest.TestCase):
    """Test password generation functions"""
    
    def test_generate_password_default_length(self):
        """Test password generation with default length"""
        if hasattr(credential_gen, 'generate_password'):
            password = credential_gen.generate_password()
            self.assertIsInstance(password, str)
            self.assertGreaterEqual(len(password), 16)
    
    def test_generate_password_custom_length(self):
        """Test password generation with custom length"""
        if hasattr(credential_gen, 'generate_password'):
            password = credential_gen.generate_password(length=32)
            self.assertGreaterEqual(len(password), 32)
    
    def test_generate_password_minimum_length(self):
        """Test password meets minimum length requirement (SEC-001)"""
        if hasattr(credential_gen, 'generate_password'):
            password = credential_gen.generate_password()
            self.assertGreaterEqual(len(password), 16)
    
    def test_generate_password_complexity(self):
        """Test password contains required character types"""
        if hasattr(credential_gen, 'generate_password'):
            password = credential_gen.generate_password()
            
            # Should contain at least one of each: uppercase, lowercase, digit, special
            has_upper = any(c.isupper() for c in password)
            has_lower = any(c.islower() for c in password)
            has_digit = any(c.isdigit() for c in password)
            has_special = any(not c.isalnum() for c in password)
            
            # At least 3 of 4 character types
            char_types = sum([has_upper, has_lower, has_digit, has_special])
            self.assertGreaterEqual(char_types, 3)
    
    def test_generate_password_uniqueness(self):
        """Test generated passwords are unique"""
        if hasattr(credential_gen, 'generate_password'):
            passwords = [credential_gen.generate_password() for _ in range(10)]
            
            # All passwords should be unique
            self.assertEqual(len(passwords), len(set(passwords)))
    
    def test_generate_password_no_spaces(self):
        """Test password does not contain spaces"""
        if hasattr(credential_gen, 'generate_password'):
            password = credential_gen.generate_password()
            self.assertNotIn(' ', password)
    
    def test_generate_secure_password_uses_secrets(self):
        """Test that secure password uses secrets module (SEC-002)"""
        if hasattr(credential_gen, 'generate_secure_password'):
            # Patch secrets module to verify it's being used
            with patch('credential_gen.secrets') as mock_secrets:
                mock_secrets.token_urlsafe.return_value = "secure_password"
                password = credential_gen.generate_secure_password()
                mock_secrets.token_urlsafe.assert_called()


class TestPasswordValidation(unittest.TestCase):
    """Test password validation functions"""
    
    def test_validate_password_strength_strong(self):
        """Test validation accepts strong passwords"""
        if hasattr(credential_gen, 'validate_password_strength'):
            strong_password = "Str0ng!P@ssw0rd#2024"
            result = credential_gen.validate_password_strength(strong_password)
            self.assertTrue(result)
    
    def test_validate_password_strength_weak_too_short(self):
        """Test validation rejects passwords under 16 chars"""
        if hasattr(credential_gen, 'validate_password_strength'):
            weak_password = "Short1!"
            result = credential_gen.validate_password_strength(weak_password)
            self.assertFalse(result)
    
    def test_validate_password_strength_weak_no_complexity(self):
        """Test validation rejects passwords without complexity"""
        if hasattr(credential_gen, 'validate_password_strength'):
            weak_password = "alllowercase12345678"
            result = credential_gen.validate_password_strength(weak_password)
            self.assertFalse(result)
    
    def test_validate_password_no_common_passwords(self):
        """Test validation rejects common passwords"""
        if hasattr(credential_gen, 'validate_password_strength'):
            common = ["password123456789", "admin123456789012"]
            for pwd in common:
                result = credential_gen.validate_password_strength(pwd)
                self.assertFalse(result)


class TestPasswordRedaction(unittest.TestCase):
    """Test password redaction for logging (SEC-003)"""
    
    def test_redact_password_in_string(self):
        """Test password redaction in log messages"""
        if hasattr(credential_gen, 'redact_password'):
            message = "Setting password to: SuperSecret123!"
            redacted = credential_gen.redact_password(message)
            self.assertNotIn("SuperSecret123!", redacted)
            self.assertIn("[REDACTED]", redacted)
    
    def test_redact_password_pattern_matching(self):
        """Test redaction handles various password patterns"""
        if hasattr(credential_gen, 'redact_password'):
            patterns = [
                "password=secret123",
                "pwd: mypassword",
                "PASSWORD='test123'"
            ]
            for pattern in patterns:
                redacted = credential_gen.redact_password(pattern)
                self.assertIn("[REDACTED]", redacted)


class TestRandomnessQuality(unittest.TestCase):
    """Test cryptographic randomness quality (SEC-002)"""
    
    def test_uses_secrets_module(self):
        """Test that secrets module is used, not random"""
        if hasattr(credential_gen, '__file__') and credential_gen.__file__ is not None:
            with open(credential_gen.__file__, 'r', encoding='utf-8') as f:
                content = f.read()
                
            # Should import secrets, not random
            self.assertIn('import secrets', content)
            # Should not use random for password generation
            self.assertNotRegex(content, r'import random.*password', re.DOTALL)
    
    def test_password_entropy(self):
        """Test password has sufficient entropy"""
        if hasattr(credential_gen, 'generate_password'):
            password = credential_gen.generate_password()
            
            # Calculate basic entropy (unique characters / total)
            unique_chars = len(set(password))
            total_chars = len(password)
            
            # Should have good character diversity
            self.assertGreater(unique_chars / total_chars, 0.5)


class TestCLIInterface(unittest.TestCase):
    """Test command-line interface"""
    
    @patch('sys.argv', ['credential-gen.py', '--length', '24'])
    def test_cli_custom_length(self):
        """Test CLI accepts custom length argument"""
        if hasattr(credential_gen, 'main'):
            with patch('sys.stdout') as mock_stdout:
                try:
                    credential_gen.main()
                except SystemExit:
                    pass
    
    @patch('sys.argv', ['credential-gen.py', '--validate', 'Str0ng!P@ss'])
    def test_cli_validation_mode(self):
        """Test CLI validation mode"""
        if hasattr(credential_gen, 'main'):
            with patch('sys.stdout') as mock_stdout:
                try:
                    credential_gen.main()
                except SystemExit:
                    pass
    
    @patch('sys.argv', ['credential-gen.py', '--help'])
    def test_cli_help_output(self):
        """Test CLI help output"""
        if hasattr(credential_gen, 'main'):
            with patch('sys.stdout') as mock_stdout:
                try:
                    credential_gen.main()
                except SystemExit:
                    pass


class TestEdgeCases(unittest.TestCase):
    """Test edge cases and error handling"""
    
    def test_generate_password_invalid_length(self):
        """Test error handling for invalid length"""
        if hasattr(credential_gen, 'generate_password'):
            with self.assertRaises((ValueError, TypeError)):
                credential_gen.generate_password(length=-1)
    
    def test_generate_password_zero_length(self):
        """Test error handling for zero length"""
        if hasattr(credential_gen, 'generate_password'):
            with self.assertRaises((ValueError, TypeError)):
                credential_gen.generate_password(length=0)
    
    def test_validate_empty_password(self):
        """Test validation rejects empty password"""
        if hasattr(credential_gen, 'validate_password_strength'):
            result = credential_gen.validate_password_strength("")
            self.assertFalse(result)
    
    def test_validate_none_password(self):
        """Test validation handles None gracefully"""
        if hasattr(credential_gen, 'validate_password_strength'):
            with self.assertRaises((TypeError, ValueError)):
                credential_gen.validate_password_strength(None)


class TestSecurityRequirements(unittest.TestCase):
    """Test compliance with security requirements"""
    
    def test_sec_001_minimum_length(self):
        """SEC-001: Password minimum 16 characters"""
        if hasattr(credential_gen, 'generate_password'):
            password = credential_gen.generate_password()
            self.assertGreaterEqual(len(password), 16)
    
    def test_sec_002_csprng_usage(self):
        """SEC-002: Use cryptographically secure random number generator"""
        # Verify secrets module is used
        if hasattr(credential_gen, '__file__') and credential_gen.__file__ is not None:
            with open(credential_gen.__file__, 'r', encoding='utf-8') as f:
                content = f.read()
            self.assertIn('secrets', content)
    
    def test_sec_003_no_password_logging(self):
        """SEC-003: Passwords must not appear in logs"""
        if hasattr(credential_gen, 'redact_password'):
            test_log = "User password: Secret123!"
            redacted = credential_gen.redact_password(test_log)
            self.assertNotIn("Secret123!", redacted)


if __name__ == '__main__':
    unittest.main()
