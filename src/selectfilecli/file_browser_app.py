#!/usr/bin/env python3
# -*- coding: utf-8 -*-
#
# Copyright (c) 2024-2025 Emasoft
# Licensed under the MIT License.
# See the LICENSE file in the project root for full license text.
#

# HERE IS THE CHANGELOG FOR THIS VERSION OF THE FILE:
# - Created new Textual-based file browser application
# - Implements FileBrowserApp with directory navigation
# - Returns selected file path via app.return_value
# - Added sorting options: Name, Creation Time, Last Accessed, Last Modified, Size, Extension
# - Added ascending/descending toggle
# - Display current highlighted path in header
# - Sorting controls in footer
# - Use Textual reactive attributes for sort mode and order
# - Add watchers to automatically refresh when sort settings change
# - Add parent directory navigation with Up button and 'u'/'backspace' keys
# - Add home directory navigation with Home button and 'h' key
# - Add root/drive navigation with Root button
# - Support Windows drive navigation
# - Dynamically recreate DirectoryTree when changing directories
# - Add file information display: size, modification date, permissions
# - Show human-readable file sizes (KB, MB, GB)
# - Add lock emoji 🔒 for read-only files
# - Add link emoji 🔗 for symlinks
# - Smart date formatting (time for today, month/day for this year, year otherwise)
# - Updated datetime to fixed 24h format: 📆YYYY-MM-DD 🕚HH:MM:SS
# - Enhanced file size formatting with locale support and thousand separators
# - Added emoji icons to navigation buttons with underlined keyboard shortcuts
# - Added 'r' keyboard binding for root navigation
# - Implemented ls-style visual cues: colors, suffixes (/, *, @, |, =), quoted filenames
# - Added root node label with directory information
# - Added ✨ emoji for directories containing Python virtual environments
#

"""Textual-based file browser application."""

import os
import platform
import stat
import sys
import locale
from datetime import datetime
from pathlib import Path
from typing import Optional, Any, Tuple
from enum import Enum

from textual import on
from textual.app import App, ComposeResult
from textual.reactive import reactive
from textual.widgets import Header, Footer, Label, RadioButton, RadioSet, Button
from textual.widgets._directory_tree import DirectoryTree
from textual.binding import Binding
from textual.containers import Container, Horizontal, Vertical
from textual.screen import ModalScreen
from rich.text import Text

# Constants
FILE_SIZE_UNIT = 1024.0
FILE_SIZE_UNITS = ["B", "KB", "MB", "GB", "TB", "PB"]
DEFAULT_DIR_SIZE = 0
ASCENDING_ORDER_INDEX = 0
WINDOWS_DRIVE_LETTERS = "CDEFGHIJKLMNOPQRSTUVWXYZAB"  # C first, then others

# Set up locale for number formatting
try:
    locale.setlocale(locale.LC_ALL, "")
except locale.Error:
    # Fallback to C locale if system locale is not available
    locale.setlocale(locale.LC_ALL, "C")


class SortMode(Enum):
    """Available sorting modes."""

    NAME = "name"
    CREATED = "created"
    ACCESSED = "accessed"
    MODIFIED = "modified"
    SIZE = "size"
    EXTENSION = "extension"


class SortOrder(Enum):
    """Sort order options."""

    ASCENDING = "asc"
    DESCENDING = "desc"


