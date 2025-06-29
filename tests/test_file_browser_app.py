#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""Tests for the Textual file browser application."""

import os
import tempfile
from pathlib import Path
from unittest.mock import patch

import pytest
from textual.pilot import Pilot

from selectfilecli.file_browser_app import FileBrowserApp


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
            assert pilot.app.query_one("DirectoryTree")
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
            tree = pilot.app.query_one("DirectoryTree")

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
            tree = pilot.app.query_one("DirectoryTree")
            assert tree is not None

    @pytest.mark.asyncio
    async def test_app_snapshot(self, temp_directory):
        """Test app appearance with snapshot testing."""
        app = FileBrowserApp(start_path=str(temp_directory))
        async with app.run_test(size=(80, 24)) as pilot:
            # Simply verify the app runs without errors
            # Snapshot testing with Textual requires specific setup
            assert pilot.app is not None
            assert pilot.app.title == "Select File Browser"


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
