#!/usr/bin/env python3
# -*- coding: utf-8 -*-

# HERE IS THE CHANGELOG FOR THIS VERSION OF THE FILE:
# - Created main library API function select_file()
# - Added proper type annotations
# - Added comprehensive docstring
# - Updated to use Textual-based FileBrowserApp instead of raw terminal control
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
    from .file_browser_app import FileBrowserApp

    # Validate and set start path
    if start_path is None:
        start_path = os.getcwd()
    elif not os.path.isdir(start_path):
        raise ValueError(f"Start path must be a valid directory: {start_path}")

    # Create and run the Textual app
    app = FileBrowserApp(start_path=start_path)
    selected_file = app.run()
    
    return selected_file


__all__ = ["select_file"]
__version__ = "0.3.0"
