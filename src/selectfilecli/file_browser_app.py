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
# - Added support for folder selection with select_files and select_dirs parameters
# - Fixed symlink detection to use lstat consistently
# - Added FileInfo return type with comprehensive file/folder information
# - Fixed edge cases: negative file sizes, Windows drive detection, filename escaping
# - Added venv detection caching for performance
# - Fixed sort dialog button handling
# - Fixed navigation bar overlapping with header using dock: top CSS property
# - Fixed path display showing function representation issue
# - Fixed directory change async black screen issue
# - Added Enter key binding to navigate into directories
# - Fixed Enter key not working in sort dialog
# - Fixed UI layout: added padding-top to main container to prevent header subtitle overlap
# - Fixed issue #4: Display <empty> placeholder when opening empty directories
# - Fixed issues #5 and #6: Implemented async loading with loading placeholders
# - Added <...loading...> placeholder with blinking effect during directory loading
# - Fixed UI responsiveness by showing placeholders immediately on expand/navigate
# - Added proper handling of loading states in render_label
# - Skip placeholders from sorting to avoid errors
# - Show root node immediately with loading placeholder during navigation
# - Fixed issue #7: Added OK and Cancel buttons to sort dialog
# - Fixed issue #7: Improved Enter key handling in sort dialog
# - Fixed issue #7: Sort dialog now properly shows current settings when opened
#

"""Textual-based file browser application."""

import os
import platform
import stat
import sys
import locale
from datetime import datetime
from pathlib import Path
from typing import Optional, Any, Tuple, Dict, Iterable
from enum import Enum
from .file_info import FileInfo

from textual import on, work
from textual.app import App, ComposeResult
from textual.reactive import reactive
from textual.widgets import Header, Footer, Label, RadioButton, RadioSet, Button
from textual.widgets._directory_tree import DirectoryTree, DirEntry
from textual.widgets._tree import TreeNode, Tree
from textual.binding import Binding
from textual.containers import Container, Horizontal, Vertical
from textual.screen import ModalScreen
from textual.worker import get_current_worker, WorkerCancelled, WorkerFailed, Worker
from rich.text import Text

# Constants
FILE_SIZE_UNIT = 1024.0
FILE_SIZE_UNITS = ["B", "KB", "MB", "GB", "TB", "PB"]
DEFAULT_DIR_SIZE = 0
ASCENDING_ORDER_INDEX = 0
WINDOWS_DRIVE_LETTERS = "CDEFGHIJKLMNOPQRSTUVWXYZAB"  # C first, then others
MAX_VENV_CACHE_SIZE = 1000  # Maximum entries in venv cache
MAX_DIR_CACHE_SIZE = 500  # Maximum entries in directory size cache
MAX_DIRECTORY_DEPTH = 100  # Maximum recursion depth for directory traversal
# UI Element Heights
NAVIGATION_BAR_HEIGHT = 3
PATH_DISPLAY_HEIGHT = 1

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

    SortDialog #button-container {
        height: 3;
        align: center middle;
        margin-top: 1;
    }

    SortDialog #button-container Button {
        margin: 0 1;
        min-width: 10;
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

            # Add button container
            with Horizontal(id="button-container"):
                yield Button("OK", variant="primary", id="ok-button")
                yield Button("Cancel", variant="default", id="cancel-button")

            yield Label("[Enter] Select  [Escape] Cancel", classes="help")

    def on_mount(self) -> None:
        """Set initial focus and properly select current values."""
        # Set the correct radio button selections based on current values
        mode_set = self.query_one("#sort-modes", RadioSet)
        order_set = self.query_one("#sort-order", RadioSet)

        # Find and toggle the correct mode button
        modes = list(SortMode)
        mode_buttons = list(mode_set.query(RadioButton))
        for i, mode in enumerate(modes):
            if mode == self.current_mode and i < len(mode_buttons):
                mode_buttons[i].value = True
                break

        # Find and toggle the correct order button
        order_buttons = list(order_set.query(RadioButton))
        if self.current_order == SortOrder.ASCENDING and len(order_buttons) > 0:
            order_buttons[0].value = True
        elif len(order_buttons) > 1:
            order_buttons[1].value = True

        # Focus on the mode selection
        mode_set.focus()

    @on(RadioSet.Changed)
    def on_radio_changed(self, event: RadioSet.Changed) -> None:
        """Handle radio selection."""
        pass  # Just track the selection

    @on(Button.Pressed, "#ok-button")
    def on_ok_pressed(self) -> None:
        """Handle OK button press."""
        self.action_submit()

    @on(Button.Pressed, "#cancel-button")
    def on_cancel_pressed(self) -> None:
        """Handle Cancel button press."""
        self.dismiss(None)

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
            # Don't prevent default behavior for radio button selection
            # Only submit if we're not in a RadioSet
            focused = self.focused
            if not isinstance(focused, RadioSet):
                event.stop()
                self.action_submit()
        elif event.key == "escape":
            event.stop()
            self.dismiss(None)


