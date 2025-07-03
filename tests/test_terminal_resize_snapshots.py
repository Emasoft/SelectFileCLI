#!/usr/bin/env python3
# -*- coding: utf-8 -*-
#
# Copyright (c) 2024-2025 Emasoft
# Licensed under the MIT License.
# See the LICENSE file in the project root for full license text.
#

# HERE IS THE CHANGELOG FOR THIS VERSION OF THE FILE:
# - Created tests for various terminal sizes
# - Tests layout adaptation to different aspect ratios
# - Tests extreme terminal dimensions
# - Tests responsive behavior
#

"""Visual snapshot tests for terminal resizing scenarios."""

import tempfile
from pathlib import Path
from typing import Any, Generator
import pytest

from selectfilecli.file_browser_app import FileBrowserApp


class TestTerminalResizeSnapshots:
    """Test app behavior with different terminal sizes."""

    @pytest.fixture
    def resize_test_directory(self) -> Generator[Path, None, None]:
        """Create a consistent test directory for resize testing."""
        with tempfile.TemporaryDirectory() as tmpdir:
            test_dir = Path(tmpdir)

            # Create a mix of content to test layout
            dirs = [
                "Documents",
                "Downloads",
                "Pictures",
                "Videos",
                "Music",
                "Projects",
                "Archive",
                "Backups",
            ]

            for dir_name in dirs:
                dir_path = test_dir / dir_name
                dir_path.mkdir()

                # Add some files to each directory
                for i in range(5):
                    (dir_path / f"file_{i}.txt").write_text(f"Content {i}")

            # Add files in root with various lengths
            files = [
                "README.md",
                "LICENSE",
                "config.json",
                "settings.yaml",
                "data.csv",
                "report_2024_Q1_final_version_approved.pdf",
                "🎉_celebration_file.txt",
                "very_long_filename_to_test_wrapping_behavior_in_narrow_terminals.document",
            ]

            for filename in files:
                (test_dir / filename).write_text(f"Content of {filename}")

            # Create a venv directory
            venv_dir = test_dir / "venv"
            venv_dir.mkdir()
            (venv_dir / "pyvenv.cfg").write_text("virtualenv config")

            yield test_dir

    # Standard aspect ratios
    def test_standard_terminal_snapshot(self, snap_compare: Any, resize_test_directory: Path) -> None:
        """Test standard 80x24 terminal."""
        app = FileBrowserApp(start_path=str(resize_test_directory))
        assert snap_compare(app, terminal_size=(80, 24))

    def test_standard_large_terminal_snapshot(self, snap_compare: Any, resize_test_directory: Path) -> None:
        """Test standard large 120x40 terminal."""
        app = FileBrowserApp(start_path=str(resize_test_directory))
        assert snap_compare(app, terminal_size=(120, 40))

    # Wide terminals
    def test_wide_short_terminal_snapshot(self, snap_compare: Any, resize_test_directory: Path) -> None:
        """Test wide but short terminal (160x15)."""
        app = FileBrowserApp(start_path=str(resize_test_directory))
        assert snap_compare(app, terminal_size=(160, 15))

    def test_ultra_wide_terminal_snapshot(self, snap_compare: Any, resize_test_directory: Path) -> None:
        """Test ultra-wide terminal (250x30)."""
        app = FileBrowserApp(start_path=str(resize_test_directory))
        assert snap_compare(app, terminal_size=(250, 30))

    # Narrow terminals
    def test_narrow_tall_terminal_snapshot(self, snap_compare: Any, resize_test_directory: Path) -> None:
        """Test narrow but tall terminal (40x50)."""
        app = FileBrowserApp(start_path=str(resize_test_directory))
        assert snap_compare(app, terminal_size=(40, 50))

    def test_very_narrow_terminal_snapshot(self, snap_compare: Any, resize_test_directory: Path) -> None:
        """Test very narrow terminal (25x20)."""
        app = FileBrowserApp(start_path=str(resize_test_directory))
        assert snap_compare(app, terminal_size=(25, 20))

    # Extreme dimensions
    def test_minimum_usable_terminal_snapshot(self, snap_compare: Any, resize_test_directory: Path) -> None:
        """Test minimum usable size (20x8)."""
        app = FileBrowserApp(start_path=str(resize_test_directory))
        assert snap_compare(app, terminal_size=(20, 8))

    def test_maximum_terminal_snapshot(self, snap_compare: Any, resize_test_directory: Path) -> None:
        """Test very large terminal (300x80)."""
        app = FileBrowserApp(start_path=str(resize_test_directory))
        assert snap_compare(app, terminal_size=(300, 80))

    # Square terminals
    def test_small_square_terminal_snapshot(self, snap_compare: Any, resize_test_directory: Path) -> None:
        """Test small square terminal (40x40)."""
        app = FileBrowserApp(start_path=str(resize_test_directory))
        assert snap_compare(app, terminal_size=(40, 40))

    def test_large_square_terminal_snapshot(self, snap_compare: Any, resize_test_directory: Path) -> None:
        """Test large square terminal (100x100)."""
        app = FileBrowserApp(start_path=str(resize_test_directory))
        assert snap_compare(app, terminal_size=(100, 100))

    # Mobile-like aspect ratios
    def test_mobile_portrait_terminal_snapshot(self, snap_compare: Any, resize_test_directory: Path) -> None:
        """Test mobile portrait-like terminal (50x80)."""
        app = FileBrowserApp(start_path=str(resize_test_directory))
        assert snap_compare(app, terminal_size=(50, 80))

    def test_mobile_landscape_terminal_snapshot(self, snap_compare: Any, resize_test_directory: Path) -> None:
        """Test mobile landscape-like terminal (80x35)."""
        app = FileBrowserApp(start_path=str(resize_test_directory))
        assert snap_compare(app, terminal_size=(80, 35))

    # Test with expanded directories
    def test_expanded_narrow_terminal_snapshot(self, snap_compare: Any, resize_test_directory: Path) -> None:
        """Test expanded directories in narrow terminal."""
        app = FileBrowserApp(start_path=str(resize_test_directory))

        async def expand_dirs(pilot: Any) -> None:
            tree = pilot.app.query_one("CustomDirectoryTree")
            # Expand first few directories
            for i, child in enumerate(tree.root.children[:3]):
                if hasattr(child, "expand"):
                    child.expand()

        assert snap_compare(app, run_before=expand_dirs, terminal_size=(45, 30))

    def test_sort_dialog_small_terminal_snapshot(self, snap_compare: Any, resize_test_directory: Path) -> None:
        """Test sort dialog in small terminal."""
        app = FileBrowserApp(start_path=str(resize_test_directory))
        assert snap_compare(
            app,
            press=["s"],  # Open sort dialog
            terminal_size=(35, 15),
        )

    def test_navigation_buttons_narrow_snapshot(self, snap_compare: Any, resize_test_directory: Path) -> None:
        """Test navigation button layout in narrow terminal."""
        app = FileBrowserApp(start_path=str(resize_test_directory), select_files=True, select_dirs=True)
        assert snap_compare(app, terminal_size=(30, 20))
