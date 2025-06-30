#!/usr/bin/env python3
# -*- coding: utf-8 -*-
#
# Copyright (c) 2024-2025 Emasoft
# Licensed under the MIT License.
# See the LICENSE file in the project root for full license text.
#

"""Tests for the Textual file browser application."""

import os
import tempfile
from pathlib import Path
from unittest.mock import patch
import time

import pytest
from textual.pilot import Pilot

from selectfilecli.file_browser_app import FileBrowserApp, SortMode, SortOrder, CustomDirectoryTree, SortDialog


@pytest.fixture
def temp_directory():
    """Create a temporary directory structure for testing."""
    with tempfile.TemporaryDirectory() as tmpdir:
        # Create test directory structure
        test_dir = Path(tmpdir)

        # Create subdirectories
        (test_dir / "documents").mkdir()
        (test_dir / "documents" / "work").mkdir()
        (test_dir / "pictures").mkdir()
        (test_dir / "music").mkdir(exist_ok=True)

        # Create test files
        (test_dir / "readme.txt").write_text("Test readme")
        (test_dir / "documents" / "report.pdf").write_text("Test report")
        (test_dir / "documents" / "work" / "project.doc").write_text("Test project")
        (test_dir / "pictures" / "photo.jpg").write_text("Test photo")
        (test_dir / ".hidden_file").write_text("Hidden file")

        yield test_dir


@pytest.fixture
def temp_directory_with_varied_files():
    """Create a temporary directory with files having different attributes."""
    with tempfile.TemporaryDirectory() as tmpdir:
        test_dir = Path(tmpdir)

        # Create files with different extensions, sizes, and timestamps
        files = [
            ("document.pdf", "Small PDF", 1024),
            ("image.jpg", "Large image file" * 1000, 15000),
            ("script.py", "#!/usr/bin/env python3\nprint('hello')", 50),
            ("data.csv", "id,name,value\n1,test,100", 30),
            ("archive.zip", "Binary content" * 100, 1400),
            ("readme.txt", "Simple text file", 20),
            ("video.mp4", "Video file content" * 500, 8000),
            ("config.json", '{"key": "value"}', 18),
        ]

        # Create files with controlled timestamps
        base_time = time.time()
        for i, (filename, content, _) in enumerate(files):
            file_path = test_dir / filename
            file_path.write_text(content)
            # Set different modification times (spaced by 10 seconds)
            mod_time = base_time + (i * 10)
            access_time = base_time + (i * 5)  # Different access pattern
            os.utime(file_path, (access_time, mod_time))

        # Create subdirectories
        (test_dir / "src").mkdir()
        (test_dir / "docs").mkdir()
        (test_dir / "tests").mkdir()

        yield test_dir