class CustomDirectoryTree(DirectoryTree):
    """Extended DirectoryTree with sorting capabilities and file info display."""

    tree_sort_mode = reactive(SortMode.NAME)
    tree_sort_order = reactive(SortOrder.ASCENDING)
    allow_file_select = reactive(True)
    allow_dir_select = reactive(False)

    def __init__(self, path: str, **kwargs: Any) -> None:
        super().__init__(path, **kwargs)
        self._original_path = path
        self._venv_cache: Dict[str, bool] = {}  # Cache for venv detection
        self._dir_size_cache: Dict[str, int] = {}  # Cache for directory sizes

    def format_file_size(self, size: int) -> str:
        """Format file size in human-readable format with locale support."""
        if size < 0:
            return "Invalid"
        if size == 0:
            return "0 B"

        size_float = float(size)
        for unit in FILE_SIZE_UNITS[:-1]:  # All units except PB
            if size_float < FILE_SIZE_UNIT:
                if unit == "B":
                    # For bytes, use integer with thousand separators
                    try:
                        return f"{locale.format_string('%d', int(size_float), grouping=True)} B"
                    except Exception:
                        return f"{int(size_float):,} B"
                else:
                    # For other units, use 2 decimal places
                    try:
                        return f"{locale.format_string('%.2f', size_float, grouping=True)} {unit}"
                    except Exception:
                        return f"{size_float:,.2f} {unit}"
            size_float /= FILE_SIZE_UNIT
        # If we get here, it's in PB
        try:
            return f"{locale.format_string('%.2f', size_float, grouping=True)} {FILE_SIZE_UNITS[-1]}"
        except Exception:
            return f"{size_float:,.2f} {FILE_SIZE_UNITS[-1]}"

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
        if stat.S_ISLNK(file_stat.st_mode):
            try:
                # Check if symlink is broken by trying to stat the target
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
        """Add quotes around filenames with spaces or special characters.

        Args:
            filename: The filename to format

        Returns:
            Filename with quotes if needed
        """
        # Characters that require quoting
        special_chars = " \t\n\r!$&'()*,:;<=>?@[\\]^`{|}~\""

        if any(char in filename for char in special_chars):
            # Escape backslashes, quotes, and tabs for shell safety
            escaped = filename.replace("\\", "\\\\").replace('"', '\\"').replace("\t", "\\t")
            return f'"{escaped}"'
        return filename

    def _manage_cache(self, cache: Dict[str, Any], key: str, max_size: int) -> None:
        """Manage LRU cache eviction.

        Args:
            cache: The cache dictionary to manage
            key: The key being accessed/added
            max_size: Maximum cache size
        """
        if len(cache) >= max_size and key not in cache:
            # Evict oldest entry (first key)
            oldest_key = next(iter(cache))
            del cache[oldest_key]

    def has_venv(self, dir_path: Path) -> bool:
        """Check if directory contains a Python virtual environment."""
        # Check cache first
        path_str = str(dir_path)
        if path_str in self._venv_cache:
            return self._venv_cache[path_str]

        result = False
        if dir_path.is_dir():
            # Common venv indicators
            venv_indicators = ["pyvenv.cfg", "bin/activate", "Scripts/activate.bat", "bin/python", "Scripts/python.exe"]

            for indicator in venv_indicators:
                if (dir_path / indicator).exists():
                    result = True
                    break

        # Manage cache size before adding
        self._manage_cache(self._venv_cache, path_str, MAX_VENV_CACHE_SIZE)

        # Cache the result
        self._venv_cache[path_str] = result
        return result

    def _get_path_from_node_data(self, data: Any) -> Optional[Path]:
        """Extract path from node data with consistent handling."""
        try:
            if hasattr(data, "path"):
                return Path(data.path)
            else:
                return Path(str(data))
        except Exception:
            return None

    def calculate_directory_size(self, dir_path: Path, depth: int = 0, max_items: int = 1000) -> int:
        """Calculate total size of directory recursively with caching and depth protection.

        Args:
            dir_path: Directory to calculate size for
            depth: Current recursion depth (internal parameter)
            max_items: Maximum number of items to process (to prevent hanging)

        Returns:
            Total size in bytes, or 0 if cannot be calculated
        """
        # Protect against infinite recursion
        if depth > MAX_DIRECTORY_DEPTH:
            return 0

        path_str = str(dir_path)

        # Check cache first
        if path_str in self._dir_size_cache:
            return self._dir_size_cache[path_str]

        total_size = 0
        items_processed = 0
        try:
            for entry in dir_path.iterdir():
                # Limit the number of items to prevent hanging
                if items_processed >= max_items:
                    # Stop processing if we've hit the limit
                    break
                items_processed += 1

                try:
                    # Use lstat to avoid following symlinks
                    stat_info = entry.lstat()
                    if stat.S_ISREG(stat_info.st_mode):
                        # Regular file - add its size
                        total_size += stat_info.st_size
                    elif stat.S_ISDIR(stat_info.st_mode):
                        # Directory - recursively calculate its size with incremented depth
                        total_size += self.calculate_directory_size(entry, depth + 1, max_items)
                    # Skip symlinks, special files, etc.
                except (PermissionError, OSError):
                    # Skip files/dirs we can't access
                    continue
        except (PermissionError, OSError):
            # Can't read directory
            pass

        # Manage cache size before adding
        self._manage_cache(self._dir_size_cache, path_str, MAX_DIR_CACHE_SIZE)

        # Cache the result
        self._dir_size_cache[path_str] = total_size
        return total_size

    def _get_file_stat_info(self, file_path: Path) -> tuple[Any, bool, bool]:
        """Get file stat information.

        Args:
            file_path: Path to get stats for

        Returns:
            Tuple of (stat_result, is_dir, is_accessible)
        """
        try:
            file_stat = file_path.lstat()
            is_dir = file_path.is_dir()
            return file_stat, is_dir, True
        except (OSError, PermissionError):
            return None, False, False

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

            # Try to get directory stats and size
            try:
                dir_stat = current_dir.stat()

                # Calculate total directory size
                total_size = self.calculate_directory_size(current_dir)
                size_str = self.format_file_size(total_size)
                label.append(f"  {size_str}", style="dim cyan")

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
        # Special handling for <empty> placeholder
        if not node.data and hasattr(node, "label") and str(node.label) == "<empty>":
            return Text("<empty>", style="dim italic")

        # Skip if no data
        if not node.data:
            return Text("Unknown")

        # Special handling for root node
        if node.parent is None:
            return self._render_root_label()

        try:
            # Get path from node data
            file_path = self._get_path_from_node_data(node.data)
            if not file_path:
                return Text("Unknown", style="dim red")

            # Special handling for loading placeholder
            if str(file_path) == "<...loading...>":
                # Create blinking loading text
                loading_text = Text("<...loading...>", style="bright_yellow blink")
                return loading_text

            # Get file stats
            try:
                file_stat = file_path.lstat()  # Use lstat to not follow symlinks
                is_dir = file_path.is_dir()
            except (OSError, PermissionError):
                # Return simple label if we can't access
                return Text(file_path.name if file_path else "Unknown", style="dim red")

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
                # Skip placeholders from sorting
                if not child.data or (hasattr(child, "label") and str(child.label) in ["<empty>", "<...loading...>"]):
                    continue

                # Get path from child data
                path = self._get_path_from_node_data(child.data)
                if not path or str(path) == "<...loading...>":
                    continue
                stat = path.lstat()  # Use lstat for consistency

                # Extract sort key based on mode using strategy pattern
                sort_key_extractors = {
                    SortMode.NAME: lambda p, s: p.name.lower(),
                    SortMode.CREATED: lambda p, s: s.st_ctime,
                    SortMode.ACCESSED: lambda p, s: s.st_atime,
                    SortMode.MODIFIED: lambda p, s: s.st_mtime,
                    SortMode.SIZE: lambda p, s: s.st_size if p.is_file() else DEFAULT_DIR_SIZE,
                    SortMode.EXTENSION: lambda p, s: p.suffix.lower() if p.is_file() else "",
                }

                extractor = sort_key_extractors.get(self.tree_sort_mode, lambda p, s: p.name.lower())
                sort_key = extractor(path, stat)  # type: ignore[no-untyped-call]

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
        """Handle directory selection - either select it or expand/collapse."""
        # This is handled by the app's on_directory_selected method now
        pass

    @on(Tree.NodeExpanded)
    def on_node_expanded(self, event: Tree.NodeExpanded[DirEntry]) -> None:
        """Handle when a tree node is expanded to show loading placeholder.

        This method intercepts the node expansion to show loading state.
        """
        node = event.node
        if node and node.data:
            # Check if this is a valid path that needs loading
            path = self._get_path_from_node_data(node.data)
            if path and path.is_dir() and not node.children:
                # Show loading placeholder immediately before the actual loading starts
                self._add_loading_placeholder(node)
                # Force a refresh to show the placeholder
                self.refresh()

        # Don't call super() as this is an event handler, not an override

    def on_key(self, event: Any) -> None:
        """Handle key events in the directory tree."""
        if event.key == "enter" and self.cursor_node:
            # Check if we're on a directory
            path = self._get_path_from_node_data(self.cursor_node.data)
            if path and path.is_dir():
                # Check if we should navigate into it
                # For now, let the default behavior handle it
                pass

    def _populate_node(self, node: TreeNode[DirEntry], content: Iterable[Path]) -> None:
        """Populate the given tree node with the given directory content.

        This override handles empty directories by showing an <empty> placeholder.

        Args:
            node: The Tree node to populate.
            content: The collection of `Path` objects to populate the node with.
        """
        node.remove_children()

        # Convert to list to check if empty
        content_list = list(content)

        if not content_list:
            # Directory is empty, add a placeholder
            node.add_leaf("<empty>", data=None)
        else:
            # Normal population for non-empty directories
            for path in content_list:
                node.add(
                    path.name,
                    data=DirEntry(path),
                    allow_expand=self._safe_is_dir(path),
                )

        node.expand()

    def _add_loading_placeholder(self, node: TreeNode[DirEntry]) -> TreeNode[DirEntry]:
        """Add a loading placeholder to a node.

        Args:
            node: The node to add the placeholder to.

        Returns:
            The loading placeholder node.
        """
        # Remove existing children first
        node.remove_children()
        # Add loading placeholder with special data
        loading_node = node.add_leaf("", data=DirEntry(Path("<...loading...>")))
        return loading_node

    @work(exclusive=True)
    async def _loader(self) -> None:
        """Background loading queue processor.

        This override ensures empty directories still get populated with a placeholder.
        """
        worker = get_current_worker()
        while not worker.is_cancelled:
            # Get the next node that needs loading off the queue.
            node = await self._load_queue.get()
            content: list[Path] = []
            async with self.lock:
                cursor_node = self.cursor_node
                try:
                    # Load the content of the directory associated with that node.
                    content = await self._load_directory(node).wait()
                except WorkerCancelled:
                    # The worker was cancelled, we should exit.
                    break
                except WorkerFailed:
                    # This particular worker failed to start.
                    pass
                else:
                    # Always populate the node, even if content is empty
                    self._populate_node(node, content)
                    if cursor_node is not None:
                        self.move_cursor(cursor_node, animate=False)
                finally:
                    # Mark this iteration as done.
                    self._load_queue.task_done()


