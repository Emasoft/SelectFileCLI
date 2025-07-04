#!/usr/bin/env python3
# -*- coding: utf-8 -*-
#
# Copyright (c) 2024-2025 Emasoft
# Licensed under the MIT License.
# See the LICENSE file in the project root for full license text.
#

"""Regression tests for bug fixes in selectFileCLI."""
# mypy: disable-error-code="method-assign"

import os
import sys
import tempfile
import pytest
from pathlib import Path
from unittest.mock import Mock, patch, MagicMock
from collections import OrderedDict
from typing import Any, Iterator

# Add src to path for imports
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "src")))

from selectfilecli.file_info import FileInfo
from selectfilecli.FileList import FileList
from selectfilecli.file_browser_app import CustomDirectoryTree


class TestCircularSymlinkFix:
    """Test that circular symlinks don't cause infinite recursion."""

    def test_calculate_directory_size_with_circular_symlink(self, tmp_path: Path) -> None:
        """Test that circular symlinks are handled without infinite recursion."""
        # Create a directory structure with circular symlink
        dir_a = tmp_path / "dir_a"
        dir_b = tmp_path / "dir_b"
        dir_a.mkdir()
        dir_b.mkdir()

        # Create some files
        (dir_a / "file1.txt").write_text("content1")
        (dir_b / "file2.txt").write_text("content2")

        # Create circular symlinks
        (dir_a / "link_to_b").symlink_to(dir_b)
        (dir_b / "link_to_a").symlink_to(dir_a)

        # Create directory tree instance
        tree = CustomDirectoryTree(str(tmp_path))

        # This should not cause infinite recursion
        size = tree.calculate_directory_size(tmp_path)

        # Size should be calculated without following symlinks
        assert size > 0
        assert size < 1000  # Should be small, not following symlinks infinitely

    def test_calculate_directory_size_visited_tracking(self, tmp_path: Path) -> None:
        """Test that visited directories are properly tracked."""
        # Create nested directories
        nested = tmp_path / "a" / "b" / "c"
        nested.mkdir(parents=True)
        (nested / "file.txt").write_text("test content")

        tree = CustomDirectoryTree(str(tmp_path))

        # Mock the calculate_directory_size to track visited paths
        visited_paths = set()
        original_method = tree.calculate_directory_size

        def track_visited(path: Path, depth: int = 0, max_items: int = 1000, visited: Any = None) -> int:
            if visited is not None:
                visited_paths.update(visited)
            return original_method(path, depth, max_items, visited)

        tree.calculate_directory_size = track_visited  # type: ignore[assignment]

        # Calculate size
        tree.calculate_directory_size(tmp_path)

        # Verify that paths were tracked (visited set was used)
        assert len(visited_paths) > 0


class TestTerminalDetection:
    """Test terminal detection before termios operations."""

    @patch("sys.stdin.isatty")
    @patch("sys.stdout.isatty")
    def test_fileBrowser_non_tty_stdin(self, mock_stdout_isatty: Mock, mock_stdin_isatty: Mock) -> None:
        """Test that non-TTY stdin is detected and raises error."""
        from selectfilecli.fileBrowser import tui_file_browser

        mock_stdin_isatty.return_value = False
        mock_stdout_isatty.return_value = True

        with pytest.raises(OSError, match="requires an interactive terminal"):
            tui_file_browser()

    @patch("sys.stdin.isatty")
    @patch("sys.stdout.isatty")
    def test_fileBrowser_non_tty_stdout(self, mock_stdout_isatty: Mock, mock_stdin_isatty: Mock) -> None:
        """Test that non-TTY stdout is detected and raises error."""
        from selectfilecli.fileBrowser import tui_file_browser

        mock_stdin_isatty.return_value = True
        mock_stdout_isatty.return_value = False

        with pytest.raises(OSError, match="requires an interactive terminal"):
            tui_file_browser()

    @patch("sys.stdin.isatty")
    def test_get_input_non_tty(self, mock_isatty: Mock) -> None:
        """Test that get_input raises error for non-TTY."""
        from selectfilecli.fileBrowser import get_input

        mock_isatty.return_value = False

        with pytest.raises(OSError, match="not a terminal"):
            get_input()

    @patch("sys.stdout.isatty")
    def test_display_files_non_tty(self, mock_isatty: Mock) -> None:
        """Test that display_files raises error for non-TTY."""
        from selectfilecli.fileBrowser import display_files

        mock_isatty.return_value = False

        with pytest.raises(OSError, match="not a terminal"):
            display_files("/tmp", [], 0)


