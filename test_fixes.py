#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""Test script to verify the fixes."""

import tempfile
from pathlib import Path
from selectfilecli import select_file


def test_file_browser() -> None:
    """Test the file browser with a temporary directory."""
    # Create a test directory structure
    with tempfile.TemporaryDirectory() as tmpdir:
        test_dir = Path(tmpdir)

        # Create subdirectories
        (test_dir / "documents").mkdir()
        (test_dir / "pictures").mkdir()
        (test_dir / "music").mkdir()

        # Create test files
        (test_dir / "readme.txt").write_text("Test readme")
        (test_dir / "documents" / "report.pdf").write_text("Test report")
        (test_dir / "pictures" / "photo.jpg").write_text("Test photo")

        print("Testing file browser...")
        print("Please verify:")
        print("1. Navigation bar is visible and not overlapped by header")
        print("2. Path display shows actual paths, not function representations")
        print("3. Navigation buttons (Up, Home, Root) work without black screen")
        print("4. Enter key navigates into directories")
        print("5. Sort dialog accepts Enter and Escape keys")
        print("\nPress Escape or Q to exit without selection")

        # Test the file browser
        result = select_file(str(test_dir), select_files=True, select_dirs=True)

        if result:
            print(f"\nSelected: {result}")
            if hasattr(result, "path"):
                print(f"Path: {result.path}")
                print(f"Size: {result.size_in_bytes} bytes")
                print(f"Read-only: {result.readonly}")
        else:
            print("\nNo selection made")


if __name__ == "__main__":
    test_file_browser()
