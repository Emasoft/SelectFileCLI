#!/usr/bin/env python3
# -*- coding: utf-8 -*-
#
# Copyright (c) 2024-2025 Emasoft
# Licensed under the MIT License.
# See the LICENSE file in the project root for full license text.
#

"""
Advanced example script demonstrating all features of selectfilecli library.
"""

from pathlib import Path
from selectfilecli import select_file


def main() -> None:
    """Run the advanced example."""
    print("Welcome to selectfilecli advanced example!")
    print("=" * 60)

    # Example 1: Basic file selection with new FileInfo return
    print("\n1. Basic file selection (returns FileInfo object):")
    print("-" * 50)
    result = select_file(return_info=True)

    if result:
        print(f"\nFile selected: {result.file_path}")
        print(f"Size: {result.size_in_bytes:,} bytes")
        print(f"Modified: {result.last_modified_datetime}")
        print(f"Read-only: {result.readonly}")
        if result.is_symlink:
            print(f"Symlink: Yes (broken: {result.symlink_broken})")
    else:
        print("\nNo file selected")

    # Example 2: Folder selection
    print("\n\n2. Folder selection mode:")
    print("-" * 50)
    result = select_file(select_files=False, select_dirs=True, return_info=True)

    if result:
        print(f"\nFolder selected: {result.folder_path}")
        print(f"Size: {result.size_in_bytes:,} bytes (recursive)")
        print(f"Has virtual environment: {result.folder_has_venv}")
        print(f"Created: {result.creation_datetime}")
    else:
        print("\nNo folder selected")

    # Example 3: Both files and folders
    print("\n\n3. Select either files or folders:")
    print("-" * 50)
    result = select_file(select_files=True, select_dirs=True, return_info=True)

    if result:
        if result.file_path:
            print(f"\nFile selected: {result.file_path}")
        else:
            print(f"\nFolder selected: {result.folder_path}")
        print(f"Type: {'File' if result.file_path else 'Directory'}")
    else:
        print("\nNothing selected")

    # Example 4: Backward compatibility (returns string path)
    print("\n\n4. Backward compatible mode (returns string):")
    print("-" * 50)
    path = select_file()  # No return_info parameter defaults to string

    if path:
        print(f"\nPath selected: {path}")
        print(f"Type: {type(path).__name__}")
    else:
        print("\nNo selection made")

    # Example 5: Starting from specific directory
    print("\n\n5. Start from home directory:")
    print("-" * 50)
    home = Path.home()
    result = select_file(str(home), return_info=True)

    if result:
        selected_path = result.file_path or result.folder_path
        print(f"\nSelected: {selected_path}")

    print("\n\nExample completed!")


if __name__ == "__main__":
    main()