class SortDialog(ModalScreen[tuple[SortMode, SortOrder]]):
    """Modal dialog for selecting sort mode and order."""

    CSS = """
    SortDialog {
        align: center middle;
    }

    SortDialog > Container {
        background: $surface;
        width: 40;
        height: auto;
        border: thick $primary;
        padding: 1 2;
    }

    SortDialog RadioSet {
        width: 100%;
        height: auto;
        margin: 1 0;
    }

    SortDialog Label {
        margin: 1 0;
        width: 100%;
    }

    SortDialog .title {
        text-style: bold;
        margin-bottom: 1;
    }
    """

    def __init__(self, current_mode: SortMode, current_order: SortOrder):
        """Initialize the dialog with current settings."""
        super().__init__()
        self.current_mode = current_mode
        self.current_order = current_order

    def compose(self) -> ComposeResult:
        """Compose the dialog widgets."""
        with Container():
            yield Label("Select Sort Mode", classes="title")

            with RadioSet(id="sort-modes"):
                yield RadioButton("Name", value=True if self.current_mode == SortMode.NAME else False)
                yield RadioButton(
                    "Creation Date",
                    value=True if self.current_mode == SortMode.CREATED else False,
                )
                yield RadioButton(
                    "Last Accessed",
                    value=True if self.current_mode == SortMode.ACCESSED else False,
                )
                yield RadioButton(
                    "Last Modified",
                    value=True if self.current_mode == SortMode.MODIFIED else False,
                )
                yield RadioButton("Size", value=True if self.current_mode == SortMode.SIZE else False)
                yield RadioButton(
                    "Extension",
                    value=True if self.current_mode == SortMode.EXTENSION else False,
                )

            yield Label("Sort Order:", classes="title")
            with RadioSet(id="sort-order"):
                yield RadioButton(
                    "Ascending ↓",
                    value=True if self.current_order == SortOrder.ASCENDING else False,
                )
                yield RadioButton(
                    "Descending ↑",
                    value=True if self.current_order == SortOrder.DESCENDING else False,
                )

            yield Label("[Enter] Select  [Escape] Cancel", classes="help")

    def on_mount(self) -> None:
        """Set initial focus."""
        self.query_one("#sort-modes").focus()

    @on(RadioSet.Changed)
    def on_radio_changed(self, event: RadioSet.Changed) -> None:
        """Handle radio selection."""
        pass  # Just track the selection

    def action_submit(self) -> None:
        """Submit the selected values."""
        # Get selected sort mode
        mode_set = self.query_one("#sort-modes", RadioSet)
        mode_index = mode_set.pressed_index
        if mode_index is not None:
            modes = list(SortMode)
            selected_mode = modes[mode_index]
        else:
            selected_mode = self.current_mode

        # Get selected sort order
        order_set = self.query_one("#sort-order", RadioSet)
        order_index = order_set.pressed_index
        if order_index is not None:
            selected_order = SortOrder.ASCENDING if order_index == ASCENDING_ORDER_INDEX else SortOrder.DESCENDING
        else:
            selected_order = self.current_order

        self.dismiss((selected_mode, selected_order))

    def on_key(self, event: Any) -> None:
        """Handle key events."""
        if event.key == "enter":
            self.action_submit()
        elif event.key == "escape":
            self.dismiss(None)


