#!/usr/bin/env python3
# -*- coding: utf-8 -*-
#
# Copyright (c) 2024-2025 Emasoft
# Licensed under the MIT License.
# See the LICENSE file in the project root for full license text.
#

"""
Advanced example script demonstrating all features of selectfilecli library.

This example showcases:
- Visual improvements: emojis, colors, ls-style file types
- Column alignment for file information
- Virtual environment detection with ✨ emoji
- Empty folder handling
- Error message handling
- Sort dialog functionality
- Real-time resizing support
"""

from pathlib import Path
from selectfilecli import select_file
import tempfile
import os
from typing import Any


def display_file_info(result: Any) -> None:
    """Display comprehensive file information."""
    if result.error_message:
        print(f"❌ Error occurred: {result.error_message}")
        return

    if result.file_path:
        print(f"\n📄 File selected: {result.file_path}")
        print(f"   Size: {result.size_in_bytes:,} bytes")
        print(f"   Modified: 📆{result.last_modified_datetime:%Y-%m-%d} 🕚{result.last_modified_datetime:%H:%M:%S}")
        print(f"   Created: 📆{result.creation_datetime:%Y-%m-%d} 🕚{result.creation_datetime:%H:%M:%S}")
        print(f"   Read-only: {'Yes ⛔' if result.readonly else 'No ✅'}")
        if result.is_symlink:
            print(f"   Symlink: Yes {'🔗💔' if result.symlink_broken else '🔗'}")
    elif result.folder_path:
        print(f"\n📁 Folder selected: {result.folder_path}")
        if result.size_in_bytes is not None:
            print(f"   Size: {result.size_in_bytes:,} bytes (recursive)")
        print(f"   Has virtual environment: {'Yes ✨' if result.folder_has_venv else 'No'}")
        print(f"   Modified: 📆{result.last_modified_datetime:%Y-%m-%d} 🕚{result.last_modified_datetime:%H:%M:%S}")
    else:
        print("\n❌ Selection cancelled (all fields None)")


def create_demo_directory() -> Path:
    """Create a demonstration directory with various file types."""
    demo_dir = Path(tempfile.mkdtemp(prefix="selectfilecli_demo_"))

    # Regular files
    (demo_dir / "readme.txt").write_text("This is a readme file")
    (demo_dir / "script.py").write_text("#!/usr/bin/env python3\nprint('Hello')")
    (demo_dir / "data.csv").write_text("name,value\ntest,123")

    # Make script executable
    os.chmod(demo_dir / "script.py", 0o755)

    # Empty directory
    (demo_dir / "empty_folder").mkdir()

    # Directory with virtual environment
    venv_dir = demo_dir / "my_venv"
    venv_dir.mkdir()
    (venv_dir / "pyvenv.cfg").write_text("python = 3.10")

    # Directory with files
    full_dir = demo_dir / "documents"
    full_dir.mkdir()
    (full_dir / "report.pdf").write_text("PDF content")
    (full_dir / "presentation.pptx").write_text("PowerPoint content")

    # Symlink (if supported)
    try:
        (demo_dir / "link_to_readme").symlink_to("readme.txt")
        (demo_dir / "broken_link").symlink_to("nonexistent.txt")
    except OSError:
        pass  # Windows might not support symlinks

    return demo_dir


def main() -> None:
    """Run the advanced example."""
    print("🚀 SelectFileCLI Advanced Example")
    print("=" * 70)
    print("\nNew Features:")
    print("✅ Fixed 24h datetime format with emojis: 📆YYYY-MM-DD 🕚HH:MM:SS")
    print("✅ File sizes with localized formatting: 1,234.56 KB")
    print("✅ Navigation buttons with emoji shortcuts: 🔼Parent(u) 🏠Home(h) ⏫Root(r)")
    print("✅ ls-style visual cues: colors, suffixes (/, *, @, |, =)")
    print("✅ Virtual environment detection: folders with ✨ emoji")
    print("✅ Column-aligned file entries")
    print("✅ Empty folder handling: shows <empty>")
    print("✅ Error message support in FileInfo")
    print("✅ Real-time terminal resizing")
    print("-" * 70)

    # Create demo directory
    demo_dir = create_demo_directory()
    print(f"\n📁 Created demo directory: {demo_dir}")

    # Example 1: Basic file selection with visual improvements
    print("\n\n1. File Selection (notice visual improvements):")
    print("-" * 50)
    print("Try navigating around, use 's' for sort dialog, resize your terminal!")
    result = select_file(str(demo_dir), return_info=True)
    display_file_info(result)

    # Example 2: Folder selection mode
    print("\n\n2. Folder Selection Mode:")
    print("-" * 50)
    print("Notice the ✨ emoji on virtual environment folders!")
    result = select_file(str(demo_dir), select_files=False, select_dirs=True, return_info=True)
    display_file_info(result)

    # Example 3: Mixed mode - files and folders
    print("\n\n3. Files AND Folders Mode:")
    print("-" * 50)
    print("Press 'd' to select current directory, Enter for files/navigate")
    result = select_file(str(demo_dir), select_files=True, select_dirs=True, return_info=True)
    display_file_info(result)

    # Example 4: Empty folder handling
    print("\n\n4. Empty Folder Handling:")
    print("-" * 50)
    print("Navigate to 'empty_folder' - it will show <empty> placeholder")
    result = select_file(str(demo_dir), return_info=True)
    display_file_info(result)

    # Example 5: Error handling demonstration
    print("\n\n5. Error Handling:")
    print("-" * 50)
    print("Try navigating to a restricted directory (like /root)")
    result = select_file("/", return_info=True)
    display_file_info(result)

    # Example 6: Backward compatibility
    print("\n\n6. Backward Compatible Mode (returns string):")
    print("-" * 50)
    path = select_file(str(demo_dir))  # Returns string path
    if path:
        print(f"Path: {path}")
        print(f"Type: {type(path).__name__}")
    else:
        print("Cancelled")

    # Cleanup
    import shutil

    try:
        shutil.rmtree(demo_dir)
        print("\n🧹 Cleaned up demo directory")
    except Exception:
        print(f"\n⚠️  Please manually delete: {demo_dir}")

    print("\n✅ Example completed!")


if __name__ == "__main__":
    main()
