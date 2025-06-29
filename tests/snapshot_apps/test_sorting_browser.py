#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""Test app for snapshot testing with sorting."""

from pathlib import Path
import time
import os

from selectfilecli.file_browser_app import FileBrowserApp


def create_test_directory():
    """Create a consistent test directory structure for sorting tests."""
    # Use a fixed subdirectory name for consistency
    test_dir = Path("/tmp/selectfilecli_sort_test")

    # Clean up if exists
    if test_dir.exists():
        import shutil

        shutil.rmtree(test_dir)

    # Create directory structure
    test_dir.mkdir(parents=True)

    # Create files with specific attributes for sorting tests
    files = [
        # filename, content, size (approx)
        ("zebra.txt", "Last alphabetically", 20),
        ("apple.py", "#!/usr/bin/env python3\nprint('First alphabetically')", 50),
        ("big_file.dat", "X" * 10000, 10000),
        ("tiny.json", '{"a":1}', 7),
        ("medium.xml", "<root>" + "data" * 100 + "</root>", 500),
        ("backup.zip", "ZIP" * 300, 900),
        ("notes.md", "# Notes\nSome content", 20),
        ("data.csv", "id,value\n1,100\n2,200", 25),
    ]

    # Create files with controlled timestamps
    base_time = time.time() - 3600  # 1 hour ago
    for i, (filename, content, _) in enumerate(files):
        file_path = test_dir / filename
        file_path.write_text(content)
        # Set different modification times
        mod_time = base_time + (i * 300)  # 5 minutes apart
        os.utime(file_path, (mod_time, mod_time))

    # Create subdirectories (these will appear first due to directory-first sorting)
    (test_dir / "archive").mkdir()
    (test_dir / "workspace").mkdir()
    (test_dir / "output").mkdir()

    return test_dir


if __name__ == "__main__":
    test_dir = create_test_directory()
    app = FileBrowserApp(start_path=str(test_dir))
    app.run()