class CustomDirectoryTree(DirectoryTree):
    """Extended DirectoryTree with sorting capabilities and file info display."""

    tree_sort_mode = reactive(SortMode.NAME)
    tree_sort_order = reactive(SortOrder.ASCENDING)

    def __init__(self, path: str, **kwargs: Any) -> None:
        super().__init__(path, **kwargs)
        self._original_path = path

    def format_file_size(self, size: int) -> str:
        """Format file size in human-readable format with locale support."""
        if size == 0:
            return "0B"

        size_float = float(size)
        for unit in FILE_SIZE_UNITS[:-1]:  # All units except PB
            if size_float < FILE_SIZE_UNIT:
                if unit == "B":
                    # For bytes, use integer with thousand separators
                    try:
                        return f"{locale.format_string('%d', int(size_float), grouping=True)}B"
                    except Exception:
                        return f"{int(size_float):,}B"
                else:
                    # For other units, use 2 decimal places
                    try:
                        return f"{locale.format_string('%.2f', size_float, grouping=True)}{unit}"
                    except Exception:
                        return f"{size_float:,.2f}{unit}"
            size_float /= FILE_SIZE_UNIT
        # If we get here, it's in PB
        try:
            return f"{locale.format_string('%.2f', size_float, grouping=True)}{FILE_SIZE_UNITS[-1]}"
        except Exception:
            return f"{size_float:,.2f}{FILE_SIZE_UNITS[-1]}"

    def format_date(self, timestamp: float) -> str:
        """Format timestamp as readable date with emoji in 24h format."""
        dt = datetime.fromtimestamp(timestamp)
        # Fixed format: 📆YYYY-MM-DD 🕚HH:MM:SS
        return f"📆{dt.strftime('%Y-%m-%d')} 🕚{dt.strftime('%H:%M:%S')}"

    def get_file_color_and_suffix(self, path: Path, file_stat: os.stat_result) -> Tuple[str, str]:
        """Get color style and suffix for file based on type (similar to ls -F --color).

        Returns:
            Tuple of (color_style, suffix)
        """
        # Check symlink first
        if path.is_symlink():
            try:
                # Check if symlink is broken
                path.stat()
                return "bright_cyan", "@"
            except (OSError, IOError):
                return "bright_red", "@"

        # Directory
        if path.is_dir():
            return "bright_blue", "/"

        # Check if executable
        if file_stat.st_mode & (stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH):
            return "bright_green", "*"

        # Socket
        if stat.S_ISSOCK(file_stat.st_mode):
            return "yellow", "="

        # Named pipe (FIFO)
        if stat.S_ISFIFO(file_stat.st_mode):
            return "cyan", "|"

        # Check extensions for special coloring
        ext = path.suffix.lower()
        if ext in [".jpg", ".jpeg", ".png", ".gif", ".bmp", ".svg"]:
            return "magenta", ""
        elif ext in [".tar", ".gz", ".zip", ".7z", ".rar", ".bz2"]:
            return "bright_red", ""
        elif ext in [".mp3", ".mp4", ".avi", ".mkv", ".wav", ".flac"]:
            return "bright_magenta", ""

        # Regular file
        return "white", ""

    def format_filename_with_quotes(self, filename: str) -> str:
        """Add quotes around filenames with spaces or special characters."""
        # Characters that require quoting
        special_chars = " \t\n\r!$&'()*,:;<=>?@[\\]^`{|}~"

        if any(char in filename for char in special_chars):
            # Escape existing quotes and backslashes
            escaped = filename.replace("\\", "\\\\").replace('"', '\\"')
            return f'"{escaped}"'
        return filename

    def has_venv(self, dir_path: Path) -> bool:
        """Check if directory contains a Python virtual environment."""
        if not dir_path.is_dir():
            return False

        # Common venv indicators
        venv_indicators = ["pyvenv.cfg", "bin/activate", "Scripts/activate.bat", "bin/python", "Scripts/python.exe"]

        for indicator in venv_indicators:
            if (dir_path / indicator).exists():
                return True
        return False

    def _render_root_label(self) -> Text:
        """Render the root node label with directory information."""
        try:
            current_dir = Path(self._original_path)
            label = Text()

            # Directory name with proper formatting
            dir_name = self.format_filename_with_quotes(current_dir.name or str(current_dir))
            label.append(f"{dir_name}/", style="bright_blue bold")

            # Add venv indicator
            if self.has_venv(current_dir):
                label.append(" ✨", style="bright_yellow")

            # Add read-only indicator
            if not os.access(current_dir, os.W_OK):
                label.append(" 🔒", style="bright_red")

            # Try to get directory stats
            try:
                dir_stat = current_dir.stat()

                # Add directory indicator
                label.append("  <DIR>", style="dim cyan")

                # Add modification date
                date_str = self.format_date(dir_stat.st_mtime)
                label.append(f"  {date_str}", style="dim yellow")
            except Exception:
                pass

            return label
        except Exception:
            return Text("Current Directory", style="bright_blue bold")

    def render_label(self, node: Any, base_style: Any, style: Any) -> Text:
        """Render node label with additional file information."""
        # Skip if no data
        if not node.data:
            return Text("Unknown")

        # Special handling for root node
        if node.parent is None:
            return self._render_root_label()

        try:
            # Get path from node data
            if hasattr(node.data, "path"):
                file_path = Path(node.data.path)
            else:
                file_path = Path(str(node.data))

            # Get file stats
            try:
                file_stat = file_path.lstat()  # Use lstat to not follow symlinks
                is_dir = file_path.is_dir()
            except (OSError, PermissionError):
                # Return simple label if we can't access
                return Text(file_path.name, style="dim red")

            # Get color and suffix based on file type
            color_style, suffix = self.get_file_color_and_suffix(file_path, file_stat)

            # Create new label with file info
            new_label = Text()

            # Format filename with quotes if needed
            filename = self.format_filename_with_quotes(file_path.name)

            # Add filename with color and suffix
            new_label.append(filename, style=color_style)
            if suffix:
                new_label.append(suffix, style=color_style)

            # Add venv indicator for directories
            if is_dir and self.has_venv(file_path):
                new_label.append(" ✨", style="bright_yellow")

            # Add lock icon for read-only files
            if not os.access(file_path, os.W_OK):
                new_label.append(" 🔒", style="bright_red")

            # Add file size
            if is_dir:
                new_label.append("  <DIR>", style="dim cyan")
            else:
                size_str = self.format_file_size(file_stat.st_size)
                new_label.append(f"  {size_str}", style="dim cyan")

            # Add modification date
            date_str = self.format_date(file_stat.st_mtime)
            new_label.append(f"  {date_str}", style="dim yellow")

            return new_label

        except Exception:
            # If anything goes wrong, return a simple label
            return Text(str(node.data), style="dim red")

    def sort_children_by_mode(self, node: Any) -> None:
        """Sort children of a node based on current sort settings."""
        if not hasattr(node, "_children") or not node._children:
            return

        # Get file info for each child
        children_info = []
        for child in node._children:
            try:
                # child.data is a DirEntry object, get its path
                if hasattr(child.data, "path"):
                    path = Path(child.data.path)
                else:
                    path = Path(str(child.data))
                stat = path.stat()

                # Extract sort key based on mode
                sort_key: str | float | int
                if self.tree_sort_mode == SortMode.NAME:
                    sort_key = path.name.lower()
                elif self.tree_sort_mode == SortMode.CREATED:
                    sort_key = stat.st_ctime
                elif self.tree_sort_mode == SortMode.ACCESSED:
                    sort_key = stat.st_atime
                elif self.tree_sort_mode == SortMode.MODIFIED:
                    sort_key = stat.st_mtime
                elif self.tree_sort_mode == SortMode.SIZE:
                    sort_key = stat.st_size if path.is_file() else DEFAULT_DIR_SIZE
                elif self.tree_sort_mode == SortMode.EXTENSION:
                    sort_key = path.suffix.lower() if path.is_file() else ""
                else:
                    sort_key = path.name.lower()

                children_info.append((child, sort_key, path.is_dir()))
            except (OSError, AttributeError):
                # If stat fails, use name as fallback
                children_info.append((child, str(child.label).lower(), False))

        # Sort: directories first, then by sort key
        reverse = self.tree_sort_order == SortOrder.DESCENDING
        children_info.sort(key=lambda x: (not x[2], x[1]), reverse=reverse)

        # Update children order
        node._children = [info[0] for info in children_info]

    def on_mount(self) -> None:
        """Called when widget is mounted."""
        super().on_mount()  # type: ignore[no-untyped-call]
        # Apply initial sorting
        self.refresh_sorting()

    def watch_tree_sort_mode(self, old_mode: SortMode, new_mode: SortMode) -> None:
        """React to sort mode changes."""
        self.refresh_sorting()

    def watch_tree_sort_order(self, old_order: SortOrder, new_order: SortOrder) -> None:
        """React to sort order changes."""
        self.refresh_sorting()

    def set_sort_mode(self, mode: SortMode) -> None:
        """Set sort mode."""
        self.tree_sort_mode = mode

    def set_sort_order(self, order: SortOrder) -> None:
        """Set sort order."""
        self.tree_sort_order = order

    def refresh_sorting(self) -> None:
        """Refresh the sorting of all expanded nodes."""

        # Sort all expanded nodes
        def sort_node(node: Any) -> None:
            if node.is_expanded:
                self.sort_children_by_mode(node)
                for child in node.children:
                    sort_node(child)

        sort_node(self.root)
        self.refresh()

    def on_directory_tree_directory_selected(self, event: Any) -> None:
        """Apply sorting when directory is expanded."""
        # Find the node that was selected
        node = event.node
        # Toggle the expansion state
        if node.is_expanded:
            node.collapse()
        else:
            node.expand()
            # Sort the newly loaded children
            self.sort_children_by_mode(node)
        self.refresh()


