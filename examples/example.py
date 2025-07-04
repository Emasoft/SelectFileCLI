#!/usr/bin/env python3
# -*- coding: utf-8 -*-
#
# Copyright (c) 2024-2025 Emasoft
# Licensed under the MIT License.
# See the LICENSE file in the project root for full license text.
#

"""
Example script demonstrating how to use selectfilecli library.
"""

from pathlib import Path
from selectfilecli import select_file, FileInfo


def main() -> None:
    """Run the comprehensive example showcasing all features."""
    print("Welcome to SelectFileCLI v0.4.3!")
    print("=" * 60)
    print("\nKeyboard Shortcuts:")
    print("- Arrow keys: Navigate through files and folders")
    print("- Enter: Navigate into folders or select files")
    print("- 'u' or Backspace: Go to parent directory")
    print("- 'h': Go to home directory")
    print("- 'r': Go to root directory")
    print("- 's': Open sort options dialog")
    print("- 'd': Select current directory (when folder selection is enabled)")
    print("- Alt+Left: Go back in navigation history")
    print("- Alt+Right: Go forward in navigation history")
    print("- 'q' or Escape: Cancel and exit")
    print("\nVisual Features:")
    print("- 🔒 Lock icon for read-only files")
    print("- 🔗 Link icon for symbolic links")
    print("- ✨ Sparkle icon for Python virtual environments")
    print("- Loading indicators during navigation")
    print("- Column alignment with file sizes and dates")
    print("-" * 60)

    # Example 1: Basic file selection (backward compatible)
    print("\nExample 1: Basic file selection")
    print("Select any file from your file system:")
    selected = select_file()

    if selected:
        print(f"\nYou selected: {selected}")
        print(f"Type: {type(selected).__name__}")
    else:
        print("\nNo file selected (cancelled)")

    # Example 2: Select with FileInfo (recommended API)
    print("\n" + "-" * 60)
    print("\nExample 2: File selection with detailed information")
    print("Select a file to see its detailed information:")

    result = select_file(return_info=True)

    if result and result.error_message:
        print(f"\nError occurred: {result.error_message}")
    elif result and result.file_path:
        print(f"\nFile selected: {result.file_path}")
        print(f"Size: {result.size_in_bytes:,} bytes" if result.size_in_bytes else "Size: Unknown")
        print(f"Modified: {result.last_modified_datetime}")
        print(f"Created: {result.creation_datetime}")
        print(f"Read-only: {result.readonly}")
        print(f"Is symlink: {result.is_symlink}")
        if result.is_symlink:
            print(f"Symlink broken: {result.symlink_broken}")
    elif result and result.folder_path:
        print(f"\nFolder selected: {result.folder_path}")
        print(f"Has virtual environment: {result.folder_has_venv}")
    else:
        print("\nCancelled - no selection made")

    # Example 3: Select only folders
    print("\n" + "-" * 60)
    print("\nExample 3: Folder-only selection")
    print("Select a folder (files cannot be selected):")

    folder_result = select_file(select_files=False, select_dirs=True, return_info=True)

    if folder_result and folder_result.folder_path:
        print(f"\nFolder selected: {folder_result.folder_path}")
        print(f"Size: {folder_result.size_in_bytes:,} bytes" if folder_result.size_in_bytes else "Size: Unknown")
        print(f"Has virtual environment: {folder_result.folder_has_venv}")
    else:
        print("\nNo folder selected")

    # Example 4: Select from a specific starting directory
    print("\n" + "-" * 60)
    print("\nExample 4: Starting from a specific directory")
    home_dir = str(Path.home())
    print(f"Starting from: {home_dir}")

    specific_result = select_file(start_path=home_dir, select_files=True, select_dirs=True, return_info=True)

    if specific_result:
        path = specific_result.path
        print(f"\nSelected: {path}")
        print(f"Type: {'Folder' if specific_result.folder_path else 'File'}")
    else:
        print("\nNo selection made")

    # Example 5: Handling errors
    print("\n" + "-" * 60)
    print("\nExample 5: Error handling")
    print("Attempting to start from an invalid path:")

    try:
        error_result = select_file(start_path="/nonexistent/path", return_info=True)
    except ValueError as e:
        print(f"Error caught: {e}")

    print("\n" + "-" * 60)
    print("\nExamples completed!")
    print("\nNew in v0.4.3:")
    print("- Fixed circular symlink handling")
    print("- Added terminal detection for safety")
    print("- Improved navigation performance")
    print("- Better memory management with LRU caches")
    print("- Enhanced column alignment with emoji support")


if __name__ == "__main__":
    main()
