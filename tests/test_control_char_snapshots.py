#!/usr/bin/env python3
# -*- coding: utf-8 -*-
#
# Copyright (c) 2024-2025 Emasoft
# Licensed under the MIT License.
# See the LICENSE file in the project root for full license text.
#

# HERE IS THE CHANGELOG FOR THIS VERSION OF THE FILE:
# - Created tests for control character handling
# - Tests for invisible characters and zero-width spaces
# - Tests for RTL/LTR override characters
# - Tests for combining characters and complex emoji
#

"""Visual snapshot tests for control and invisible characters."""

import tempfile
from pathlib import Path
from typing import Any, Generator
import pytest

from selectfilecli.file_browser_app import FileBrowserApp


class TestControlCharacterSnapshots:
    """Test handling of control and invisible characters."""

    @pytest.fixture
    def control_char_directory(self) -> Generator[Path, None, None]:
        """Create directory with control character filenames."""
        with tempfile.TemporaryDirectory() as tmpdir:
            test_dir = Path(tmpdir)

            # Files with control characters
            control_char_files = [
                # ASCII control characters
                ("null_char", "file\x00with\x00null.txt"),
                ("bell_char", "\x07bell\x07sound.txt"),
                ("backspace", "file\x08back\x08space.txt"),
                ("tab", "file\twith\ttabs.txt"),
                ("newline", "file\nwith\nnewlines.txt"),
                ("vertical_tab", "file\x0bvertical\x0btab.txt"),
                ("form_feed", "file\x0cform\x0cfeed.txt"),
                ("carriage_return", "file\rwith\rCR.txt"),
                ("escape", "file\x1bescape\x1bseq.txt"),
                ("delete", "file\x7fdelete\x7fchar.txt"),
                # Unicode control characters
                ("zero_width_space", "file\u200bzero\u200bwidth.txt"),
                ("zero_width_joiner", "file\u200dzero\u200djoiner.txt"),
                ("zero_width_non_joiner", "file\u200czero\u200cnon-joiner.txt"),
                ("left_to_right_mark", "file\u200eLTR\u200emark.txt"),
                ("right_to_left_mark", "file\u200fRTL\u200fmark.txt"),
                ("left_to_right_embedding", "file\u202aLRE\u202aembed.txt"),
                ("right_to_left_embedding", "file\u202bRLE\u202bembed.txt"),
                ("pop_directional", "file\u202cPOP\u202cdir.txt"),
                ("left_to_right_override", "file\u202dLRO\u202doverride.txt"),
                ("right_to_left_override", "file\u202eRLO\u202eoverride.txt"),
                ("word_joiner", "file\u2060word\u2060joiner.txt"),
                ("function_application", "file\u2061func\u2061app.txt"),
                ("invisible_times", "file\u2062invisible\u2062times.txt"),
                ("invisible_separator", "file\u2063invisible\u2063sep.txt"),
                ("invisible_plus", "file\u2064invisible\u2064plus.txt"),
                ("byte_order_mark", "\ufeffBOM\ufefffile.txt"),
                # Combining characters
                ("combining_acute", "file\u0301combining\u0301acute.txt"),
                ("combining_grave", "file\u0300combining\u0300grave.txt"),
                ("combining_circumflex", "file\u0302combining\u0302circ.txt"),
                ("combining_tilde", "file\u0303combining\u0303tilde.txt"),
                ("combining_macron", "file\u0304combining\u0304macron.txt"),
                ("combining_breve", "file\u0306combining\u0306breve.txt"),
                ("combining_dot_above", "file\u0307combining\u0307dot.txt"),
                ("combining_diaeresis", "file\u0308combining\u0308diaer.txt"),
                ("combining_ring", "file\u030acombining\u030aring.txt"),
                ("combining_double_acute", "file\u030bcombining\u030bdbl.txt"),
                ("combining_caron", "file\u030ccombining\u030ccaron.txt"),
                # Mixed problematic content
                ("mixed_controls", "mix\x00\n\r\t\x1b\x7f\u200b\u200c\u200d.txt"),
                ("all_spaces", "\x20\xa0\u2000\u2001\u2002\u2003\u2004\u2005.txt"),
                ("direction_mess", "text\u202eגםבעברית\u202cEnglish\u202bوعربي\u202c.txt"),
                ("zalgo_text", "Ż̸̧̢̛͔̹̟̦̭̪̈́̊̾̈́͊̚ͅḀ̷̢̭̰̯̮̹̒̈́̓̊͐̕͝L̶̨̧̰̭̹̮̩̔̈́̊̒̈́̚͝G̸̢̧̛̭̰̮̹̒̈́̓̊͐̕Ơ̷̢͔̹̟̦̭̪̇̈́̊̾̈́͊̚.txt"),
                # Emoji with modifiers
                ("emoji_skin_tone", "👨🏻‍💻👩🏽‍🔬👨🏿‍🎨.txt"),
                ("emoji_zwj_sequence", "👨‍👩‍👧‍👦family👩‍👩‍👧‍👧.txt"),
                ("flag_sequences", "🇺🇸🇬🇧🇯🇵🇰🇷🇨🇳flags.txt"),
                # Extreme cases
                ("only_controls", "\x00\x01\x02\x03\x04\x05\x06\x07.txt"),
                ("only_invisible", "\u200b\u200c\u200d\u2060\u2061\u2062.txt"),
                ("empty_looking", "\u3000\u2800\ufeff.txt"),  # Ideographic space, braille blank, BOM
            ]

            # Create files with sanitized names for filesystem
            for category, filename in control_char_files:
                try:
                    # Create a sanitized version for actual file creation
                    safe_name = filename
                    for char, replacement in [
                        ("\x00", "[NULL]"),
                        ("\x07", "[BELL]"),
                        ("\x08", "[BS]"),
                        ("\n", "[LF]"),
                        ("\r", "[CR]"),
                        ("\x1b", "[ESC]"),
                        ("\x7f", "[DEL]"),
                        ("\x0b", "[VT]"),
                        ("\x0c", "[FF]"),
                    ]:
                        safe_name = safe_name.replace(char, replacement)

                    file_path = test_dir / f"{category}_{safe_name}"
                    file_path.write_text(f"Content: {category}")
                except Exception:
                    # Skip files that can't be created
                    pass

            yield test_dir

    def test_control_chars_display_snapshot(self, snap_compare: Any, control_char_directory: Path) -> None:
        """Test how control characters are displayed."""
        app = FileBrowserApp(start_path=str(control_char_directory))
        assert snap_compare(app, terminal_size=(100, 40))

    def test_control_chars_narrow_terminal_snapshot(self, snap_compare: Any, control_char_directory: Path) -> None:
        """Test control characters on narrow terminal."""
        app = FileBrowserApp(start_path=str(control_char_directory))
        assert snap_compare(app, terminal_size=(50, 30))

    def test_control_chars_navigation_snapshot(self, snap_compare: Any, control_char_directory: Path) -> None:
        """Test navigating through files with control characters."""
        app = FileBrowserApp(start_path=str(control_char_directory))
        assert snap_compare(app, press=["down"] * 10 + ["up"] * 5, terminal_size=(80, 24))

    def test_control_chars_sort_snapshot(self, snap_compare: Any, control_char_directory: Path) -> None:
        """Test sorting files with control characters."""
        app = FileBrowserApp(start_path=str(control_char_directory))

        async def change_sort(pilot: Any) -> None:
            # Open sort dialog
            await pilot.press("s")
            await pilot.pause(0.1)
            # Select size sorting
            await pilot.press("down", "down", "down", "down")
            await pilot.press("enter")

        assert snap_compare(app, run_before=change_sort, terminal_size=(80, 30))


