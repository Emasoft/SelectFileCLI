#!/usr/bin/env python3
# -*- coding: utf-8 -*-
#
# Copyright (c) 2024-2025 Emasoft
# Licensed under the MIT License.
# See the LICENSE file in the project root for full license text.
#

# HERE IS THE CHANGELOG FOR THIS VERSION OF THE FILE:
# - Initial creation of visual snapshot tests for requirements verification
# - Added tests to visually verify header layout, button bar, and UI elements
# - Tests ensure visual consistency and proper rendering
#

"""Visual snapshot tests to verify UI requirements."""

from pathlib import Path
import pytest
from typing import Any


class TestVisualRequirements:
    """Visual snapshot tests for UI requirements."""

    def test_header_button_bar_layout(self, snap_compare: Any) -> None:
        """Test that header doesn't overlap button bar (Requirement 1)."""
        snapshot_app_path = Path(__file__).parent / "snapshot_apps" / "test_file_browser.py"
        assert snap_compare(snapshot_app_path, terminal_size=(80, 24))

    def test_path_display_visibility(self, snap_compare: Any) -> None:
        """Test path display is visible and styled correctly (Requirement 3)."""
        snapshot_app_path = Path(__file__).parent / "snapshot_apps" / "test_file_browser.py"
        # Navigate to show path updates
        assert snap_compare(snapshot_app_path, press=["enter", "down", "down"], terminal_size=(80, 24))

    def test_empty_folder_placeholder(self, snap_compare: Any) -> None:
        """Test empty folder shows <empty> placeholder (Requirement 4)."""
        snapshot_app_path = Path(__file__).parent / "snapshot_apps" / "test_empty_folder.py"
        # Expand root and navigate to empty folder
        assert snap_compare(
            snapshot_app_path,
            press=["enter", "down", "enter"],  # Expand root, select empty folder, expand it
            terminal_size=(80, 24),
        )

    def test_sort_dialog_appearance(self, snap_compare: Any) -> None:
        """Test sort dialog with OK/Cancel buttons (Requirement 7)."""
        snapshot_app_path = Path(__file__).parent / "snapshot_apps" / "test_file_browser.py"
        # Open sort dialog
        assert snap_compare(snapshot_app_path, press=["s"], terminal_size=(80, 24))

    def test_file_alignment_columns(self, snap_compare: Any) -> None:
        """Test directory entries are column-aligned (Requirement 8)."""
        snapshot_app_path = Path(__file__).parent / "snapshot_apps" / "test_aligned_files.py"
        # Expand to show files with different name lengths
        assert snap_compare(
            snapshot_app_path,
            press=["enter"],
            terminal_size=(100, 30),  # Wider to see alignment
        )

    def test_narrow_terminal_layout(self, snap_compare: Any) -> None:
        """Test layout in narrow terminal (Requirement 11 - resizing)."""
        snapshot_app_path = Path(__file__).parent / "snapshot_apps" / "test_file_browser.py"
        assert snap_compare(
            snapshot_app_path,
            terminal_size=(60, 20),  # Narrow terminal
        )

    def test_wide_terminal_layout(self, snap_compare: Any) -> None:
        """Test layout in wide terminal (Requirement 11 - resizing)."""
        snapshot_app_path = Path(__file__).parent / "snapshot_apps" / "test_file_browser.py"
        assert snap_compare(
            snapshot_app_path,
            terminal_size=(120, 35),  # Wide terminal
        )

    def test_loading_state_visual(self, snap_compare: Any) -> None:
        """Test loading indicator visibility (Requirements 5 & 6)."""
        # This would require a special snapshot app that simulates loading
        # For now, we'll skip as it requires async mocking
        pytest.skip("Loading state requires special async simulation")

    def test_navigation_buttons_visual(self, snap_compare: Any) -> None:
        """Test navigation buttons with emojis and underlines."""
        snapshot_app_path = Path(__file__).parent / "snapshot_apps" / "test_file_browser.py"
        # Focus on button bar area
        assert snap_compare(snapshot_app_path, terminal_size=(80, 24))

    def test_error_state_visual(self, snap_compare: Any) -> None:
        """Test error display in file browser."""
        snapshot_app_path = Path(__file__).parent / "snapshot_apps" / "test_error_state.py"
        assert snap_compare(snapshot_app_path, terminal_size=(80, 24))
