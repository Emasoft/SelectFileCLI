#!/usr/bin/env python3
"""Snapshot app for testing empty folder display."""

from pathlib import Path
import tempfile
from selectfilecli.file_browser_app import FileBrowserApp


def create_test_structure() -> Path:
    """Create test structure with empty folders."""
    tmpdir = tempfile.mkdtemp()
    test_dir = Path(tmpdir)

    # Create empty folders
    (test_dir / "empty_folder_1").mkdir()
    (test_dir / "empty_folder_2").mkdir()

    # Create folder with content for comparison
    full_folder = test_dir / "folder_with_files"
    full_folder.mkdir()
    (full_folder / "file1.txt").write_text("content")
    (full_folder / "file2.txt").write_text("more content")

    # Create a file at root
    (test_dir / "readme.txt").write_text("Root file")

    return test_dir


if __name__ == "__main__":
    test_dir = create_test_structure()
    app = FileBrowserApp(str(test_dir))
    app.run()
