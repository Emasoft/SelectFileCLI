#!/usr/bin/env python3
# -*- coding: utf-8 -*-
#
# Copyright (c) 2024-2025 Emasoft
# Licensed under the MIT License.
# See the LICENSE file in the project root for full license text.
#

# HERE IS THE CHANGELOG FOR THIS VERSION OF THE FILE:
# - Created snapshot tests with artificial delays to ensure loading indicators are captured
# - Mock slow filesystem operations to make loading states visible
# - Test all navigation and expansion scenarios with guaranteed visibility
#

"""Snapshot tests with delays to ensure loading indicators are visible."""

import tempfile
import asyncio
import time
from pathlib import Path
from unittest.mock import patch, MagicMock
import pytest
from textual.pilot import Pilot
from selectfilecli.file_browser_app import FileBrowserApp, CustomDirectoryTree


class TestLoadingSnapshotsWithDelay:
    """Snapshot tests with delays to guarantee loading indicator visibility."""

    @pytest.fixture
    def slow_listdir(self):
        """Mock os.listdir to add delay."""
        import os
        original_listdir = os.listdir
        
        def delayed_listdir(path):
            """Add delay to directory listing."""
            # Add 0.3 second delay to make loading visible
            time.sleep(0.3)
            return original_listdir(path)
        
        with patch('os.listdir', side_effect=delayed_listdir):
            yield

    @pytest.fixture
    def slow_path_operations(self):
        """Mock Path operations to add delays."""
        original_iterdir = Path.iterdir
        original_is_dir = Path.is_dir
        original_stat = Path.stat
        
        def delayed_iterdir(self):
            """Add delay to directory iteration."""
            time.sleep(0.2)
            return original_iterdir(self)
        
        def delayed_is_dir(self):
            """Add small delay to is_dir checks."""
            time.sleep(0.05)
            return original_is_dir(self)
        
        def delayed_stat(self, *args, **kwargs):
            """Add small delay to stat calls."""
            time.sleep(0.05)
            return original_stat(self, *args, **kwargs)
        
        with patch.object(Path, 'iterdir', delayed_iterdir), \
             patch.object(Path, 'is_dir', delayed_is_dir), \
             patch.object(Path, 'stat', delayed_stat):
            yield

    def create_test_structure(self, tmpdir: Path) -> None:
        """Create test directory structure."""
        for i in range(4):
            folder = tmpdir / f"slow_folder_{i}"
            folder.mkdir()
            
            for j in range(3):
                (folder / f"file_{j}.txt").write_text(f"Content {j}")
            
            sub = folder / "subfolder"
            sub.mkdir()
            (sub / "nested.txt").write_text("Nested")

    def test_navigation_loading_visible_enter(self, snap_compare, slow_listdir):
        """Test navigation loading is visible when pressing Enter."""
        with tempfile.TemporaryDirectory() as tmpdir:
            test_dir = Path(tmpdir)
            self.create_test_structure(test_dir)
            
            app = FileBrowserApp(str(test_dir))
            
            async def navigate_with_enter(pilot: Pilot):
                """Navigate and capture loading state."""
                await pilot.press("down")
                await pilot.press("enter")
                # With slow_listdir, loading should be visible
                await asyncio.sleep(0.1)  # Capture during loading
                
            assert snap_compare(
                app,
                run_before=navigate_with_enter,
                terminal_size=(80, 24)
            )

    def test_navigation_loading_visible_parent(self, snap_compare, slow_listdir):
        """Test parent navigation loading is visible."""
        with tempfile.TemporaryDirectory() as tmpdir:
            test_dir = Path(tmpdir)
            self.create_test_structure(test_dir)
            
            start_dir = test_dir / "slow_folder_0" / "subfolder"
            app = FileBrowserApp(str(start_dir))
            
            async def go_to_parent(pilot: Pilot):
                """Navigate to parent with loading visible."""
                await pilot.press("p")  # Parent shortcut
                await asyncio.sleep(0.1)  # Capture during loading
                
            assert snap_compare(
                app,
                run_before=go_to_parent,
                terminal_size=(80, 24)
            )

    def test_expansion_loading_placeholder_visible(self, snap_compare, slow_path_operations):
        """Test directory expansion loading placeholder is visible."""
        with tempfile.TemporaryDirectory() as tmpdir:
            test_dir = Path(tmpdir)
            self.create_test_structure(test_dir)
            
            app = FileBrowserApp(str(test_dir))
            
            async def expand_with_loading(pilot: Pilot):
                """Expand directory and capture loading placeholder."""
                tree = pilot.app.query_one("#directory-tree", CustomDirectoryTree)
                
                # Get first expandable node
                root = tree.root
                if root and root.children:
                    for node in root.children:
                        if node.allow_expand:
                            # Expand node
                            node.expand()
                            # Immediately capture - loading placeholder should be visible
                            break
                
                # Very short delay to let UI update
                await asyncio.sleep(0.05)
                
            assert snap_compare(
                app,
                run_before=expand_with_loading,
                terminal_size=(80, 24)
            )

    def test_multiple_loading_indicators(self, snap_compare, slow_path_operations):
        """Test multiple loading indicators at once."""
        with tempfile.TemporaryDirectory() as tmpdir:
            test_dir = Path(tmpdir)
            self.create_test_structure(test_dir)
            
            app = FileBrowserApp(str(test_dir))
            
            async def expand_multiple_slow(pilot: Pilot):
                """Expand multiple directories to show multiple loading indicators."""
                tree = pilot.app.query_one("#directory-tree", CustomDirectoryTree)
                
                root = tree.root
                if root and root.children:
                    # Expand first three directories rapidly
                    for i, node in enumerate(root.children[:3]):
                        if node.allow_expand:
                            node.expand()
                            await asyncio.sleep(0.02)  # Very short delay between expansions
                
                # Capture while loading placeholders are visible
                await asyncio.sleep(0.05)
                
            assert snap_compare(
                app,
                run_before=expand_multiple_slow,
                terminal_size=(80, 24)
            )

    def test_loading_indicator_blinking_style(self, snap_compare, slow_listdir):
        """Test that loading indicator has correct blinking style."""
        with tempfile.TemporaryDirectory() as tmpdir:
            test_dir = Path(tmpdir)
            self.create_test_structure(test_dir)
            
            app = FileBrowserApp(str(test_dir))
            
            async def trigger_styled_loading(pilot: Pilot):
                """Trigger loading to check styling."""
                # First expand a directory
                tree = pilot.app.query_one("#directory-tree", CustomDirectoryTree)
                if tree.root and tree.root.children:
                    tree.root.children[0].expand()
                
                await asyncio.sleep(0.05)
                
                # Then navigate
                await pilot.press("down")
                await pilot.press("enter")
                await asyncio.sleep(0.1)
                
            assert snap_compare(
                app,
                run_before=trigger_styled_loading,
                terminal_size=(80, 24)
            )