class TestFileInfoTypeAnnotations:
    """Test FileInfo type annotations are correct."""

    def test_iter_return_type(self) -> None:
        """Test that __iter__ returns correct types."""
        info = FileInfo(file_path=Path("/test/file.txt"), size_in_bytes=1024, readonly=True)

        # Test iteration
        values = list(info)
        assert len(values) == 10  # Number of fields

        # Each value should be Optional[Union[...]]
        for value in values:
            # Value can be None or one of the expected types
            assert value is None or isinstance(value, (Path, str, int, bool))

    def test_as_tuple_return_type(self) -> None:
        """Test that as_tuple returns correct types."""
        info = FileInfo(folder_path=Path("/test"))

        # Get tuple
        result = info.as_tuple()

        # Should be a tuple
        assert isinstance(result, tuple)
        assert len(result) == 10


class TestLRUCacheEviction:
    """Test proper LRU cache eviction implementation."""

    def test_ordered_dict_usage(self) -> None:
        """Test that caches use OrderedDict."""
        tree = CustomDirectoryTree("/tmp")

        # Verify caches are OrderedDict
        assert isinstance(tree._venv_cache, OrderedDict)
        assert isinstance(tree._dir_size_cache, OrderedDict)

    def test_lru_eviction_order(self) -> None:
        """Test that LRU eviction removes least recently used items."""
        tree = CustomDirectoryTree("/tmp")

        # Create a small cache for testing
        test_cache: OrderedDict[str, Any] = OrderedDict()

        # Add items
        for i in range(5):
            tree._manage_cache(test_cache, f"key{i}", 3)
            test_cache[f"key{i}"] = i

        # Cache should have evicted oldest items
        assert len(test_cache) == 3
        assert "key0" not in test_cache
        assert "key1" not in test_cache
        assert "key2" in test_cache
        assert "key3" in test_cache
        assert "key4" in test_cache

    def test_lru_access_updates_order(self) -> None:
        """Test that accessing an item moves it to end (most recent)."""
        tree = CustomDirectoryTree("/tmp")

        # Create cache with 3 items
        test_cache: OrderedDict[str, Any] = OrderedDict()
        test_cache["a"] = 1
        test_cache["b"] = 2
        test_cache["c"] = 3

        # Access "a" to make it most recent
        tree._manage_cache(test_cache, "a", 3)

        # Add new item - "b" should be evicted (oldest)
        tree._manage_cache(test_cache, "d", 3)
        test_cache["d"] = 4

        assert "a" in test_cache  # Still present (was accessed)
        assert "b" not in test_cache  # Evicted (oldest)
        assert "c" in test_cache
        assert "d" in test_cache


class TestNavigationRaceCondition:
    """Test that navigation race condition is fixed."""

    def test_navigation_flag_prevents_concurrent_navigation(self) -> None:
        """Test that _is_navigating flag prevents concurrent navigation."""
        from selectfilecli.file_browser_app import FileBrowserApp

        app = FileBrowserApp()

        # Mock the methods that require UI components
        app._update_navigation_buttons = Mock()
        app._update_path_display = Mock()
        app.query_one = Mock()

        # Mock the worker method
        app._replace_tree_worker = Mock()

        # Set initial navigation state
        app._is_navigating = False

        # First navigation should succeed
        app._change_directory(Path("/tmp"))
        assert app._is_navigating is True
        assert app.current_path == Path("/tmp")

        # Try second navigation while first is in progress
        app._change_directory(Path("/usr"))

        # Path should not have changed because navigation was blocked
        assert app.current_path == Path("/tmp")

        # Worker should have been called only once
        app._replace_tree_worker.assert_called_once()

    def test_worker_receives_target_path(self, tmp_path: Path) -> None:
        """Test that worker receives target path as parameter."""
        from selectfilecli.file_browser_app import FileBrowserApp

        app = FileBrowserApp()

        # Mock the methods that require UI components
        app._update_navigation_buttons = Mock()
        app._update_path_display = Mock()
        app.query_one = Mock()

        # Mock the worker to capture arguments
        app._replace_tree_worker = Mock()

        # Ensure navigation is not blocked
        app._is_navigating = False

        # Create a real directory to navigate to
        test_dir = tmp_path / "test_dir"
        test_dir.mkdir()

        # Navigate to the real directory
        app._change_directory(test_dir)

        # Verify worker was called with correct path
        app._replace_tree_worker.assert_called_once_with(test_dir)


