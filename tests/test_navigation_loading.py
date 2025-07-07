#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Test navigation loading indicators."""

import tempfile
import shutil
from pathlib import Path
from selectfilecli import select_file  # type: ignore[import-not-found]


def create_test_dirs() -> Path:
    """Create test directory structure."""
    temp_dir = tempfile.mkdtemp(prefix="test_nav_loading_")

    # Create a few directories to navigate between
    dirs = []
    for i in range(3):
        d = Path(temp_dir) / f"folder_{i}"
        d.mkdir()
        dirs.append(d)

        # Add some content
        for j in range(5):
            (d / f"file_{j}.txt").write_text(f"Content {j}")

        # Create a subdirectory
        sub = d / "subfolder"
        sub.mkdir()
        (sub / "nested_file.txt").write_text("Nested content")

    return Path(temp_dir)


def main() -> None:
    """Test navigation loading."""
    temp_dir = create_test_dirs()

    print("\n" + "=" * 60)
    print("NAVIGATION LOADING TEST")
    print("=" * 60)
    print("\nThis tests the loading indicator during directory navigation.")
    print("\nInstructions:")
    print("1. Use arrow keys to select different folders")
    print("2. Press Enter to navigate into a folder")
    print("3. You should see a loading spinner when navigating")
    print("4. Press 'P' to go to parent directory")
    print("5. Use Back/Forward buttons or 'Alt+Left/Right'")
    print("\nThe loading indicator appears as a spinning overlay")
    print("during directory changes.")
    print("\n" + "=" * 60 + "\n")

    try:
        result = select_file(start_path=temp_dir, select_files=True, select_dirs=True)

        if result:
            print(f"\nSelected: {result}")
        else:
            print("\nNo selection made")
    finally:
        shutil.rmtree(temp_dir, ignore_errors=True)


if __name__ == "__main__":
    main()
