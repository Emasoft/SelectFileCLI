#!/usr/bin/env python3
# -*- coding: utf-8 -*-
#
# Copyright (c) 2024-2025 Emasoft
# Licensed under the MIT License.
# See the LICENSE file in the project root for full license text.
#

# HERE IS THE CHANGELOG FOR THIS VERSION OF THE FILE:
# - Added type annotations to all functions
#

"""Basic tests for selectfilecli."""

import os
import sys
from pathlib import Path

# Add parent directory to path for imports
sys.path.insert(0, str(Path(__file__).parent.parent))


def test_import() -> None:
    """Test that the module can be imported."""
    from selectfilecli import select_file

    assert select_file is not None


def test_api_exists() -> None:
    """Test that the select_file function exists."""
    from selectfilecli import select_file

    assert hasattr(select_file, "__call__"), "select_file is not callable"


def test_invalid_path() -> None:
    """Test that invalid path raises ValueError."""
    from selectfilecli import select_file
    import pytest

    with pytest.raises(ValueError):
        select_file("/path/that/does/not/exist")


def main() -> None:
    """Run tests using pytest."""
    import pytest

    # Run pytest on this file
    exit_code = pytest.main([__file__, "-v"])
    sys.exit(exit_code)


if __name__ == "__main__":
    main()
