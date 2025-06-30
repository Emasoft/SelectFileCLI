#!/usr/bin/env python3
# -*- coding: utf-8 -*-
#
# Copyright (c) 2024-2025 Emasoft
# Licensed under the MIT License.
# See the LICENSE file in the project root for full license text.
#

# HERE IS THE CHANGELOG FOR THIS VERSION OF THE FILE:
# - Fixed import to use relative import for FileList
# - Added proper shebang and encoding declaration
# - Modified tui_file_browser to return selected file path instead of printing
# - Added type annotation for return value (Optional[str])
# - Renamed getInput to get_input following Python naming conventions
# - Renamed fileList to file_list following Python naming conventions
# - Added docstrings to all functions
# - Added type hints to function parameters
#

import os
import sys
import termios
import tty
from typing import Optional, List, Union, Dict, Any
from .FileList import FileList

# ANSI escape codes for terminal control
CLEAR_SCREEN = "\033[2J"
RESET_CURSOR = "\033[H"
HIGHLIGHT = "\033[7m"
RESET = "\033[0m"


def get_input() -> str:
    """Read a single character input from the terminal.

    Returns:
        The character read from stdin

    Raises:
        OSError: If terminal attributes cannot be read/set
    """
    try:
        fd = sys.stdin.fileno()
        old_settings = termios.tcgetattr(fd)
        try:
            tty.setraw(fd)
            ch = sys.stdin.read(1)
        finally:
            termios.tcsetattr(fd, termios.TCSADRAIN, old_settings)
        return ch
    except (OSError, ValueError) as e:
        # Handle case where stdin is not a terminal
        raise OSError(f"Failed to read terminal input: {e}")


def display_files(current_path: str, file_list: List[Union[Dict[str, str], os.DirEntry[Any]]], selected_index: int) -> None:
    """Display files in a TUI format with highlighted selection.

    Args:
        current_path: The current directory path
        file_list: List of file entries to display
        selected_index: Index of the currently selected item
    """
    try:
        sys.stdout.write(CLEAR_SCREEN + RESET_CURSOR)
        print(f"Current Path: {current_path}")

        for i, entry in enumerate(file_list):
            label = entry["label"] if isinstance(entry, dict) else f"{'Dir ' if entry.is_dir() else 'File'} {entry.name}"
            if i == selected_index:
                sys.stdout.write(f"{HIGHLIGHT}> {label}{RESET}\n")
            else:
                sys.stdout.write(f"  {label}\n")

        sys.stdout.flush()
    except (OSError, IOError) as e:
        # Handle case where stdout is not available
        raise OSError(f"Failed to write to terminal: {e}")


def tui_file_browser() -> Optional[str]:
    """Main TUI function for file browsing.

    Returns:
        The path of the selected file, or None if cancelled

    Raises:
        OSError: If terminal operations fail
    """
    current_path = os.getcwd()
    selected_index = 0

    while True:
        file_list_obj = FileList(current_path)
        entries = file_list_obj.get_entry_list()

        # Add custom dict entry for '..' for parent directory navigation
        file_list = [{"name": "..", "label": "Dir  .. (Go up)"}] + entries

        display_files(current_path, file_list, selected_index)

        key = get_input()

        # Handle arrow keys
        if key == "\x1b":  # ESC sequence for arrow keys
            get_input()  # Skip '['
            arrow_key = get_input()
            if arrow_key == "A":  # Up arrow
                selected_index = max(0, selected_index - 1)
            elif arrow_key == "B":  # Down arrow
                selected_index = min(len(file_list) - 1, selected_index + 1)

        # Enter key to open directory or file
        elif key == "\r":
            selected_entry = file_list[selected_index]

            if isinstance(selected_entry, dict) and selected_entry["name"] == "..":
                # Navigate to the parent directory
                current_path = os.path.dirname(current_path)
                selected_index = 0
            elif hasattr(selected_entry, "is_dir") and selected_entry.is_dir():
                # Navigate into the selected directory
                if hasattr(selected_entry, "name"):
                    current_path = os.path.join(current_path, selected_entry.name)
                selected_index = 0
            elif hasattr(selected_entry, "name"):
                sys.stdout.write(CLEAR_SCREEN + RESET_CURSOR)
                selected_file = os.path.join(current_path, selected_entry.name)
                return selected_file

        # Quit the TUI with 'q'
        elif key == "q":
            sys.stdout.write(CLEAR_SCREEN + RESET_CURSOR)
            return None


if __name__ == "__main__":
    tui_file_browser()
