#!/usr/bin/env python3
# -*- coding: utf-8 -*-
#
# Copyright (c) 2024-2025 Emasoft
# Licensed under the MIT License.
# See the LICENSE file in the project root for full license text.
#

# HERE IS THE CHANGELOG FOR THIS VERSION OF THE FILE:
# - Created snapshot app for edge case testing
# - App with consistent Unicode and special character files
# - Designed for reproducible visual testing
#

"""Snapshot test app with edge cases."""

from pathlib import Path
import os
import sys

# Add parent directory to path
sys.path.insert(0, str(Path(__file__).parent.parent.parent))

from selectfilecli.file_browser_app import FileBrowserApp


def create_edge_case_test_directory():
    """Create a consistent test directory with edge cases."""
    test_dir = Path("/tmp/selectfilecli_edge_test")

    # Clean up if exists
    if test_dir.exists():
        import shutil

        shutil.rmtree(test_dir)

    # Create directory structure
    test_dir.mkdir(parents=True)

    # Language directories
    language_dirs = {
        "01_English": ["readme.txt", "document.pdf", "script.py"],
        "02_中文_Chinese": ["文档.txt", "脚本.py", "图片.jpg"],
        "03_日本語_Japanese": ["ドキュメント.txt", "スクリプト.py", "画像.jpg"],
        "04_한국어_Korean": ["문서.txt", "스크립트.py", "이미지.jpg"],
        "05_Русский_Russian": ["документ.txt", "скрипт.py", "картинка.jpg"],
        "06_العربية_Arabic": ["مستند.txt", "نص.py", "صورة.jpg"],
        "07_עברית_Hebrew": ["מסמך.txt", "תסריט.py", "תמונה.jpg"],
        "08_हिंदी_Hindi": ["दस्तावेज़.txt", "स्क्रिप्ट.py", "छवि.jpg"],
        "09_Ελληνικά_Greek": ["έγγραφο.txt", "σενάριο.py", "εικόνα.jpg"],
        "10_Emoji_🌍🎉": ["🎉party.txt", "💻code.py", "🖼️image.jpg"],
    }

    for dir_name, files in language_dirs.items():
        dir_path = test_dir / dir_name
        dir_path.mkdir()
        for file_name in files:
            (dir_path / file_name).write_text(f"Content: {file_name}")

    # Special character files in root
    special_files = [
        # Long names
        "very_long_filename_that_exceeds_typical_terminal_width_and_should_trigger_horizontal_scrolling_behavior_when_displayed_in_the_file_browser_interface_1234567890.txt",
        # Special characters
        "file with spaces.txt",
        "file\twith\ttabs.txt",
        "file'with'quotes.txt",
        'file"with"double"quotes.txt',
        "file[with]brackets.txt",
        "file{with}braces.txt",
        "file(with)parens.txt",
        "file|pipe|file.txt",
        "file*asterisk*file.txt",
        "file?question?file.txt",
        "file@at@file.txt",
        "file#hash#file.txt",
        "file$dollar$file.txt",
        "file%percent%file.txt",
        "file&ampersand&file.txt",
        "file=equals=file.txt",
        "file+plus+file.txt",
        "file~tilde~file.txt",
        "file^caret^file.txt",
        "file`backtick`file.txt",
        # Leading/trailing spaces and special chars
        "   leading_spaces.txt",
        "trailing_spaces.txt   ",
        "...leading_dots.txt",
        "trailing_dots.txt...",
        "___leading_underscores.txt",
        "trailing_underscores.txt___",
        # Mixed content
        "🌟mixed_emoji_and_text🌟.txt",
        "中英mixed_languages混合.txt",
        "ΑΛΦΑ_ΒΗΤΑ_greek_ΓΑΜΜΑ.txt",
        # Executable and special types
        "executable_script.sh",
        "symbolic_link",
        "compressed_file.tar.gz",
        "image_file.jpg",
        "audio_file.mp3",
    ]

    for file_name in special_files:
        try:
            file_path = test_dir / file_name
            file_path.write_text(f"Content of {file_name}")

            # Make some files executable
            if file_name.endswith(".sh"):
                os.chmod(file_path, 0o755)

            # Create a symbolic link
            if file_name == "symbolic_link":
                file_path.unlink()
                file_path.symlink_to("readme.txt")

        except Exception:
            # Skip files that can't be created
            pass

    # Create a virtual environment directory
    venv_dir = test_dir / "python_venv"
    venv_dir.mkdir()
    (venv_dir / "pyvenv.cfg").write_text("home = /usr/local/bin")
    (venv_dir / "bin").mkdir()
    (venv_dir / "bin" / "activate").write_text("# activation script")

    # Create deeply nested structure
    nested = test_dir / "deeply" / "nested" / "folder" / "structure" / "test"
    nested.mkdir(parents=True)
    (nested / "deep_file.txt").write_text("Deep file")

    # Create many files for scrolling test
    many_files_dir = test_dir / "many_files"
    many_files_dir.mkdir()
    for i in range(50):
        (many_files_dir / f"file_{i:03d}.txt").write_text(f"File {i}")

    return test_dir


if __name__ == "__main__":
    test_dir = create_edge_case_test_directory()
    app = FileBrowserApp(start_path=str(test_dir), select_files=True, select_dirs=True)
    app.run()
