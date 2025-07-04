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
from selectfilecli import select_file


def main() -> None:
    """Run the basic example."""
    print("Welcome to SelectFileCLI!")
    print("=" * 60)
    print("\nFeatures:")
    print("- Navigate with arrow keys")
    print("- Enter to navigate into folders or select files")
    print("- 'u' or Backspace for parent directory")
    print("- 'h' for home directory")
    print("- 'r' for root directory")
    print("- 's' for sort options")
    print("- 'q' or Escape to cancel")
    print("-" * 60)

    # Example 1: Basic file selection (backward compatible)
    print("\nSelect a file:")
    selected = select_file()

    if selected:
        print(f"\nYou selected: {selected}")
        print(f"Type: {type(selected).__name__}")
    else:
        print("\nNo file selected (cancelled)")

    # Example 2: Select with FileInfo (new API)
    print("\n" + "-" * 60)
    print("Now let's try with detailed file information:")

    result = select_file(return_info=True)

    if result and result.error_message:
        print(f"\nError occurred: {result.error_message}")
    elif result and result.file_path:
        print(f"\nFile selected: {result.file_path}")
        print(f"Size: {result.size_in_bytes:,} bytes")
        print(f"Modified: {result.last_modified_datetime}")
        print(f"Read-only: {result.readonly}")
    elif result and result.folder_path:
        print(f"\nFolder selected: {result.folder_path}")
        print(f"Has virtual environment: {result.folder_has_venv}")
    else:
        print("\nCancelled - no selection made")


if __name__ == "__main__":
    main()
