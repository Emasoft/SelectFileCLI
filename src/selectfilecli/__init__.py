#!/usr/bin/env python3
# -*- coding: utf-8 -*-

# HERE IS THE CHANGELOG FOR THIS VERSION OF THE FILE:
# - Created main library API function select_file()
# - Added proper type annotations
# - Added comprehensive docstring
#

"""
selectfilecli - A handy file selection browser for CLI applications.

This module provides a simple API to display a file browser TUI and get the selected file path.
"""

from typing import Optional
import os


def select_file(start_path: Optional[str] = None) -> Optional[str]:
    """
    Display a file browser TUI and return the selected file path.

    Args:
        start_path: The directory to start browsing from. If None, uses current working directory.

    Returns:
        The full path of the selected file, or None if the user cancelled.

    Example:
        >>> from selectfilecli import select_file
        >>> selected = select_file("/home/user/documents")
        >>> if selected:
        ...     print(f"You selected: {selected}")
    """
    # Import here to avoid circular imports and only load when needed
    from .fileBrowser import tui_file_browser

    # Validate and set start path
    if start_path is None:
        start_path = os.getcwd()
    elif not os.path.isdir(start_path):
        raise ValueError(f"Start path must be a valid directory: {start_path}")

    # Store original cwd to restore later
    original_cwd = os.getcwd()

    try:
        # Change to start directory
        os.chdir(start_path)

        # Run the file browser and get the selected file
        selected_file = tui_file_browser()
        return selected_file

    finally:
        # Always restore original directory
        os.chdir(original_cwd)


__all__ = ["select_file"]
__version__ = "0.1.0"
