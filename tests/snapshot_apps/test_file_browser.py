#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""Test app for snapshot testing."""

from pathlib import Path
import tempfile

from selectfilecli.file_browser_app import FileBrowserApp


def create_test_directory():
    """Create a consistent test directory structure."""
    # Use a fixed subdirectory name for consistency
    test_dir = Path("/tmp/selectfilecli_test")

    # Clean up if exists
    if test_dir.exists():
        import shutil

        shutil.rmtree(test_dir)

    # Create directory structure
    test_dir.mkdir(parents=True)

    # Create subdirectories
    (test_dir / "documents").mkdir()
    (test_dir / "documents" / "work").mkdir()
    (test_dir / "pictures").mkdir()
    (test_dir / "music").mkdir()

    # Create test files
    (test_dir / "readme.txt").write_text("Test readme")
    (test_dir / "documents" / "report.pdf").write_text("Test report")
    (test_dir / "documents" / "work" / "project.doc").write_text("Test project")
    (test_dir / "pictures" / "photo.jpg").write_text("Test photo")

    return test_dir


if __name__ == "__main__":
    test_dir = create_test_directory()
    app = FileBrowserApp(start_path=str(test_dir))
    app.run()
