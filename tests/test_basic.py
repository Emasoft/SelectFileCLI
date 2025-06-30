#!/usr/bin/env python3
# -*- coding: utf-8 -*-
#
# Copyright (c) 2024-2025 Emasoft
# Licensed under the MIT License.
# See the LICENSE file in the project root for full license text.
#

"""Basic tests for selectfilecli."""

import os
import sys
from pathlib import Path

# Add parent directory to path for imports
sys.path.insert(0, str(Path(__file__).parent.parent))


def test_import():
    """Test that the module can be imported."""
    from selectfilecli import select_file
    assert select_file is not None


def test_api_exists():
    """Test that the select_file function exists."""
    from selectfilecli import select_file
    assert hasattr(select_file, "__call__"), "select_file is not callable"


def test_invalid_path():
    """Test that invalid path raises ValueError."""
    from selectfilecli import select_file
    import pytest
    
    with pytest.raises(ValueError):
        select_file("/path/that/does/not/exist")


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
