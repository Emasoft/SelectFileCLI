#!/usr/bin/env python3
# -*- coding: utf-8 -*-
#
# Copyright (c) 2024-2025 Emasoft
# Licensed under the MIT License.
# See the LICENSE file in the project root for full license text.
#

# HERE IS THE CHANGELOG FOR THIS VERSION OF THE FILE:
# - Created tests specifically for scrollbar behavior
# - Tests vertical scrolling with many files
# - Tests horizontal scrolling with long filenames
# - Tests scrollbar visibility and interaction
#

"""Visual snapshot tests for scrollbar behavior."""

import tempfile
from pathlib import Path
from typing import Any, Generator
import pytest

from selectfilecli.file_browser_app import FileBrowserApp


class TestScrollbarSnapshots:
    """Test scrollbar behavior and appearance."""

    @pytest.fixture
    def scrollbar_test_directory(self) -> Generator[Path, None, None]:
        """Create directory optimized for scrollbar testing."""
        with tempfile.TemporaryDirectory() as tmpdir:
            test_dir = Path(tmpdir)

            # Create many files for vertical scrolling
            vertical_dir = test_dir / "vertical_scroll_test"
            vertical_dir.mkdir()

            # Create 100 files with incrementing names
            for i in range(100):
                filename = f"{i:03d}_file_with_moderate_length_name_{chr(65 + (i % 26))}.txt"
                (vertical_dir / filename).write_text(f"File number {i}")

            # Create files with very long names for horizontal scrolling
            horizontal_dir = test_dir / "horizontal_scroll_test"
            horizontal_dir.mkdir()

            long_names = [
                "this_is_an_extremely_long_filename_that_should_definitely_exceed_the_terminal_width_and_trigger_horizontal_scrolling_behavior_when_displayed_in_the_file_browser_" + "x" * 50 + ".txt",
                "another_ridiculously_long_filename_with_many_words_separated_by_underscores_to_test_how_the_browser_handles_horizontal_overflow_scenarios_" + "y" * 50 + ".doc",
                "第三个超级长的文件名包含中文字符以测试不同字符宽度对水平滚动的影响以及布局的稳定性" + "文" * 30 + ".pdf",
                "네번째_매우_긴_파일명은_한국어를_포함하여_수평_스크롤_동작을_테스트합니다" + "가" * 30 + ".jpg",
                "🎉🎨🎭emoji_filled_extremely_long_filename_to_test_emoji_handling_in_horizontal_scroll🎪🎬🎯" + "🌟" * 20 + ".png",
            ]

            for i, name in enumerate(long_names):
                (horizontal_dir / name).write_text(f"Long name file {i}")

            # Create mixed content directory
            mixed_dir = test_dir / "mixed_scroll_test"
            mixed_dir.mkdir()

            # Mix of short and long names
            for i in range(50):
                if i % 5 == 0:
                    # Every 5th file has a very long name
                    name = f"{i:02d}_this_is_a_very_long_filename_that_exceeds_normal_width_" + "z" * 40 + ".txt"
                else:
                    # Normal length names
                    name = f"{i:02d}_normal_file.txt"
                (mixed_dir / name).write_text(f"Mixed file {i}")

            # Create deeply nested structure for testing tree scrolling
            nested_dir = test_dir / "nested_scroll_test"
            current = nested_dir
            for i in range(15):  # Reduced from 30 to avoid path length limits
                current = current / f"L{i:02d}"  # Shorter directory names
                try:
                    current.mkdir(parents=True)
                    # Add some files at each level
                    for j in range(3):
                        (current / f"file_{j}.txt").write_text(f"Level {i} file {j}")
                except OSError:
                    # Stop if we hit filesystem limits
                    break

            yield test_dir

    def test_vertical_scrollbar_top_snapshot(self, snap_compare: Any, scrollbar_test_directory: Path) -> None:
        """Test vertical scrollbar at top position."""
        app = FileBrowserApp(start_path=str(scrollbar_test_directory / "vertical_scroll_test"))
        assert snap_compare(app, terminal_size=(80, 20))

    def test_vertical_scrollbar_middle_snapshot(self, snap_compare: Any, scrollbar_test_directory: Path) -> None:
        """Test vertical scrollbar at middle position."""
        app = FileBrowserApp(start_path=str(scrollbar_test_directory / "vertical_scroll_test"))
        # Scroll to middle
        assert snap_compare(app, press=["page_down"] * 3, terminal_size=(80, 20))

    def test_vertical_scrollbar_bottom_snapshot(self, snap_compare: Any, scrollbar_test_directory: Path) -> None:
        """Test vertical scrollbar at bottom position."""
        app = FileBrowserApp(start_path=str(scrollbar_test_directory / "vertical_scroll_test"))
        # Scroll to bottom
        assert snap_compare(app, press=["end"], terminal_size=(80, 20))

    def test_horizontal_scrollbar_snapshot(self, snap_compare: Any, scrollbar_test_directory: Path) -> None:
        """Test horizontal scrollbar with long filenames."""
        app = FileBrowserApp(start_path=str(scrollbar_test_directory / "horizontal_scroll_test"))
        assert snap_compare(app, terminal_size=(60, 15))

    def test_both_scrollbars_snapshot(self, snap_compare: Any, scrollbar_test_directory: Path) -> None:
        """Test both scrollbars visible."""
        app = FileBrowserApp(start_path=str(scrollbar_test_directory / "mixed_scroll_test"))
        # Navigate to a long filename in the middle
        assert snap_compare(app, press=["down"] * 15, terminal_size=(50, 15))

    def test_scrollbar_tiny_terminal_snapshot(self, snap_compare: Any, scrollbar_test_directory: Path) -> None:
        """Test scrollbars in very small terminal."""
        app = FileBrowserApp(start_path=str(scrollbar_test_directory / "vertical_scroll_test"))
        assert snap_compare(app, terminal_size=(30, 10))

    def test_nested_tree_scrolling_snapshot(self, snap_compare: Any, scrollbar_test_directory: Path) -> None:
        """Test scrolling in deeply nested tree."""
        app = FileBrowserApp(start_path=str(scrollbar_test_directory / "nested_scroll_test"))

        async def expand_nested(pilot: Any) -> None:
            tree = pilot.app.query_one("CustomDirectoryTree")
            # Expand several levels
            node = tree.root.children[0] if tree.root.children else None
            for _ in range(10):
                if node and hasattr(node, "expand"):
                    node.expand()
                    if node.children:
                        node = node.children[0]

        assert snap_compare(app, run_before=expand_nested, terminal_size=(80, 25))

    def test_scrollbar_page_navigation_snapshot(self, snap_compare: Any, scrollbar_test_directory: Path) -> None:
        """Test page up/down navigation with scrollbar."""
        app = FileBrowserApp(start_path=str(scrollbar_test_directory / "vertical_scroll_test"))
        # Navigate with page up/down
        assert snap_compare(app, press=["page_down", "page_down", "page_up"], terminal_size=(70, 20))

    def test_scrollbar_continuous_scroll_snapshot(self, snap_compare: Any, scrollbar_test_directory: Path) -> None:
        """Test continuous scrolling behavior."""
        app = FileBrowserApp(start_path=str(scrollbar_test_directory / "vertical_scroll_test"))
        # Continuous down scrolling
        assert snap_compare(app, press=["down"] * 30, terminal_size=(75, 18))