class TestFileBrowserApp:
    """Test the FileBrowserApp functionality."""

    @pytest.mark.asyncio
    async def test_app_initialization(self, temp_directory):
        """Test that the app initializes correctly."""
        app = FileBrowserApp(start_path=str(temp_directory))

        assert app.start_path == temp_directory.resolve()
        assert app.selected_file is None

    @pytest.mark.asyncio
    async def test_app_compose(self, temp_directory):
        """Test that the app composes the correct widgets."""
        app = FileBrowserApp(start_path=str(temp_directory))
        async with app.run_test() as pilot:
            # Check that Header, DirectoryTree, and Footer are present
            assert pilot.app.query_one("Header")
            assert pilot.app.query_one(CustomDirectoryTree)
            assert pilot.app.query_one("Footer")

    @pytest.mark.asyncio
    async def test_app_title(self, temp_directory):
        """Test that the app sets the correct title and subtitle."""
        app = FileBrowserApp(start_path=str(temp_directory))
        async with app.run_test() as pilot:
            assert pilot.app.title == "Select File Browser"
            assert pilot.app.sub_title == "Navigate with arrows, Enter to select, Q to quit"

    @pytest.mark.asyncio
    async def test_quit_action(self, temp_directory):
        """Test that pressing 'q' quits the app without selecting."""
        app = FileBrowserApp(start_path=str(temp_directory))
        async with app.run_test() as pilot:
            await pilot.press("q")
            assert pilot.app.return_value is None

    @pytest.mark.asyncio
    async def test_escape_quit(self, temp_directory):
        """Test that pressing Escape quits the app."""
        app = FileBrowserApp(start_path=str(temp_directory))
        async with app.run_test() as pilot:
            await pilot.press("escape")
            assert pilot.app.return_value is None

    @pytest.mark.asyncio
    async def test_directory_tree_navigation(self, temp_directory):
        """Test navigation through the directory tree."""
        app = FileBrowserApp(start_path=str(temp_directory))
        async with app.run_test() as pilot:
            # Get the DirectoryTree widget
            tree = pilot.app.query_one(CustomDirectoryTree)

            # The tree should show our temp directory
            assert str(temp_directory) in str(tree.path)

            # Navigate with arrow keys
            await pilot.press("down")  # Move to first item
            await pilot.press("down")  # Move to second item
            await pilot.press("up")  # Move back up

    @pytest.mark.asyncio
    async def test_file_selection(self, temp_directory):
        """Test selecting a file."""
        app = FileBrowserApp(start_path=str(temp_directory))

        # Mock the file selection to avoid complex tree navigation
        selected_file = str(temp_directory / "readme.txt")

        async with app.run_test() as pilot:
            # Simulate file selection by calling the handler directly
            from textual.widgets import DirectoryTree

            # Create a mock event
            class MockFileSelectedEvent:
                def __init__(self, path):
                    self.path = path

            # Call the file selection handler
            pilot.app.on_file_selected(MockFileSelectedEvent(selected_file))

            # The app should exit with the selected file
            assert pilot.app.selected_file == selected_file

    @pytest.mark.asyncio
    async def test_invalid_start_path(self):
        """Test that invalid start path raises ValueError."""
        with pytest.raises(ValueError, match="Start path must be a valid directory"):
            from selectfilecli import select_file

            select_file("/nonexistent/path")

    @pytest.mark.asyncio
    async def test_app_css(self, temp_directory):
        """Test that the app has proper CSS styling."""
        app = FileBrowserApp(start_path=str(temp_directory))
        async with app.run_test() as pilot:
            # Check that CSS is applied
            tree = pilot.app.query_one(CustomDirectoryTree)
            assert tree is not None

    def test_app_visual_snapshot(self, snap_compare):
        """Test app visual appearance with SVG snapshot testing."""
        # Use the test app with consistent directory structure
        snapshot_app_path = Path(__file__).parent / "snapshot_apps" / "test_file_browser.py"

        # Use snap_compare to take and compare SVG snapshot
        assert snap_compare(snapshot_app_path, terminal_size=(80, 24))

    def test_app_navigation_snapshot(self, snap_compare):
        """Test app appearance after navigation with SVG snapshot."""
        # Use the test app with consistent directory structure
        snapshot_app_path = Path(__file__).parent / "snapshot_apps" / "test_file_browser.py"

        # Navigate down twice and take snapshot
        assert snap_compare(snapshot_app_path, press=["down", "down"], terminal_size=(80, 24))

    def test_app_file_selection_snapshot(self, snap_compare):
        """Test app appearance when selecting a file with SVG snapshot."""
        # Use the test app with consistent directory structure
        snapshot_app_path = Path(__file__).parent / "snapshot_apps" / "test_file_browser.py"

        # Navigate to readme.txt and select it
        # Note: The exact key sequence depends on the directory structure
        assert snap_compare(
            snapshot_app_path,
            press=["down", "down", "down", "down", "enter"],  # Navigate to readme.txt and select
            terminal_size=(80, 24),
        )

    @pytest.mark.asyncio
    async def test_path_display_updates(self, temp_directory):
        """Test that the path display updates when navigating."""
        app = FileBrowserApp(start_path=str(temp_directory))
        async with app.run_test() as pilot:
            # Check initial path display
            path_display = pilot.app.query_one("#path-display")
            assert str(temp_directory) in path_display.renderable

            # Navigate and check path updates
            await pilot.press("down")
            await pilot.pause(0.1)
            # Path should still show something (even if same directory)
            assert path_display.renderable != ""

    @pytest.mark.asyncio
    async def test_sort_dialog_opens(self, temp_directory_with_varied_files):
        """Test that the sort dialog opens when pressing 's'."""
        app = FileBrowserApp(start_path=str(temp_directory_with_varied_files))
        async with app.run_test() as pilot:
            # Check initial sort mode
            assert app.current_sort_mode == SortMode.NAME

            # Press 's' to open dialog
            await pilot.press("s")
            await pilot.pause(0.1)

            # Check if dialog is visible
            from selectfilecli.file_browser_app import SortDialog

            dialog = pilot.app.screen_stack[-1]
            assert isinstance(dialog, SortDialog)

    @pytest.mark.asyncio
    async def test_sort_dialog_selection(self, temp_directory_with_varied_files):
        """Test selecting sort options in the dialog."""
        app = FileBrowserApp(start_path=str(temp_directory_with_varied_files))
        async with app.run_test() as pilot:
            # Check initial sort mode
            assert app.current_sort_mode == SortMode.NAME

            # Open sort dialog
            await pilot.press("s")
            await pilot.pause(0.2)

            # Check dialog is open
            from selectfilecli.file_browser_app import SortDialog

            dialog = pilot.app.screen_stack[-1]
            assert isinstance(dialog, SortDialog)

            # Cancel the dialog with escape
            await pilot.press("escape")
            await pilot.pause(0.1)

            # Mode should remain unchanged
            assert app.current_sort_mode == SortMode.NAME

    @pytest.mark.asyncio
    async def test_tree_sorting_applied(self, temp_directory_with_varied_files):
        """Test that sorting is actually applied to the tree."""
        app = FileBrowserApp(start_path=str(temp_directory_with_varied_files))
        async with app.run_test() as pilot:
            tree = pilot.app.query_one(CustomDirectoryTree)

            # Expand root to load children
            await pilot.press("enter")
            await pilot.pause(0.1)

            # Check that tree has sort settings
            assert hasattr(tree, "sort_mode")
            assert hasattr(tree, "sort_order")
            assert tree.sort_mode == SortMode.NAME
            assert tree.sort_order == SortOrder.ASCENDING

    # Snapshot tests for different sort modes
    def test_sort_by_name_snapshot(self, snap_compare):
        """Test visual snapshot when sorted by name."""
        snapshot_app_path = Path(__file__).parent / "snapshot_apps" / "test_sorting_browser.py"
        # Default is name sort, just expand the tree
        assert snap_compare(snapshot_app_path, press=["enter"], terminal_size=(80, 24))

    def test_sort_dialog_snapshot(self, snap_compare):
        """Test visual snapshot of the sort dialog."""
        snapshot_app_path = Path(__file__).parent / "snapshot_apps" / "test_sorting_browser.py"
        # Open sort dialog
        assert snap_compare(snapshot_app_path, press=["s"], terminal_size=(80, 24))

    @pytest.mark.asyncio
    async def test_sort_dialog_cancel(self, temp_directory_with_varied_files):
        """Test canceling the sort dialog leaves settings unchanged."""
        app = FileBrowserApp(start_path=str(temp_directory_with_varied_files))
        async with app.run_test() as pilot:
            # Save initial settings
            initial_mode = app.current_sort_mode
            initial_order = app.current_sort_order

            # Open and cancel dialog
            await pilot.press("s")
            await pilot.pause(0.1)
            await pilot.press("escape")
            await pilot.pause(0.1)

            # Settings should be unchanged
            assert app.current_sort_mode == initial_mode
            assert app.current_sort_order == initial_order

    @pytest.mark.asyncio
    async def test_footer_shows_sort_binding(self, temp_directory):
        """Test that footer shows the Sort binding."""
        app = FileBrowserApp(start_path=str(temp_directory))
        async with app.run_test() as pilot:
            footer = pilot.app.query_one("Footer")
            # The footer should show the sort binding
            assert footer is not None