class TestLoadingSnapshotsAllButtons:
    """Test loading indicators for all navigation buttons with delays."""

    @pytest.fixture
    def slow_filesystem(self):
        """Make all filesystem operations slow."""
        import os
        original_listdir = os.listdir
        
        def slow_listdir(path):
            time.sleep(0.4)  # Significant delay
            return original_listdir(path)
        
        with patch('os.listdir', side_effect=slow_listdir):
            yield

    def create_nested_structure(self, tmpdir: Path) -> Path:
        """Create deeply nested structure for navigation tests."""
        # Create nested path: tmpdir/level1/level2/level3
        level1 = tmpdir / "level1"
        level1.mkdir()
        (level1 / "file1.txt").write_text("Level 1")
        
        level2 = level1 / "level2"
        level2.mkdir()
        (level2 / "file2.txt").write_text("Level 2")
        
        level3 = level2 / "level3"
        level3.mkdir()
        (level3 / "file3.txt").write_text("Level 3")
        
        return level3  # Return deepest directory

    def test_back_button_loading(self, snap_compare, slow_filesystem):
        """Test Back button shows loading indicator."""
        with tempfile.TemporaryDirectory() as tmpdir:
            test_dir = Path(tmpdir)
            deepest = self.create_nested_structure(test_dir)
            
            app = FileBrowserApp(str(test_dir))
            
            async def use_back_button(pilot: Pilot):
                """Navigate forward then use back button."""
                # Navigate into directories
                await pilot.press("down")
                await pilot.press("enter")
                await asyncio.sleep(0.5)  # Let it load
                
                # Click back button
                back_btn = pilot.app.query_one("#back-button")
                await pilot.click(back_btn)
                await asyncio.sleep(0.1)  # Capture during loading
                
            assert snap_compare(
                app,
                run_before=use_back_button,
                terminal_size=(80, 24)
            )

    def test_forward_button_loading(self, snap_compare, slow_filesystem):
        """Test Forward button shows loading indicator."""
        with tempfile.TemporaryDirectory() as tmpdir:
            test_dir = Path(tmpdir)
            self.create_nested_structure(test_dir)
            
            app = FileBrowserApp(str(test_dir))
            
            async def use_forward_button(pilot: Pilot):
                """Navigate, go back, then forward."""
                # Navigate in
                await pilot.press("down")
                await pilot.press("enter")
                await asyncio.sleep(0.5)
                
                # Go back
                await pilot.press("alt+left")
                await asyncio.sleep(0.5)
                
                # Click forward button
                forward_btn = pilot.app.query_one("#forward-button")
                await pilot.click(forward_btn)
                await asyncio.sleep(0.1)  # Capture during loading
                
            assert snap_compare(
                app,
                run_before=use_forward_button,
                terminal_size=(80, 24)
            )

    def test_parent_button_loading(self, snap_compare, slow_filesystem):
        """Test Parent button shows loading indicator."""
        with tempfile.TemporaryDirectory() as tmpdir:
            test_dir = Path(tmpdir)
            deepest = self.create_nested_structure(test_dir)
            
            # Start in deep directory
            app = FileBrowserApp(str(deepest))
            
            async def use_parent_button(pilot: Pilot):
                """Click parent button."""
                parent_btn = pilot.app.query_one("#parent-button")
                await pilot.click(parent_btn)
                await asyncio.sleep(0.1)  # Capture during loading
                
            assert snap_compare(
                app,
                run_before=use_parent_button,
                terminal_size=(80, 24)
            )

    def test_home_button_loading(self, snap_compare, slow_filesystem):
        """Test Home button shows loading indicator."""
        with tempfile.TemporaryDirectory() as tmpdir:
            test_dir = Path(tmpdir)
            deepest = self.create_nested_structure(test_dir)
            
            # Start in deep directory
            app = FileBrowserApp(str(deepest))
            
            async def use_home_button(pilot: Pilot):
                """Click home button."""
                home_btn = pilot.app.query_one("#home-button")
                await pilot.click(home_btn)
                await asyncio.sleep(0.1)  # Capture during loading
                
            assert snap_compare(
                app,
                run_before=use_home_button,
                terminal_size=(80, 24)
            )

    def test_root_button_loading(self, snap_compare, slow_filesystem):
        """Test Root button shows loading indicator."""
        with tempfile.TemporaryDirectory() as tmpdir:
            test_dir = Path(tmpdir)
            deepest = self.create_nested_structure(test_dir)
            
            # Start in deep directory
            app = FileBrowserApp(str(deepest))
            
            async def use_root_button(pilot: Pilot):
                """Click root button."""
                root_btn = pilot.app.query_one("#root-button")
                await pilot.click(root_btn)
                await asyncio.sleep(0.1)  # Capture during loading
                
            assert snap_compare(
                app,
                run_before=use_root_button,
                terminal_size=(80, 24)
            )

    def test_all_navigation_methods(self, snap_compare, slow_filesystem):
        """Test snapshot showing various loading states."""
        with tempfile.TemporaryDirectory() as tmpdir:
            test_dir = Path(tmpdir)
            self.create_nested_structure(test_dir)
            
            # Add more folders at root
            for i in range(5):
                folder = test_dir / f"folder_{i}"
                folder.mkdir()
                (folder / "content.txt").write_text(f"Folder {i}")
            
            app = FileBrowserApp(str(test_dir))
            
            async def multiple_navigations(pilot: Pilot):
                """Perform multiple navigation actions."""
                # Expand some directories
                tree = pilot.app.query_one("#directory-tree", CustomDirectoryTree)
                if tree.root and tree.root.children:
                    # Expand first two
                    tree.root.children[0].expand()
                    await asyncio.sleep(0.02)
                    tree.root.children[1].expand()
                
                # Navigate into a directory
                await asyncio.sleep(0.02)
                await pilot.press("down")
                await pilot.press("down")
                await pilot.press("enter")
                
                # Capture during multiple loading states
                await asyncio.sleep(0.1)
                
            assert snap_compare(
                app,
                run_before=multiple_navigations,
                terminal_size=(80, 24)
            )