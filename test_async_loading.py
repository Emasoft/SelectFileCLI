#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Test script to verify async loading behavior."""

import sys
import tempfile
from pathlib import Path

# Add src to path
sys.path.insert(0, str(Path(__file__).parent / "src"))

from selectfilecli.file_browser_app import FileBrowserApp


def create_large_directory(num_files: int = 1000) -> Path:
    """Create a directory with many files to test loading."""
    temp_dir = Path(tempfile.mkdtemp(prefix="large_dir_test_"))

    # Create many files
    for i in range(num_files):
        (temp_dir / f"file_{i:04d}.txt").write_text(f"Content {i}")

    # Create some subdirectories
    for i in range(10):
        subdir = temp_dir / f"subdir_{i}"
        subdir.mkdir()
        # Add files to subdirs too
        for j in range(100):
            (subdir / f"subfile_{j:03d}.txt").write_text(f"Subdir {i} file {j}")

    return temp_dir


if __name__ == "__main__":
    # Create test directory
    test_dir = create_large_directory(1000)
    print(f"Created test directory: {test_dir}")
    print("Testing async loading behavior...")
    print("Look for <...loading...> placeholders when expanding directories")

    try:
        # Run the file browser
        app = FileBrowserApp(start_path=str(test_dir))
        result = app.run()

        if result:
            print(f"\nSelected: {result.file_path or result.folder_path}")
        else:
            print("\nNo selection made")
    finally:
        # Cleanup
        import shutil

        shutil.rmtree(test_dir, ignore_errors=True)
        print("Cleaned up test directory")
