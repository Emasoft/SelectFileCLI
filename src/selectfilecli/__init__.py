#!/usr/bin/env python3
# -*- coding: utf-8 -*-
#
# Copyright (c) 2024-2025 Emasoft
# Licensed under the MIT License.
# See the LICENSE file in the project root for full license text.
#

# HERE IS THE CHANGELOG FOR THIS VERSION OF THE FILE:
# - Created main library API function select_file()
# - Added proper type annotations
# - Added comprehensive docstring
# - Updated to use Textual-based FileBrowserApp instead of raw terminal control
# - Added support for folder selection with select_files and select_dirs parameters
# - Changed return type to FileInfo dataclass with comprehensive file information
# - Added backward compatibility mode that returns string when only file selection is enabled
#

"""
selectfilecli - A handy file selection browser for CLI applications.

This module provides a simple API to display a file browser TUI and get the selected file path.
"""

from typing import Any, Optional, Union, overload
import os
import signal
import sys
import warnings
from .file_info import FileInfo


@overload
def select_file(start_path: Optional[str] = None, *, select_files: bool = True, select_dirs: bool = True, return_info: bool = True) -> Optional[FileInfo]: ...


@overload
def select_file(start_path: Optional[str] = None, select_files: bool = True, select_dirs: bool = False) -> Optional[Union[str, FileInfo]]: ...


def select_file(start_path: Optional[str] = None, select_files: bool = True, select_dirs: bool = False, return_info: Optional[bool] = None) -> Optional[Union[str, FileInfo]]:
    """
    Display a file browser TUI and return the selected file or directory.

    Args:
        start_path: The directory to start browsing from. If None, uses current working directory.
        select_files: Whether to allow file selection (default: True).
        select_dirs: Whether to allow directory selection (default: False).
        return_info: Whether to return FileInfo object. If None, returns FileInfo when
                    select_dirs=True, otherwise returns string for backward compatibility.

    Returns:
        - If return_info=False and only files selectable: String path or None
        - Otherwise: FileInfo object with comprehensive information or None

    Example:
        >>> from selectfilecli import select_file
        >>> # Simple file selection (backward compatible)
        >>> selected = select_file("/home/user/documents")
        >>> if selected:
        ...     print(f"You selected: {selected}")

        >>> # Select files or directories with full info
        >>> info = select_file("/home", select_files=True, select_dirs=True)
        >>> if info:
        ...     print(f"Path: {info.path}")
        ...     print(f"Size: {info.size_in_bytes}")
        ...     print(f"Read-only: {info.readonly}")
    """
    # Import here to avoid circular imports and only load when needed
    from .file_browser_app import FileBrowserApp

    # Validate and set start path
    if start_path is None:
        start_path = os.getcwd()
    elif not os.path.isdir(start_path):
        raise ValueError(f"Start path must be a valid directory: {start_path}")
    elif not os.access(start_path, os.R_OK):
        raise ValueError(f"Start path must be readable: {start_path}")

    # Validate selection options
    if not select_files and not select_dirs:
        raise ValueError("At least one of select_files or select_dirs must be True")

    # Determine return type
    if return_info is None:
        # Auto-detect: use FileInfo if dirs are selectable or explicitly requested
        return_info = select_dirs

    # Setup signal handlers for clean exit
    def signal_handler(signum: int, frame: Any) -> None:
        """Handle interrupt signals gracefully."""
        sys.exit(0)

    # Register signal handlers
    original_sigint = signal.signal(signal.SIGINT, signal_handler)
    try:
        # Create and run the Textual app
        app = FileBrowserApp(start_path=start_path, select_files=select_files, select_dirs=select_dirs)
        result = app.run()
    finally:
        # Restore original signal handler
        signal.signal(signal.SIGINT, original_sigint)

    if result is None:
        return None

    # Check if this is a cancellation (all fields are None)
    if isinstance(result, FileInfo):
        # Check if all fields are None (cancellation)
        if all(value is None for value in result.as_tuple()):
            return None

    # For backward compatibility, return string if only files are selectable
    # and return_info is False
    if not return_info and isinstance(result, FileInfo):
        # Issue deprecation warning if using old API
        if select_files and not select_dirs:
            warnings.warn("Returning string paths is deprecated. Set return_info=True to get FileInfo objects.", DeprecationWarning, stacklevel=2)
        return result.path_str

    return result


__all__ = ["select_file", "FileInfo"]
__version__ = "0.4.4"  # Follow semantic versioning