class TestBoundaryConditionsSnapshots:
    """Test boundary conditions for layout stability."""

    @pytest.fixture
    def boundary_test_directory(self) -> Generator[Path, None, None]:
        """Create directory for boundary condition testing."""
        with tempfile.TemporaryDirectory() as tmpdir:
            test_dir = Path(tmpdir)

            # Create files at filesystem limits
            boundary_files = [
                # Maximum filename lengths (255 chars on most systems)
                "a" * 250 + ".txt",
                "文" * 80 + ".txt",  # Unicode chars take more bytes
                "🎉" * 60 + ".txt",  # Emoji take even more bytes
                # Single character names
                "a",
                "文",
                "🎉",
                ".",
                "_",
                "-",
                "~",
                # All dots
                ".",
                "..",
                "...",
                "....",
                # All spaces (will need quotes)
                "   ",
                "\t\t\t",
                "\xa0\xa0\xa0",  # Non-breaking spaces
                # Numbers only
                "0",
                "123456789",
                "999999999999999999999999999999",
                # Special patterns
                "CON",  # Reserved on Windows
                "PRN",  # Reserved on Windows
                "AUX",  # Reserved on Windows
                "NUL",  # Reserved on Windows
                "COM1",  # Reserved on Windows
                "LPT1",  # Reserved on Windows
            ]

            for filename in boundary_files:
                try:
                    if filename not in [".", ".."]:  # Skip special directory entries
                        (test_dir / filename).write_text("boundary test")
                except Exception:
                    pass

            # Create directory structure to test tree limits
            # Very deep nesting
            deep_path = test_dir
            for i in range(20):
                deep_path = deep_path / f"level_{i}"
                try:
                    deep_path.mkdir()
                except Exception:
                    break

            # Very wide (many siblings)
            wide_dir = test_dir / "many_siblings"
            wide_dir.mkdir()
            for i in range(200):
                (wide_dir / f"sibling_{i:03d}.txt").write_text(f"Sibling {i}")

            yield test_dir

    def test_boundary_filenames_snapshot(self, snap_compare: Any, boundary_test_directory: Path) -> None:
        """Test display of boundary condition filenames."""
        app = FileBrowserApp(start_path=str(boundary_test_directory))
        assert snap_compare(app, terminal_size=(120, 40))

    def test_deep_nesting_expanded_snapshot(self, snap_compare: Any, boundary_test_directory: Path) -> None:
        """Test deeply nested directories when expanded."""
        app = FileBrowserApp(start_path=str(boundary_test_directory))

        async def expand_deep(pilot: Any) -> None:
            tree = pilot.app.query_one("CustomDirectoryTree")
            # Find and expand the deep directory chain
            for child in tree.root.children:
                if child.data and "level_0" in str(child.data.path):
                    node = child
                    for _ in range(10):  # Expand 10 levels
                        node.expand()
                        if node.children:
                            node = node.children[0]
                    break

        assert snap_compare(app, run_before=expand_deep, terminal_size=(100, 50))

    def test_many_siblings_snapshot(self, snap_compare: Any, boundary_test_directory: Path) -> None:
        """Test directory with many sibling files."""
        app = FileBrowserApp(start_path=str(boundary_test_directory))

        async def expand_wide(pilot: Any) -> None:
            tree = pilot.app.query_one("CustomDirectoryTree")
            # Find and expand the many_siblings directory
            for child in tree.root.children:
                if child.data and "many_siblings" in str(child.data.path):
                    child.expand()
                    break

        assert snap_compare(app, run_before=expand_wide, terminal_size=(80, 40))