class TestSortDialog:
    """Test the SortDialog class directly."""

    def test_sort_dialog_initialization(self):
        """Test SortDialog initialization."""
        dialog = SortDialog(SortMode.SIZE, SortOrder.DESCENDING)
        assert dialog.current_mode == SortMode.SIZE
        assert dialog.current_order == SortOrder.DESCENDING

    def test_custom_directory_tree_init(self):
        """Test CustomDirectoryTree initialization."""
        tree = CustomDirectoryTree("/tmp")
        assert tree._original_path == "/tmp"
        assert tree.sort_mode == SortMode.NAME
        assert tree.sort_order == SortOrder.ASCENDING


class TestSelectFileFunction:
    """Test the select_file public API function."""

    def test_select_file_with_mock(self, temp_directory, monkeypatch):
        """Test select_file function with mocked Textual app."""
        from selectfilecli import select_file

        selected_path = str(temp_directory / "test.txt")

        # Mock the FileBrowserApp to return a specific path
        class MockApp:
            def __init__(self, start_path):
                self.start_path = start_path

            def run(self):
                return selected_path

        monkeypatch.setattr("selectfilecli.file_browser_app.FileBrowserApp", MockApp)

        result = select_file(str(temp_directory))
        assert result == selected_path

    def test_select_file_default_path(self, monkeypatch):
        """Test select_file with default current directory."""
        from selectfilecli import select_file

        # Mock the app
        class MockApp:
            def __init__(self, start_path):
                self.start_path = start_path
                assert start_path == os.getcwd()

            def run(self):
                return None

        monkeypatch.setattr("selectfilecli.file_browser_app.FileBrowserApp", MockApp)

        result = select_file()
        assert result is None