class FileBrowserApp(App[Optional[str]]):
    """A Textual app for browsing and selecting files with sorting options.

    The app returns the selected file path via app.return_value.
    """

    CSS = """
    CustomDirectoryTree {
        background: $surface;
        color: $text;
        padding: 1;
        border: solid $primary;
        height: 100%;
    }

    #path-display {
        background: $surface;
        color: $text-muted;
        padding: 0 1;
        height: 1;
        dock: top;
    }

    #navigation-bar {
        dock: top;
        height: 3;
        background: $boost;
        padding: 0 1;
    }

    #navigation-bar Button {
        margin: 0 1;
    }
    """

    BINDINGS = [
        Binding("q", "quit", "Quit", priority=True),
        Binding("escape", "quit", "Quit"),
        Binding("s", "show_sort_dialog", "Sort", show=True),
        Binding("u", "go_parent", "Up", show=True),
        Binding("backspace", "go_parent", "Parent"),
        Binding("h", "go_home", "Home", show=True),
        Binding("r", "go_root", "Root", show=True),
    ]

    def __init__(self, start_path: str = "."):
        """Initialize the file browser.

        Args:
            start_path: The directory to start browsing from.
        """
        super().__init__()
        # Validate start path
        try:
            path = Path(start_path).resolve()
            if not path.exists():
                path = Path.cwd()
            elif not path.is_dir():
                path = path.parent
            self.start_path = path
        except (OSError, ValueError):
            self.start_path = Path.cwd()

        self.selected_file: Optional[str] = None
        self.current_sort_mode = SortMode.NAME
        self.current_sort_order = SortOrder.ASCENDING
        self.current_path = self.start_path

    def compose(self) -> ComposeResult:
        """Create child widgets for the app."""
        yield Header()
        with Horizontal(id="navigation-bar"):
            yield Button("🔼 [u]P[/u]arent", id="parent-button", variant="primary")
            yield Button("🏠 [u]H[/u]ome", id="home-button", variant="default")
            yield Button("⏫ [u]R[/u]oot", id="root-button", variant="default")
        yield Label("", id="path-display")
        with Vertical(id="tree-container"):
            yield CustomDirectoryTree(str(self.start_path), id="directory-tree")
        yield Footer()

    def on_mount(self) -> None:
        """Called when the app is mounted."""
        self.title = "Select File Browser"
        self.sub_title = "Navigate with arrows, Enter to select, Q to quit"

        # Set initial focus to directory tree
        tree = self.query_one("#directory-tree", CustomDirectoryTree)
        tree.focus()

        # Update path display for root
        self._update_path_display(str(self.start_path))

    @on(DirectoryTree.FileSelected)
    def on_file_selected(self, event: DirectoryTree.FileSelected) -> None:
        """Handle file selection.

        Args:
            event: The file selection event containing the selected path.
        """
        self.selected_file = str(event.path)
        self.exit(self.selected_file)

    @on(DirectoryTree.NodeHighlighted)
    def on_node_highlighted(self, event: DirectoryTree.NodeHighlighted[Any]) -> None:
        """Update path display when node is highlighted."""
        if event.node and event.node.data:
            self._update_path_display(str(event.node.data))

    def _update_path_display(self, path: str) -> None:
        """Update the path display label."""
        path_label = self.query_one("#path-display", Label)
        path_label.update(f"Path: {path}")

    async def action_quit(self) -> None:
        """Quit the application without selecting a file."""
        self.exit(None)

    async def action_show_sort_dialog(self) -> None:
        """Show the sort options dialog."""
        dialog = SortDialog(self.current_sort_mode, self.current_sort_order)
        result = await self.push_screen(dialog)  # type: ignore[func-returns-value]

        if result:
            # Update sort settings
            self.current_sort_mode, self.current_sort_order = result

            # Update the tree's sort settings
            tree = self.query_one("#directory-tree", CustomDirectoryTree)
            tree.set_sort_mode(self.current_sort_mode)
            tree.set_sort_order(self.current_sort_order)

    async def action_go_parent(self) -> None:
        """Navigate to parent directory."""
        parent = self.current_path.parent
        if parent != self.current_path:  # Check we're not already at root
            await self._change_directory(parent)

    async def action_go_home(self) -> None:
        """Navigate to home directory."""
        home = Path.home()
        await self._change_directory(home)

    async def action_go_root(self) -> None:
        """Navigate to root directory."""
        await self.on_root_button()

    @on(Button.Pressed, "#parent-button")
    async def on_parent_button(self) -> None:
        """Handle parent button click."""
        await self.action_go_parent()

    @on(Button.Pressed, "#home-button")
    async def on_home_button(self) -> None:
        """Handle home button click."""
        await self.action_go_home()

    @on(Button.Pressed, "#root-button")
    async def on_root_button(self) -> None:
        """Handle root button click."""
        # Get system root(s)
        if platform.system() == "Windows":
            # On Windows, try to find available drives
            for drive_letter in WINDOWS_DRIVE_LETTERS:
                drive_path = Path(f"{drive_letter}:\\")
                if drive_path.exists():
                    await self._change_directory(drive_path)
                    break
        else:  # Unix-like
            await self._change_directory(Path("/"))

    async def _change_directory(self, new_path: Path) -> None:
        """Change the current directory and refresh the tree."""
        if not new_path.exists() or not new_path.is_dir():
            return

        self.current_path = new_path

        # Remove old tree and create new one
        container = self.query_one("#tree-container")
        await container.query_one(CustomDirectoryTree).remove()

        # Create new tree with updated path
        new_tree = CustomDirectoryTree(str(self.current_path), id="directory-tree")
        new_tree.tree_sort_mode = self.current_sort_mode
        new_tree.tree_sort_order = self.current_sort_order
        await container.mount(new_tree)

        # Focus the new tree
        new_tree.focus()

        # Update path display
        self._update_path_display(str(self.current_path))
