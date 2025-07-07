#!/usr/bin/env python3
# -*- coding: utf-8 -*-

# HERE IS THE CHANGELOG FOR THIS VERSION OF THE FILE:
# - Created comprehensive test suite for select_file API with correct FileInfo structure
# - Added tests for all parameter combinations
# - Added tests for error handling and edge cases
# - Added tests for FileInfo return types
# - Added tests for backward compatibility
# - Added tests for signal handling
#

"""
Comprehensive tests for the select_file API with correct FileInfo structure.

This module tests all aspects of the select_file function including:
- Parameter validation
- Return types
- Error handling
- Signal handling
- Backward compatibility
"""

import os
import pytest
import warnings
from unittest.mock import Mock, patch, MagicMock
from pathlib import Path
import tempfile
import signal

from selectfilecli import select_file, FileInfo


class TestSelectFileAPIWithFileInfo:
    """Test the main select_file API function with correct FileInfo structure."""

    def test_default_parameters(self) -> None:
        """Test select_file with default parameters."""
        with patch("selectfilecli.file_browser_app.FileBrowserApp") as MockApp:
            mock_app = Mock()
            mock_app.run.return_value = None
            MockApp.return_value = mock_app

            result = select_file()

            assert result is None
            MockApp.assert_called_once_with(start_path=os.getcwd(), select_files=True, select_dirs=False)

    def test_custom_start_path(self) -> None:
        """Test select_file with custom start path."""
        with tempfile.TemporaryDirectory() as tmpdir:
            with patch("selectfilecli.file_browser_app.FileBrowserApp") as MockApp:
                mock_app = Mock()
                mock_app.run.return_value = None
                MockApp.return_value = mock_app

                result = select_file(tmpdir)

                assert result is None
                MockApp.assert_called_once_with(start_path=tmpdir, select_files=True, select_dirs=False)

    def test_file_selection_returns_string(self) -> None:
        """Test that file selection returns string for backward compatibility."""
        with patch("selectfilecli.file_browser_app.FileBrowserApp") as MockApp:
            mock_app = Mock()
            mock_file_info = FileInfo(file_path=Path("/test/file.txt"), folder_path=None, last_modified_datetime=None, creation_datetime=None, size_in_bytes=1234, readonly=False, folder_has_venv=False, is_symlink=False, symlink_broken=False, error_message=None)
            mock_app.run.return_value = mock_file_info
            MockApp.return_value = mock_app

            with warnings.catch_warnings(record=True) as w:
                warnings.simplefilter("always")
                result = select_file(select_files=True, select_dirs=False, return_info=False)

                assert result == "/test/file.txt"
                assert len(w) == 1
                assert issubclass(w[0].category, DeprecationWarning)
                assert "Returning string paths is deprecated" in str(w[0].message)

    def test_dir_selection_returns_fileinfo(self) -> None:
        """Test that directory selection returns FileInfo by default."""
        with patch("selectfilecli.file_browser_app.FileBrowserApp") as MockApp:
            mock_app = Mock()
            mock_file_info = FileInfo(file_path=None, folder_path=Path("/test/dir"), last_modified_datetime=None, creation_datetime=None, size_in_bytes=0, readonly=False, folder_has_venv=False, is_symlink=False, symlink_broken=False, error_message=None)
            mock_app.run.return_value = mock_file_info
            MockApp.return_value = mock_app

            result = select_file(select_files=True, select_dirs=True)

            assert isinstance(result, FileInfo)
            assert result.path_str == "/test/dir"
            assert result.folder_path == Path("/test/dir")

    def test_explicit_return_info_true(self) -> None:
        """Test explicit return_info=True returns FileInfo."""
        with patch("selectfilecli.file_browser_app.FileBrowserApp") as MockApp:
            mock_app = Mock()
            mock_file_info = FileInfo(file_path=Path("/test/file.txt"), folder_path=None, last_modified_datetime=None, creation_datetime=None, size_in_bytes=1234, readonly=False, folder_has_venv=False, is_symlink=False, symlink_broken=False, error_message=None)
            mock_app.run.return_value = mock_file_info
            MockApp.return_value = mock_app

            result = select_file(select_files=True, select_dirs=False, return_info=True)

            assert isinstance(result, FileInfo)
            assert result.path_str == "/test/file.txt"

    def test_cancellation_returns_none(self) -> None:
        """Test that cancellation (all None FileInfo) returns None."""
        with patch("selectfilecli.file_browser_app.FileBrowserApp") as MockApp:
            mock_app = Mock()
            # Create a FileInfo with all None values (cancellation)
            mock_file_info = FileInfo(file_path=None, folder_path=None, last_modified_datetime=None, creation_datetime=None, size_in_bytes=None, readonly=None, folder_has_venv=None, is_symlink=None, symlink_broken=None, error_message=None)
            mock_app.run.return_value = mock_file_info
            MockApp.return_value = mock_app

            result = select_file()

            assert result is None

    def test_signal_handler_restoration(self) -> None:
        """Test that signal handlers are properly restored."""
        original_handler = signal.signal(signal.SIGINT, signal.SIG_DFL)

        try:
            with patch("selectfilecli.file_browser_app.FileBrowserApp") as MockApp:
                mock_app = Mock()
                mock_app.run.return_value = None
                MockApp.return_value = mock_app

                # Run select_file
                select_file()

                # Check that handler is restored (may be modified by app)
                current_handler = signal.signal(signal.SIGINT, signal.SIG_DFL)
                # Handler should be either original or SIG_DFL
                assert current_handler in (original_handler, signal.SIG_DFL)
        finally:
            # Restore original handler
            signal.signal(signal.SIGINT, original_handler)

    def test_signal_handler_on_exception(self) -> None:
        """Test that signal handlers are restored even on exception."""
        original_handler = signal.signal(signal.SIGINT, signal.SIG_DFL)

        try:
            with patch("selectfilecli.file_browser_app.FileBrowserApp") as MockApp:
                mock_app = Mock()
                mock_app.run.side_effect = RuntimeError("Test error")
                MockApp.return_value = mock_app

                # Run select_file expecting exception
                with pytest.raises(RuntimeError):
                    select_file()

                # Check that handler is still restored
                current_handler = signal.signal(signal.SIGINT, signal.SIG_DFL)
                # Handler should be either original or SIG_DFL
                assert current_handler in (original_handler, signal.SIG_DFL)
        finally:
            # Restore original handler
            signal.signal(signal.SIGINT, original_handler)

    def test_symlink_handling(self) -> None:
        """Test handling of symbolic links."""
        with patch("selectfilecli.file_browser_app.FileBrowserApp") as MockApp:
            mock_app = Mock()
            mock_file_info = FileInfo(file_path=Path("/test/link"), folder_path=None, last_modified_datetime=None, creation_datetime=None, size_in_bytes=1234, readonly=False, folder_has_venv=False, is_symlink=True, symlink_broken=False, error_message=None)
            mock_app.run.return_value = mock_file_info
            MockApp.return_value = mock_app

            result = select_file(return_info=True)

            assert isinstance(result, FileInfo)
            assert result.is_symlink is True
            assert result.symlink_broken is False

    def test_error_message_handling(self) -> None:
        """Test handling of files with error messages."""
        with patch("selectfilecli.file_browser_app.FileBrowserApp") as MockApp:
            mock_app = Mock()
            mock_file_info = FileInfo(file_path=Path("/test/file.txt"), folder_path=None, last_modified_datetime=None, creation_datetime=None, size_in_bytes=None, readonly=True, folder_has_venv=None, is_symlink=False, symlink_broken=False, error_message="Permission denied")
            mock_app.run.return_value = mock_file_info
            MockApp.return_value = mock_app

            result = select_file(return_info=True)

            assert isinstance(result, FileInfo)
            assert result.error_message == "Permission denied"

    def test_all_selection_combinations(self) -> None:
        """Test all combinations of select_files and select_dirs."""
        test_cases = [
            (True, False, False),  # Files only, no return_info
            (True, False, True),  # Files only, with return_info
            (False, True, None),  # Dirs only, auto return_info
            (True, True, None),  # Both, auto return_info
            (True, True, False),  # Both, no return_info
            (True, True, True),  # Both, with return_info
        ]

        for select_files, select_dirs, return_info in test_cases:
            with patch("selectfilecli.file_browser_app.FileBrowserApp") as MockApp:
                mock_app = Mock()
                mock_file_info = FileInfo(
                    file_path=Path("/test/item") if select_files else None,
                    folder_path=Path("/test/item") if select_dirs and not select_files else None,
                    last_modified_datetime=None,
                    creation_datetime=None,
                    size_in_bytes=1234,
                    readonly=False,
                    folder_has_venv=False,
                    is_symlink=False,
                    symlink_broken=False,
                    error_message=None,
                )
                mock_app.run.return_value = mock_file_info
                MockApp.return_value = mock_app

                kwargs = {"select_files": select_files, "select_dirs": select_dirs}
                if return_info is not None:
                    kwargs["return_info"] = return_info

                with warnings.catch_warnings():
                    warnings.simplefilter("ignore")
                    result = select_file(**kwargs)

                # Determine expected return type
                if return_info is False and select_files and not select_dirs:
                    assert isinstance(result, str)
                elif return_info is None and select_dirs:
                    assert isinstance(result, FileInfo)
                elif return_info:
                    assert isinstance(result, FileInfo)

    def test_venv_folder_detection(self) -> None:
        """Test detection of virtual environment folders."""
        with patch("selectfilecli.file_browser_app.FileBrowserApp") as MockApp:
            mock_app = Mock()
            mock_file_info = FileInfo(file_path=None, folder_path=Path("/test/venv"), last_modified_datetime=None, creation_datetime=None, size_in_bytes=0, readonly=False, folder_has_venv=True, is_symlink=False, symlink_broken=False, error_message=None)
            mock_app.run.return_value = mock_file_info
            MockApp.return_value = mock_app

            result = select_file(select_dirs=True, return_info=True)

            assert isinstance(result, FileInfo)
            assert result.folder_has_venv is True

    def test_broken_symlink_detection(self) -> None:
        """Test detection of broken symbolic links."""
        with patch("selectfilecli.file_browser_app.FileBrowserApp") as MockApp:
            mock_app = Mock()
            mock_file_info = FileInfo(file_path=Path("/test/broken_link"), folder_path=None, last_modified_datetime=None, creation_datetime=None, size_in_bytes=None, readonly=True, folder_has_venv=False, is_symlink=True, symlink_broken=True, error_message="Target not found")
            mock_app.run.return_value = mock_file_info
            MockApp.return_value = mock_app

            result = select_file(return_info=True)

            assert isinstance(result, FileInfo)
            assert result.is_symlink is True
            assert result.symlink_broken is True
