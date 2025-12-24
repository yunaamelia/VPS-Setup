#!/usr/bin/env python3
"""
credential-gen.py - Secure Password Generator

Generates cryptographically secure passwords meeting defined complexity requirements.
Implements SEC-001 (Password Complexity) and SEC-002 (CSPRNG Usage).

Requirements:
- Minimum length enforcement (16 chars)
- CSPRNG usage (secrets module)
- Complexity classes (low, medium, high)
"""

import argparse
import secrets
import string
import sys

def generate_password(length, complexity='high'):
    """
    Generate a secure password with specified length and complexity.
    """
    if length < 16:
        raise ValueError("Password length must be at least 16 characters (SEC-001)")

    # Define character sets
    lower = string.ascii_lowercase
    upper = string.ascii_uppercase
    digits = string.digits
    symbols = "!@#$%^&*()-_=+[]{}|;:,.<>?"
    
    # Base alphabet
    alphabet = lower + upper + digits
    
    if complexity == 'high':
        alphabet += symbols
    
    # Ensure minimum requirements are met for high complexity
    while True:
        password = ''.join(secrets.choice(alphabet) for _ in range(length))
        
        if complexity == 'high':
            # Check constraints
            has_lower = any(c in lower for c in password)
            has_upper = any(c in upper for c in password)
            has_digit = any(c in digits for c in password)
            has_symbol = any(c in symbols for c in password)
            
            # Require at least 2 of each class for robust security
            lower_count = sum(1 for c in password if c in lower)
            upper_count = sum(1 for c in password if c in upper)
            digit_count = sum(1 for c in password if c in digits)
            symbol_count = sum(1 for c in password if c in symbols)
            
            if (has_lower and has_upper and has_digit and has_symbol and
                lower_count >= 2 and upper_count >= 2 and digit_count >= 2 and symbol_count >= 2):
                return password
        else:
            # For lower complexity, just return valid length
            return password

def main():
    parser = argparse.ArgumentParser(description="Generate secure credentials (SEC-001, SEC-002)")
    parser.add_argument("--length", type=int, default=32, help="Password length (min 16)")
    parser.add_argument("--complexity", choices=['low', 'medium', 'high'], default='high', 
                        help="Password complexity level")
    
    args = parser.parse_args()
    
    try:
        password = generate_password(args.length, args.complexity)
        print(password)
        return 0
    except ValueError as e:
        print(f"Error: {e}", file=sys.stderr)
        return 1
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        return 1

if __name__ == "__main__":
    sys.exit(main())
