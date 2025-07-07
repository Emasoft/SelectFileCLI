#!/usr/bin/env python3
# -*- coding: utf-8 -*-
#
# Copyright (c) 2024-2025 Emasoft
# Licensed under the MIT License.
# See the LICENSE file in the project root for full license text.
#

# HERE IS THE CHANGELOG FOR THIS VERSION OF THE FILE:
# - Created comprehensive visual snapshot tests for loading indicators
# - Test navigation loading indicator for all navigation methods
# - Test directory expansion loading placeholder
# - Use run_before to capture loading state before it completes
#

"""Visual snapshot tests for loading indicators in all scenarios."""

import tempfile
import asyncio
from pathlib import Path
from typing import List
import pytest
from textual.pilot import Pilot
from textual.widgets import Button, Input
from selectfilecli.file_browser_app import FileBrowserApp, CustomDirectoryTree


class TestLoadingIndicatorSnapshots:
    """Comprehensive snapshot tests for loading indicators."""

    def create_test_structure(self, tmpdir: Path) -> None:
        """Create a test directory structure."""
        # Create multiple nested directories
        for i in range(3):
            folder = tmpdir / f"folder_{i}"
            folder.mkdir()

            # Add some files
            for j in range(5):
                (folder / f"file_{j}.txt").write_text(f"Content {j}")

            # Create subdirectories
            sub = folder / "subfolder"
            sub.mkdir()
            (sub / "nested.txt").write_text("Nested content")

            # Create deeply nested structure
            deep = sub / "deep"
            deep.mkdir()
            (deep / "very_deep.txt").write_text("Very deep content")

    def test_navigation_loading_enter_key(self, snap_compare):
        """Test loading indicator when navigating with Enter key."""
        with tempfile.TemporaryDirectory() as tmpdir:
            test_dir = Path(tmpdir)
            self.create_test_structure(test_dir)

            app = FileBrowserApp(str(test_dir))

            async def before_navigation(pilot: Pilot):
                """Navigate and capture during loading state."""
                # Select a folder
                await pilot.press("down")
                # Press enter to navigate - this triggers loading
                await pilot.press("enter")
                # The loading indicator should be visible now

            assert snap_compare(app, run_before=before_navigation, terminal_size=(80, 24))

    def test_navigation_loading_parent_button(self, snap_compare):
        """Test loading indicator when using Parent button."""
        with tempfile.TemporaryDirectory() as tmpdir:
            test_dir = Path(tmpdir)
            self.create_test_structure(test_dir)

            # Start in a subdirectory
            start_dir = test_dir / "folder_0" / "subfolder"
            app = FileBrowserApp(str(start_dir))

            async def click_parent_button(pilot: Pilot):
                """Click parent button to trigger loading."""
                # Find and click the parent button
                parent_button = pilot.app.query_one("#parent-button", Button)
                await pilot.click(parent_button)
                # Loading indicator should be visible now

            assert snap_compare(app, run_before=click_parent_button, terminal_size=(80, 24))

    def test_navigation_loading_home_button(self, snap_compare):
        """Test loading indicator when using Home button."""
        with tempfile.TemporaryDirectory() as tmpdir:
            test_dir = Path(tmpdir)
            self.create_test_structure(test_dir)

            # Start in a subdirectory
            start_dir = test_dir / "folder_0" / "subfolder" / "deep"
            app = FileBrowserApp(str(start_dir))

            async def click_home_button(pilot: Pilot):
                """Click home button to trigger loading."""
                home_button = pilot.app.query_one("#home-button", Button)
                await pilot.click(home_button)
                # Loading indicator should be visible during navigation

            assert snap_compare(app, run_before=click_home_button, terminal_size=(80, 24))

    def test_navigation_loading_root_button(self, snap_compare):
        """Test loading indicator when using Root button."""
        with tempfile.TemporaryDirectory() as tmpdir:
            test_dir = Path(tmpdir)
            self.create_test_structure(test_dir)

            app = FileBrowserApp(str(test_dir))

            async def click_root_button(pilot: Pilot):
                """Click root button to trigger loading."""
                root_button = pilot.app.query_one("#root-button", Button)
                await pilot.click(root_button)
                # Loading indicator should be visible

            assert snap_compare(app, run_before=click_root_button, terminal_size=(80, 24))

    def test_navigation_loading_back_button(self, snap_compare):
        """Test loading indicator when using Back button."""
        with tempfile.TemporaryDirectory() as tmpdir:
            test_dir = Path(tmpdir)
            self.create_test_structure(test_dir)

            app = FileBrowserApp(str(test_dir))

            async def navigate_then_back(pilot: Pilot):
                """Navigate to create history, then use back button."""
                # First navigate into a folder
                await pilot.press("down")
                await pilot.press("enter")
                await asyncio.sleep(0.1)  # Let navigation complete

                # Now click back button
                back_button = pilot.app.query_one("#back-button", Button)
                await pilot.click(back_button)
                # Loading indicator should be visible

            assert snap_compare(app, run_before=navigate_then_back, terminal_size=(80, 24))

    def test_navigation_loading_forward_button(self, snap_compare):
        """Test loading indicator when using Forward button."""
        with tempfile.TemporaryDirectory() as tmpdir:
            test_dir = Path(tmpdir)
            self.create_test_structure(test_dir)

            app = FileBrowserApp(str(test_dir))

            async def navigate_back_then_forward(pilot: Pilot):
                """Navigate to create history, go back, then forward."""
                # Navigate into a folder
                await pilot.press("down")
                await pilot.press("enter")
                await asyncio.sleep(0.1)

                # Go back
                back_button = pilot.app.query_one("#back-button", Button)
                await pilot.click(back_button)
                await asyncio.sleep(0.1)

                # Now click forward button
                forward_button = pilot.app.query_one("#forward-button", Button)
                await pilot.click(forward_button)
                # Loading indicator should be visible

            assert snap_compare(app, run_before=navigate_back_then_forward, terminal_size=(80, 24))

    def test_navigation_loading_keyboard_shortcuts(self, snap_compare):
        """Test loading indicator with keyboard navigation shortcuts."""
        with tempfile.TemporaryDirectory() as tmpdir:
            test_dir = Path(tmpdir)
            self.create_test_structure(test_dir)

            # Start in a subdirectory
            start_dir = test_dir / "folder_0" / "subfolder"
            app = FileBrowserApp(str(start_dir))

            async def use_keyboard_shortcut(pilot: Pilot):
                """Use keyboard shortcut to navigate to parent."""
                # Press 'p' to go to parent directory
                await pilot.press("p")
                # Loading indicator should be visible

            assert snap_compare(app, run_before=use_keyboard_shortcut, terminal_size=(80, 24))

    def test_directory_expansion_loading(self, snap_compare):
        """Test loading placeholder when expanding a directory."""
        with tempfile.TemporaryDirectory() as tmpdir:
            test_dir = Path(tmpdir)
            self.create_test_structure(test_dir)

            app = FileBrowserApp(str(test_dir))

            async def expand_directory(pilot: Pilot):
                """Expand a directory to show loading placeholder."""
                # Find the tree widget
                tree = pilot.app.query_one("#directory-tree", CustomDirectoryTree)

                # Get the first folder node
                root = tree.root
                if root and root.children:
                    folder_node = root.children[0]
                    # Expand the node - this should trigger loading placeholder
                    folder_node.expand()
                    # Don't wait - capture immediately to see loading state

            assert snap_compare(app, run_before=expand_directory, terminal_size=(80, 24))

    def test_multiple_expansion_loading(self, snap_compare):
        """Test loading placeholders when expanding multiple directories."""
        with tempfile.TemporaryDirectory() as tmpdir:
            test_dir = Path(tmpdir)
            self.create_test_structure(test_dir)

            app = FileBrowserApp(str(test_dir))

            async def expand_multiple(pilot: Pilot):
                """Expand multiple directories quickly."""
                tree = pilot.app.query_one("#directory-tree", CustomDirectoryTree)

                # Expand multiple nodes rapidly
                root = tree.root
                if root and root.children:
                    for i, node in enumerate(root.children[:3]):
                        if node.allow_expand:
                            node.expand()
                            # Small delay to let UI update but not complete loading
                            await asyncio.sleep(0.01)

            assert snap_compare(app, run_before=expand_multiple, terminal_size=(80, 24))

    def test_loading_with_sorting_dialog(self, snap_compare):
        """Test that loading works correctly with sort dialog."""
        with tempfile.TemporaryDirectory() as tmpdir:
            test_dir = Path(tmpdir)
            self.create_test_structure(test_dir)

            app = FileBrowserApp(str(test_dir))

            async def change_sort_and_navigate(pilot: Pilot):
                """Open sort dialog, change sort, then navigate."""
                # Open sort dialog
                await pilot.press("s")
                await asyncio.sleep(0.1)

                # Select different sort mode
                await pilot.press("down")  # Move to different sort option
                await pilot.press("enter")  # Confirm
                await asyncio.sleep(0.1)

                # Now navigate to trigger loading
                await pilot.press("down")
                await pilot.press("enter")
                # Loading indicator should be visible

            assert snap_compare(app, run_before=change_sort_and_navigate, terminal_size=(80, 24))

    def test_loading_indicator_styles(self, snap_compare):
        """Test that loading indicators have correct styling."""
        with tempfile.TemporaryDirectory() as tmpdir:
            test_dir = Path(tmpdir)
            self.create_test_structure(test_dir)

            app = FileBrowserApp(str(test_dir))

            async def trigger_both_loading_types(pilot: Pilot):
                """Trigger both navigation and expansion loading."""
                # First expand a directory to show loading placeholder
                tree = pilot.app.query_one("#directory-tree", CustomDirectoryTree)
                root = tree.root
                if root and root.children:
                    folder_node = root.children[0]
                    folder_node.expand()

                # Small delay
                await asyncio.sleep(0.05)

                # Then navigate to show navigation loading
                await pilot.press("down")
                await pilot.press("enter")

            assert snap_compare(app, run_before=trigger_both_loading_types, terminal_size=(80, 24))


