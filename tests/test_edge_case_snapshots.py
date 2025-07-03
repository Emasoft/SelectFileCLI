#!/usr/bin/env python3
# -*- coding: utf-8 -*-
#
# Copyright (c) 2024-2025 Emasoft
# Licensed under the MIT License.
# See the LICENSE file in the project root for full license text.
#

# HERE IS THE CHANGELOG FOR THIS VERSION OF THE FILE:
# - Created comprehensive edge case visual snapshot tests
# - Tests for various terminal sizes and dynamic resizing
# - Tests for long filenames exceeding screen width
# - Tests for scrollbars (vertical and horizontal)
# - Tests for Unicode characters in various languages
# - Tests for control characters and special characters
# - Tests for layout stability with exotic filenames
#

"""Edge case visual snapshot tests for the file browser."""

import os
import tempfile
from pathlib import Path
from typing import Any, Generator, Type
import pytest

from selectfilecli.file_browser_app import FileBrowserApp


class TestEdgeCaseSnapshots:
    """Test visual snapshots for edge cases."""

    @pytest.fixture
    def edge_case_directory(self) -> Generator[Path, None, None]:
        """Create a directory with edge case filenames."""
        with tempfile.TemporaryDirectory() as tmpdir:
            test_dir = Path(tmpdir)

            # Create subdirectories with various languages
            dirs = [
                "普通文件夹",  # Chinese: Normal Folder
                "한국어_폴더",  # Korean: Korean Folder
                "Русская_папка",  # Russian: Russian Folder
                "עברית_תיקייה",  # Hebrew: Hebrew Folder (will display LTR)
                "مجلد_عربي",  # Arabic: Arabic Folder (will display LTR)
                "हिंदी_फ़ोल्डर",  # Hindi: Hindi Folder
                "संस्कृत_फोल्डर",  # Sanskrit: Sanskrit Folder
                "Ελληνικός_φάκελος",  # Greek: Greek Folder
                "日本語フォルダ",  # Japanese: Japanese Folder
                "emoji_folder_🎉🎨🎭🎪🎬",  # Emoji folder
            ]

            for dir_name in dirs:
                (test_dir / dir_name).mkdir()

            # Create files with edge cases
            edge_case_files = [
                # Very long filenames
                "this_is_a_very_long_filename_that_should_exceed_normal_screen_width_and_trigger_horizontal_scrolling_behavior_in_the_file_browser_interface_1234567890.txt",
                "another_extremely_long_filename_with_lots_of_underscores_and_numbers_123456789012345678901234567890123456789012345678901234567890.document",
                # Files with various Unicode characters
                "文件名_中文字符.txt",  # Chinese characters
                "파일명_한글.txt",  # Korean characters
                "файл_кириллица.txt",  # Cyrillic characters
                "קובץ_עברית.txt",  # Hebrew (will display LTR)
                "ملف_عربي.txt",  # Arabic (will display LTR)
                "फ़ाइल_हिंदी.txt",  # Hindi
                "ファイル_日本語.txt",  # Japanese
                "αρχείο_ελληνικά.txt",  # Greek
                # Files with special characters
                "file with spaces.txt",
                "file\twith\ttabs.txt",
                "file|with|pipes.txt",
                "file*with*asterisks.txt",
                "file?with?questions.txt",
                "file<with>brackets.txt",
                'file"with"quotes.txt',
                "file'with'apostrophes.txt",
                "file[with]square[brackets].txt",
                "file{with}curly{braces}.txt",
                "file(with)parentheses.txt",
                "file&with&ampersands.txt",
                "file@with@at@signs.txt",
                "file#with#hashes.txt",
                "file$with$dollars.txt",
                "file%with%percents.txt",
                "file^with^carets.txt",
                "file=with=equals.txt",
                "file+with+plus+signs.txt",
                "file~with~tildes.txt",
                "file`with`backticks.txt",
                # Files with control characters (will be escaped)
                "file\nwith\nnewlines.txt",
                "file\rwith\rcarriage\rreturns.txt",
                "file\x00with\x00null\x00chars.txt",
                "file\x1bwith\x1bescape\x1bchars.txt",
                "\x07bell\x07character\x07file.txt",
                # Leading/trailing special characters
                "   leading_spaces.txt",
                "trailing_spaces.txt   ",
                "\t\tleading_tabs.txt",
                "trailing_tabs.txt\t\t",
                "...leading_dots.txt",
                "trailing_dots.txt...",
                # Mixed emoji and text
                "🎉celebration🎊file🎈.txt",
                "💻code👨‍💻file🖥️.py",
                "🌍world🌎map🌏.jpg",
                "🔥hot🌶️spicy🌡️.dat",
                # Zero-width and invisible characters
                "file\u200bwith\u200bzero\u200bwidth\u200bspaces.txt",
                "file\u2060with\u2060word\u2060joiners.txt",
                "file\ufeffwith\ufeffBOM.txt",
            ]

            # Create all edge case files
            for filename in edge_case_files:
                try:
                    # Some filenames might be invalid on certain filesystems
                    # Replace invalid characters for the actual file creation
                    safe_filename = filename.replace("\x00", "_null_").replace("\r", "_cr_").replace("\n", "_lf_").replace("\x1b", "_esc_").replace("\x07", "_bel_")
                    (test_dir / safe_filename).write_text(f"Content of {filename}")
                except Exception:
                    # Skip files that can't be created on this filesystem
                    pass

            # Create a Python virtual environment for testing venv detection
            venv_dir = test_dir / "test_venv_✨"
            venv_dir.mkdir()
            (venv_dir / "pyvenv.cfg").write_text("test venv config")

            yield test_dir

    def test_narrow_terminal_snapshot(self, snap_compare: Any, edge_case_directory: Path) -> None:
        """Test with narrow terminal (40x20)."""
        app = FileBrowserApp(start_path=str(edge_case_directory))
        assert snap_compare(app, terminal_size=(40, 20))

    def test_wide_terminal_snapshot(self, snap_compare: Any, edge_case_directory: Path) -> None:
        """Test with wide terminal (120x30)."""
        app = FileBrowserApp(start_path=str(edge_case_directory))
        assert snap_compare(app, terminal_size=(120, 30))

    def test_very_wide_terminal_snapshot(self, snap_compare: Any, edge_case_directory: Path) -> None:
        """Test with very wide terminal (200x40)."""
        app = FileBrowserApp(start_path=str(edge_case_directory))
        assert snap_compare(app, terminal_size=(200, 40))

    def test_tall_terminal_snapshot(self, snap_compare: Any, edge_case_directory: Path) -> None:
        """Test with tall terminal (80x50)."""
        app = FileBrowserApp(start_path=str(edge_case_directory))
        assert snap_compare(app, terminal_size=(80, 50))

    def test_tiny_terminal_snapshot(self, snap_compare: Any, edge_case_directory: Path) -> None:
        """Test with tiny terminal (30x10)."""
        app = FileBrowserApp(start_path=str(edge_case_directory))
        assert snap_compare(app, terminal_size=(30, 10))

    def test_square_terminal_snapshot(self, snap_compare: Any, edge_case_directory: Path) -> None:
        """Test with square terminal (60x60)."""
        app = FileBrowserApp(start_path=str(edge_case_directory))
        assert snap_compare(app, terminal_size=(60, 60))

    def test_navigation_in_edge_cases_snapshot(self, snap_compare: Any, edge_case_directory: Path) -> None:
        """Test navigation with edge case files."""
        app = FileBrowserApp(start_path=str(edge_case_directory))
        # Navigate through some items to test scrolling
        assert snap_compare(app, press=["down"] * 10 + ["up"] * 3, terminal_size=(80, 24))

    def test_expanded_folders_snapshot(self, snap_compare: Any, edge_case_directory: Path) -> None:
        """Test with expanded folders showing Unicode names."""
        app = FileBrowserApp(start_path=str(edge_case_directory))

        async def expand_folders(pilot: Any) -> None:
            # Expand several folders to show their contents
            tree = pilot.app.query_one("CustomDirectoryTree")
            nodes = list(tree.root.children)[:5]  # Expand first 5 folders
            for node in nodes:
                if node.data and Path(node.data.path).is_dir():
                    node.expand()

        assert snap_compare(app, run_before=expand_folders, terminal_size=(100, 40))

    def test_horizontal_scroll_snapshot(self, snap_compare: Any, edge_case_directory: Path) -> None:
        """Test horizontal scrolling with long filenames."""
        app = FileBrowserApp(start_path=str(edge_case_directory))
        # Navigate to a file with a very long name
        assert snap_compare(
            app,
            press=["down"] * 3 + ["right"] * 20,  # Navigate and try to scroll right
            terminal_size=(60, 20),
        )

    def test_mixed_content_snapshot(self, snap_compare: Any, edge_case_directory: Path) -> None:
        """Test with all content visible in medium terminal."""
        app = FileBrowserApp(start_path=str(edge_case_directory), select_files=True, select_dirs=True)
        assert snap_compare(app, terminal_size=(100, 35))

    def test_sort_dialog_unicode_snapshot(self, snap_compare: Any, edge_case_directory: Path) -> None:
        """Test sort dialog with Unicode directory."""
        app = FileBrowserApp(start_path=str(edge_case_directory))
        assert snap_compare(
            app,
            press=["s"],  # Open sort dialog
            terminal_size=(80, 24),
        )


