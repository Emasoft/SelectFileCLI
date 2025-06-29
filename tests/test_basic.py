#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""Basic tests for selectfilecli."""

import os
import sys
from pathlib import Path

# Add parent directory to path for imports
sys.path.insert(0, str(Path(__file__).parent.parent))


def test_import():
    """Test that the module can be imported."""
    try:
        from selectfilecli import select_file
        print("✓ Import test passed")
        return True
    except ImportError as e:
        print(f"✗ Import test failed: {e}")
        return False


def test_api_exists():
    """Test that the select_file function exists."""
    try:
        from selectfilecli import select_file
        assert hasattr(select_file, '__call__'), "select_file is not callable"
        print("✓ API exists test passed")
        return True
    except Exception as e:
        print(f"✗ API exists test failed: {e}")
        return False


def test_invalid_path():
    """Test that invalid path raises ValueError."""
    try:
        from selectfilecli import select_file
        try:
            select_file("/path/that/does/not/exist")
            print("✗ Invalid path test failed: No exception raised")
            return False
        except ValueError:
            print("✓ Invalid path test passed")
            return True
    except Exception as e:
        print(f"✗ Invalid path test failed with unexpected error: {e}")
        return False


def main():
    """Run all tests."""
    print("Running basic tests for selectfilecli...")
    print("-" * 50)
    
    tests = [
        test_import,
        test_api_exists,
        test_invalid_path,
    ]
    
    passed = 0
    for test in tests:
        if test():
            passed += 1
    
    print("-" * 50)
    print(f"Tests passed: {passed}/{len(tests)}")
    
    return passed == len(tests)


if __name__ == "__main__":
    success = main()
    sys.exit(0 if success else 1)