#!/usr/bin/env python3
"""Snapshot app for testing error states."""

from pathlib import Path
import tempfile
import os
from selectfilecli.file_browser_app import FileBrowserApp


def create_test_structure() -> Path:
    """Create test structure with files that may cause errors."""
    tmpdir = tempfile.mkdtemp()
    test_dir = Path(tmpdir)

    # Create normal files
    (test_dir / "normal_file.txt").write_text("This is accessible")

    # Create a file with restricted permissions (Unix only)
    if os.name != "nt":
        restricted = test_dir / "restricted_file.txt"
        restricted.write_text("secret")
        restricted.chmod(0o000)  # No permissions

        # Create directory with no read permission
        no_read_dir = test_dir / "no_read_directory"
        no_read_dir.mkdir()
        (no_read_dir / "hidden.txt").write_text("can't see me")
        no_read_dir.chmod(0o000)

    # Create broken symlink
    broken_link = test_dir / "broken_symlink.txt"
    broken_link.symlink_to(test_dir / "nonexistent_target.txt")

    # Create circular symlink
    circular1 = test_dir / "circular1"
    circular2 = test_dir / "circular2"
    circular1.symlink_to(circular2)
    circular2.symlink_to(circular1)

    return test_dir


if __name__ == "__main__":
    test_dir = create_test_structure()
    app = FileBrowserApp(str(test_dir))
    try:
        app.run()
    finally:
        # Cleanup: restore permissions for deletion
        if os.name != "nt":
            try:
                (test_dir / "restricted_file.txt").chmod(0o644)
                (test_dir / "no_read_directory").chmod(0o755)
            except Exception:
                pass
