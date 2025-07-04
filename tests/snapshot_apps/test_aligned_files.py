#!/usr/bin/env python3
"""Snapshot app for testing file alignment in columns."""

from pathlib import Path
import tempfile
import time
from selectfilecli.file_browser_app import FileBrowserApp


def create_test_structure() -> Path:
    """Create test structure with files of varying name lengths and sizes."""
    tmpdir = tempfile.mkdtemp()
    test_dir = Path(tmpdir)

    # Create files with different name lengths and sizes
    files = [
        ("a.txt", "x" * 10),  # Short name, small file
        ("medium_length_file.csv", "y" * 1000),  # Medium name, medium file
        ("this_is_a_very_long_filename_that_should_test_alignment.doc", "z" * 50000),  # Long name, large file
        ("test.py", "#!/usr/bin/env python3\nprint('test')" * 100),  # Script file
        ("data.json", '{"key": "value"}' * 500),  # JSON file
        ("image.jpg", "binary" * 2000),  # Image file
        ("README.md", "# Readme\n\nThis is a test." * 10),  # Markdown
        ("config.ini", "[section]\nkey=value\n" * 20),  # Config file
    ]

    # Create files with different timestamps
    base_time = time.time()
    for i, (filename, content) in enumerate(files):
        file_path = test_dir / filename
        file_path.write_text(content)
        # Set different modification times
        mod_time = base_time - (i * 3600)  # Each file 1 hour older
        file_path.touch()
        import os

        os.utime(file_path, (mod_time, mod_time))

    # Create some directories too
    (test_dir / "short_dir").mkdir()
    (test_dir / "directory_with_a_longer_name").mkdir()

    return test_dir


if __name__ == "__main__":
    test_dir = create_test_structure()
    app = FileBrowserApp(str(test_dir))
    app.run()