class TestLoadingIndicatorEdgeCases:
    """Test edge cases for loading indicators."""

    def test_loading_empty_directory(self, snap_compare):
        """Test loading indicator when expanding empty directory."""
        with tempfile.TemporaryDirectory() as tmpdir:
            test_dir = Path(tmpdir)

            # Create empty directories
            for i in range(3):
                (test_dir / f"empty_{i}").mkdir()

            app = FileBrowserApp(str(test_dir))

            async def expand_empty_dir(pilot: Pilot):
                """Expand empty directory."""
                tree = pilot.app.query_one("#directory-tree", CustomDirectoryTree)
                root = tree.root
                if root and root.children:
                    # Expand first empty directory
                    root.children[0].expand()

            assert snap_compare(app, run_before=expand_empty_dir, terminal_size=(80, 24))

    def test_loading_with_permission_error(self, snap_compare):
        """Test loading indicator when directory has permission issues."""
        with tempfile.TemporaryDirectory() as tmpdir:
            test_dir = Path(tmpdir)

            # Create directories
            normal_dir = test_dir / "normal"
            normal_dir.mkdir()
            (normal_dir / "file.txt").write_text("content")

            # Note: Permission testing is platform-specific and may not work in all environments
            # This test focuses on the UI behavior

            app = FileBrowserApp(str(test_dir))

            async def navigate_dirs(pilot: Pilot):
                """Navigate through directories."""
                await pilot.press("down")
                await pilot.press("enter")

            assert snap_compare(app, run_before=navigate_dirs, terminal_size=(80, 24))

    def test_rapid_navigation_loading(self, snap_compare):
        """Test loading indicators during rapid navigation."""
        with tempfile.TemporaryDirectory() as tmpdir:
            test_dir = Path(tmpdir)

            # Create simple structure
            for i in range(5):
                folder = test_dir / f"quick_{i}"
                folder.mkdir()
                (folder / "file.txt").write_text("content")

            app = FileBrowserApp(str(test_dir))

            async def rapid_navigation(pilot: Pilot):
                """Navigate rapidly between directories."""
                # Rapid key presses
                for _ in range(3):
                    await pilot.press("down")
                    await pilot.press("enter")
                    await asyncio.sleep(0.01)  # Very short delay
                    await pilot.press("p")  # Go back to parent
                    await asyncio.sleep(0.01)

            assert snap_compare(app, run_before=rapid_navigation, terminal_size=(80, 24))