class FileBrowserApp(App[Optional[FileInfo]]):
    """A Textual app for browsing and selecting files with sorting options.

    The app returns FileInfo object with comprehensive file/folder information.
    """

    CSS = """
    FileBrowserApp {
        layers: base;
    }

    #main-container {
        width: 100%;
        height: 100%;
        layer: base;
        layout: vertical;
        /* Add top padding to account for Header with subtitle (3 units tall) */
        padding-top: 1;
    }

    #navigation-bar {
        height: 3;
        background: $boost;
        padding: 0 1;
        width: 100%;
        layout: horizontal;
    }

    #path-display {
        background: $surface;
        color: yellow;
        padding: 0 1;
        height: 1;
        width: 100%;
    }

    #tree-container {
        width: 100%;
        height: 1fr;
    }

    CustomDirectoryTree {
        background: $surface;
        color: $text;
        padding: 1;
        border: solid $primary;
        width: 100%;
        height: 100%;
    }

    #navigation-bar Button {
        margin: 0 1;
        min-width: 16;
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
        Binding("d", "select_current_directory", "Select Dir", show=False),
        Binding("enter", "navigate_or_select", "Navigate/Select", show=False),
    ]

    def __init__(self, start_path: str = ".", select_files: bool = True, select_dirs: bool = False):
        """Initialize the file browser.

        Args:
            start_path: The directory to start browsing from.
            select_files: Whether to allow file selection.
            select_dirs: Whether to allow directory selection.
        """
        super().__init__()

        # Set title and subtitle immediately
        self.title = "Select File Browser"

        # Update subtitle based on what can be selected
        select_types = []
        if select_files:
            select_types.append("files")
        if select_dirs:
            select_types.append("folders")
        select_text = " or ".join(select_types)
        if select_dirs:
            self.sub_title = f"Navigate with arrows, Enter to select {select_text}, D to select dir, Q to quit"
        else:
            self.sub_title = f"Navigate with arrows, Enter to select {select_text}, Q to quit"

        # Validate start path
        try:
            path = Path(start_path).resolve()
            if not path.exists():
                path = Path.cwd()
            elif not path.is_dir():
                path = path.parent
            self.start_path = path
        except (OSError, ValueError, RuntimeError):
            # RuntimeError can occur with circular symlinks
            self.start_path = Path.cwd()

        self.selected_item: Optional[FileInfo] = None
        self.select_files = select_files
        self.select_dirs = select_dirs
        self.current_sort_mode = SortMode.NAME
        self.current_sort_order = SortOrder.ASCENDING
        self.current_path = self.start_path

    def compose(self) -> ComposeResult:
        """Create child widgets for the app."""
        yield Header()
        with Vertical(id="main-container"):
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
        # Set initial focus to directory tree
        tree = self.query_one("#directory-tree", CustomDirectoryTree)
        tree.allow_file_select = self.select_files
        tree.allow_dir_select = self.select_dirs
        tree.focus()

        # Update path display for root
        self._update_path_display(str(self.start_path))

    @on(DirectoryTree.FileSelected)
    def on_file_selected(self, event: DirectoryTree.FileSelected) -> None:
        """Handle file selection.

        Args:
            event: The file selection event containing the selected path.
        """
        if self.select_files:
            self._create_file_info(Path(event.path), is_file=True)

    @on(DirectoryTree.DirectorySelected)
    def on_directory_selected(self, event: DirectoryTree.DirectorySelected) -> None:
        """Handle directory selection.

        Args:
            event: The directory selection event containing the selected path.
        """
        # Get the path from the event
        tree = self.query_one("#directory-tree", CustomDirectoryTree)
        node = event.node

        # Check if this is a double-click or Enter key navigation
        path = tree._get_path_from_node_data(node.data)
        if path and path.is_dir():
            # Check if Enter key was pressed (navigate into directory)
            # For now, just toggle expand/collapse
            if node.is_expanded:
                node.collapse()
            else:
                node.expand()
                tree.sort_children_by_mode(node)
            tree.refresh()

    def _create_file_info(self, path: Path, is_file: bool) -> None:
        """Create FileInfo object and exit the app."""
        try:
            # Get file stats
            stat_result = path.lstat()
            is_symlink = stat.S_ISLNK(stat_result.st_mode)
            symlink_broken = False

            if is_symlink:
                try:
                    path.stat()  # Check if target exists
                except (OSError, IOError):
                    symlink_broken = True

            # Create FileInfo object
            info = FileInfo(
                file_path=path if is_file else None,
                folder_path=path if not is_file else None,
                last_modified_datetime=datetime.fromtimestamp(stat_result.st_mtime),
                creation_datetime=datetime.fromtimestamp(stat_result.st_ctime),
                size_in_bytes=stat_result.st_size if is_file else self._calculate_dir_size(path),
                readonly=not os.access(path, os.W_OK),
                folder_has_venv=self._check_venv(path) if not is_file else None,
                is_symlink=is_symlink,
                symlink_broken=symlink_broken,
            )

            self.selected_item = info
            self.exit(self.selected_item)
        except (OSError, IOError, PermissionError, ValueError) as e:
            # If we can't get file info, exit without selection
            # Log the error for debugging if needed
            self.exit(None)

    def _check_venv(self, path: Path) -> bool:
        """Check if directory contains a virtual environment."""
        tree = self.query_one("#directory-tree", CustomDirectoryTree)
        return tree.has_venv(path)

    def _calculate_dir_size(self, path: Path) -> int:
        """Calculate directory size."""
        tree = self.query_one("#directory-tree", CustomDirectoryTree)
        return tree.calculate_directory_size(path)

    @on(DirectoryTree.NodeHighlighted)
    def on_node_highlighted(self, event: DirectoryTree.NodeHighlighted[Any]) -> None:
        """Update path display when node is highlighted."""
        if event.node and event.node.data:
            # Handle different data types properly
            tree = self.query_one("#directory-tree", CustomDirectoryTree)
            path = tree._get_path_from_node_data(event.node.data)
            if path:
                self._update_path_display(str(path))

    def _update_path_display(self, path: str) -> None:
        """Update the path display label."""
        path_label = self.query_one("#path-display", Label)
        # Format the path properly - ensure it's a string
        if hasattr(path, "__call__"):
            # If it's a function/method, don't display it
            return
        path_str = str(path) if path else ""
        path_label.update(f"Path: {path_str}")

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

    async def action_select_current_directory(self) -> None:
        """Select the current highlighted directory."""
        if not self.select_dirs:
            return

        # Get the currently highlighted node
        tree = self.query_one("#directory-tree", CustomDirectoryTree)
        if tree.cursor_node and tree.cursor_node.data:
            path = tree._get_path_from_node_data(tree.cursor_node.data)
            if path and path.is_dir():
                self._create_file_info(path, is_file=False)

    async def action_navigate_or_select(self) -> None:
        """Navigate into directory with Enter key or select file."""
        tree = self.query_one("#directory-tree", CustomDirectoryTree)
        if not tree.cursor_node or not tree.cursor_node.data:
            return

        path = tree._get_path_from_node_data(tree.cursor_node.data)
        if not path:
            return

        if path.is_dir():
            # Navigate into the directory
            await self._change_directory(path)
        elif path.is_file() and self.select_files:
            # Select the file
            self._create_file_info(path, is_file=True)

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
            # On Windows, use current drive root for better performance
            try:
                current_drive = Path.cwd().drive
                if current_drive:
                    await self._change_directory(Path(current_drive + "\\"))
                else:
                    # Fallback to C: drive
                    c_drive = Path("C:\\")
                    if c_drive.exists():
                        await self._change_directory(c_drive)
            except Exception:
                # Last resort: try common drives
                for drive_letter in ["C", "D", "E"]:
                    drive_path = Path(f"{drive_letter}:\\")
                    try:
                        if drive_path.exists():
                            await self._change_directory(drive_path)
                            break
                    except (OSError, PermissionError):
                        continue
        else:  # Unix-like
            await self._change_directory(Path("/"))

    async def _change_directory(self, new_path: Path) -> None:
        """Change the current directory and refresh the tree."""
        if not new_path.exists() or not new_path.is_dir():
            return

        self.current_path = new_path

        # Get the container
        container = self.query_one("#tree-container")
        old_tree = container.query_one(CustomDirectoryTree)

        # Create new tree with updated path BEFORE removing old one
        new_tree = CustomDirectoryTree(str(self.current_path), id="directory-tree")
        new_tree.tree_sort_mode = self.current_sort_mode
        new_tree.tree_sort_order = self.current_sort_order
        new_tree.allow_file_select = self.select_files
        new_tree.allow_dir_select = self.select_dirs

        # Remove old tree and mount new one
        await old_tree.remove()
        await container.mount(new_tree)

        # Show loading placeholder in root immediately
        if new_tree.root:
            new_tree._add_loading_placeholder(new_tree.root)
            new_tree.refresh()

        # Focus the new tree after mounting
        new_tree.focus()

        # Update path display
        self._update_path_display(str(self.current_path))

        # Force the tree to start loading
        new_tree.reload()