class TestFileListPathHandling:
    """Test FileList path handling fix."""

    def test_relative_path_converted_to_absolute(self) -> None:
        """Test that relative paths are converted to absolute."""
        # Test with relative path
        file_list = FileList(".")
        assert os.path.isabs(file_list.path)

        # Test with another relative path
        file_list2 = FileList("../")
        assert os.path.isabs(file_list2.path)

    def test_recursive_search_uses_absolute_paths(self, tmp_path: Path) -> None:
        """Test that recursive search works correctly with absolute paths."""
        # Create nested structure
        (tmp_path / "dir1").mkdir()
        (tmp_path / "dir1" / "dir2").mkdir()
        (tmp_path / "dir1" / "file1.txt").write_text("test")
        (tmp_path / "dir1" / "dir2" / "file2.txt").write_text("test")

        # Search with relative path
        original_cwd = os.getcwd()
        try:
            os.chdir(tmp_path)
            file_list = FileList(".")
            file_list.search_dir(max_depth=2)

            # All paths in tree should be absolute
            for path in file_list.tree.keys():
                assert os.path.isabs(path)

        finally:
            os.chdir(original_cwd)


class TestSignalHandlerContextManager:
    """Test signal handler context manager."""

    def test_signal_handler_restored_on_exception(self) -> None:
        """Test that signal handler is restored even on exception."""
        import signal
        from selectfilecli import _signal_handler_context

        # Save original handler
        original_handler = signal.signal(signal.SIGINT, signal.default_int_handler)

        try:
            # Use context manager with exception
            with pytest.raises(ValueError):
                with _signal_handler_context():
                    # Verify handler was changed
                    current = signal.signal(signal.SIGINT, signal.default_int_handler)
                    assert current != original_handler
                    signal.signal(signal.SIGINT, current)  # Restore for test

                    # Raise exception
                    raise ValueError("Test exception")

            # Verify handler was restored after exception
            restored = signal.signal(signal.SIGINT, original_handler)
            assert restored == original_handler

        finally:
            # Ensure original handler is restored
            signal.signal(signal.SIGINT, original_handler)

    def test_signal_handler_restored_on_normal_exit(self) -> None:
        """Test that signal handler is restored on normal exit."""
        import signal
        from selectfilecli import _signal_handler_context

        # Save original handler
        original_handler = signal.signal(signal.SIGINT, signal.default_int_handler)

        try:
            # Use context manager normally
            with _signal_handler_context():
                # Verify handler was changed
                current = signal.signal(signal.SIGINT, signal.default_int_handler)
                assert current != original_handler
                signal.signal(signal.SIGINT, current)  # Restore for test

            # Verify handler was restored
            restored = signal.signal(signal.SIGINT, original_handler)
            assert restored == original_handler

        finally:
            # Ensure original handler is restored
            signal.signal(signal.SIGINT, original_handler)


class TestEmojiColumnAlignment:
    """Test emoji visual width calculation for column alignment."""

    def test_emoji_visual_width_calculation(self) -> None:
        """Test that emojis are counted as 2 visual columns."""
        tree = CustomDirectoryTree("/tmp")

        # Create mock node structure
        mock_node = Mock()
        mock_node._children = []

        # Add mock children with emoji filenames
        for filename in ["file.txt", "✨venv", "🔒readonly.txt", "normal.py"]:
            child = Mock()
            child.data = Mock()
            child.data.path = Path(f"/tmp/{filename}")
            mock_node._children.append(child)

        # Calculate column widths
        tree._calculate_column_widths(mock_node)

        # Verify that emoji filenames were properly accounted for
        # The longest visual width should be for "🔒readonly.txt" (14 visual chars)
        assert tree._column_widths["filename"] >= 14


class TestMemoryLeakPrevention:
    """Test that caches don't grow unbounded."""

    def test_venv_cache_size_limit(self, tmp_path: Path) -> None:
        """Test that venv cache respects size limit."""
        tree = CustomDirectoryTree(str(tmp_path))

        # Add many items to venv cache
        for i in range(1500):  # More than MAX_VENV_CACHE_SIZE (1000)
            path = tmp_path / f"dir{i}"
            path.mkdir()
            tree.has_venv(path)

        # Cache should not exceed limit
        assert len(tree._venv_cache) <= 1000

    def test_dir_size_cache_limit(self, tmp_path: Path) -> None:
        """Test that dir size cache respects size limit."""
        tree = CustomDirectoryTree(str(tmp_path))

        # Create many directories
        for i in range(600):  # More than MAX_DIR_CACHE_SIZE (500)
            path = tmp_path / f"dir{i}"
            path.mkdir()
            (path / "file.txt").write_text("content")
            tree.calculate_directory_size(path)

        # Cache should not exceed limit
        assert len(tree._dir_size_cache) <= 500


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
