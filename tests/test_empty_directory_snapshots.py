#!/usr/bin/env python3
# -*- coding: utf-8 -*-
#
# Copyright (c) 2024-2025 Emasoft
# Licensed under the MIT License.
# See the LICENSE file in the project root for full license text.
#

# HERE IS THE CHANGELOG FOR THIS VERSION OF THE FILE:
# - Created visual snapshot tests for empty directory display
#

"""Visual snapshot tests for empty directory display."""

import tempfile
from pathlib import Path
import pytest


class TestEmptyDirectorySnapshots:
    """Snapshot tests for empty directory display."""

    def test_empty_directory_snapshot(self, snap_compare):
        """Test visual appearance of empty directory display."""
        with tempfile.TemporaryDirectory() as tmpdir:
            test_dir = Path(tmpdir)

            # Create empty directories
            (test_dir / "empty_folder_1").mkdir()
            (test_dir / "empty_folder_2").mkdir()

            # Create a non-empty directory for comparison
            non_empty = test_dir / "non_empty_folder"
            non_empty.mkdir()
            (non_empty / "file.txt").write_text("test content")

            # Create the test app
            from selectfilecli.file_browser_app import FileBrowserApp

            app = FileBrowserApp(str(test_dir))

            # Simulate navigation to expand empty folder
            assert snap_compare(
                app,
                press=["down", "enter", "down", "enter"],  # Navigate and expand folders
                terminal_size=(80, 24),
            )