class TestCustomSubtitleSnapshots:
    """Test custom subtitles with Unicode characters."""

    @pytest.fixture
    def unicode_subtitle_app(self) -> Type[FileBrowserApp]:
        """Create app with Unicode subtitle."""

        class UnicodeSubtitleApp(FileBrowserApp):
            def on_mount(self) -> None:
                super().on_mount()
                # Set a subtitle with various Unicode characters
                self.sub_title = "🌍 世界 • 한국 • Мир • עולם • عالم • विश्व • 世界 🌏"

        return UnicodeSubtitleApp

    def test_unicode_subtitle_snapshot(self, snap_compare: Any, unicode_subtitle_app: Type[FileBrowserApp], tmp_path: Path) -> None:
        """Test app with Unicode subtitle."""
        app = unicode_subtitle_app(start_path=str(tmp_path))
        assert snap_compare(app, terminal_size=(120, 24))

    def test_unicode_subtitle_narrow_snapshot(self, snap_compare: Any, unicode_subtitle_app: Type[FileBrowserApp], tmp_path: Path) -> None:
        """Test Unicode subtitle on narrow terminal."""
        app = unicode_subtitle_app(start_path=str(tmp_path))
        assert snap_compare(app, terminal_size=(40, 24))


class TestLayoutStabilitySnapshots:
    """Test layout stability with problematic content."""

    @pytest.fixture
    def stress_test_directory(self) -> Generator[Path, None, None]:
        """Create directory designed to stress test the layout."""
        with tempfile.TemporaryDirectory() as tmpdir:
            test_dir = Path(tmpdir)

            # Create nested directories to test tree depth
            current = test_dir
            for i in range(10):
                current = current / f"深い階層_{i}_уровень_{i}_level_{i}"
                current.mkdir()

            # Create many files to test vertical scrolling
            for i in range(100):
                (test_dir / f"file_{i:03d}_测试文件_{i}.txt").write_text(f"File {i}")

            # Create files that might break layout
            problem_files = [
                "\x1b[31mANSI_color_codes\x1b[0m.txt",
                "file\u202ewith\u202eRTL\u202eoverride.txt",
                "file\u200ewith\u200eLTR\u200emark.txt",
                "combining_é_è_ê_ë_marks.txt",
                "emoji👨‍👩‍👧‍👦family👨‍👨‍👦‍👦emoji.txt",
                "​​​​​only_zero_width_spaces​​​​​.txt",
                "mixed\u0301\u0302\u0303\u0304combining.txt",
            ]

            for filename in problem_files:
                try:
                    (test_dir / filename).write_text("test")
                except Exception:
                    pass

            yield test_dir

    def test_deep_nesting_snapshot(self, snap_compare: Any, stress_test_directory: Path) -> None:
        """Test deeply nested directory structure."""
        app = FileBrowserApp(start_path=str(stress_test_directory))

        async def expand_nested(pilot: Any) -> None:
            tree = pilot.app.query_one("CustomDirectoryTree")
            # Expand the deeply nested directory
            node = tree.root.children[0]
            for _ in range(5):  # Expand 5 levels
                if node.children:
                    node.expand()
                    node = node.children[0]

        assert snap_compare(app, run_before=expand_nested, terminal_size=(100, 30))

    def test_many_files_scrolling_snapshot(self, snap_compare: Any, stress_test_directory: Path) -> None:
        """Test scrolling through many files."""
        app = FileBrowserApp(start_path=str(stress_test_directory))
        # Scroll down through many files
        assert snap_compare(app, press=["down"] * 30 + ["page_down"] * 2, terminal_size=(80, 20))

    def test_layout_breaking_chars_snapshot(self, snap_compare: Any, stress_test_directory: Path) -> None:
        """Test files with potentially layout-breaking characters."""
        app = FileBrowserApp(start_path=str(stress_test_directory))
        # Navigate to problem files
        assert snap_compare(
            app,
            press=["end"],  # Go to end of list where problem files are
            terminal_size=(100, 24),
        )
