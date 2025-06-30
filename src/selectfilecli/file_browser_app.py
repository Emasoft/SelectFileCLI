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
#

"""Textual-based file browser application."""

import os
from pathlib import Path
from typing import Optional, List, Literal
from datetime import datetime
from enum import Enum

from textual import on, work
from textual.app import App, ComposeResult
from textual.widgets import Header, Footer, Label, Static, RadioButton, RadioSet
from textual.widgets._directory_tree import DirectoryTree
from textual.binding import Binding
from textual.reactive import reactive
from textual.containers import Container, Horizontal, Vertical
from textual.message import Message
from textual.screen import ModalScreen


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
                yield RadioButton("Creation Date", value=True if self.current_mode == SortMode.CREATED else False)
                yield RadioButton("Last Accessed", value=True if self.current_mode == SortMode.ACCESSED else False)
                yield RadioButton("Last Modified", value=True if self.current_mode == SortMode.MODIFIED else False)
                yield RadioButton("Size", value=True if self.current_mode == SortMode.SIZE else False)
                yield RadioButton("Extension", value=True if self.current_mode == SortMode.EXTENSION else False)

            yield Label("Sort Order:", classes="title")
            with RadioSet(id="sort-order"):
                yield RadioButton("Ascending ↓", value=True if self.current_order == SortOrder.ASCENDING else False)
                yield RadioButton("Descending ↑", value=True if self.current_order == SortOrder.DESCENDING else False)

            yield Label("[Enter] Select  [Escape] Cancel", classes="help")

    def on_mount(self):
        """Set initial focus."""
        self.query_one("#sort-modes").focus()

    @on(RadioSet.Changed)
    def on_radio_changed(self, event: RadioSet.Changed):
        """Handle radio selection."""
        pass  # Just track the selection

    def action_submit(self):
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
            selected_order = SortOrder.ASCENDING if order_index == 0 else SortOrder.DESCENDING
        else:
            selected_order = self.current_order

        self.dismiss((selected_mode, selected_order))

    def on_key(self, event):
        """Handle key events."""
        if event.key == "enter":
            self.action_submit()
        elif event.key == "escape":
            self.dismiss(None)


class CustomDirectoryTree(DirectoryTree):
    """Extended DirectoryTree with sorting capabilities."""

    def __init__(self, path: str, **kwargs):
        super().__init__(path, **kwargs)
        self._original_path = path
        # Initialize reactive attributes after parent init
        self.sort_mode = SortMode.NAME
        self.sort_order = SortOrder.ASCENDING

    def sort_children(self, node):
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
                if self.sort_mode == SortMode.NAME:
                    sort_key = path.name.lower()
                elif self.sort_mode == SortMode.CREATED:
                    sort_key = stat.st_ctime
                elif self.sort_mode == SortMode.ACCESSED:
                    sort_key = stat.st_atime
                elif self.sort_mode == SortMode.MODIFIED:
                    sort_key = stat.st_mtime
                elif self.sort_mode == SortMode.SIZE:
                    sort_key = stat.st_size if path.is_file() else 0
                elif self.sort_mode == SortMode.EXTENSION:
                    sort_key = path.suffix.lower() if path.is_file() else ""
                else:
                    sort_key = path.name.lower()

                children_info.append((child, sort_key, path.is_dir()))
            except (OSError, AttributeError):
                # If stat fails, use name as fallback
                children_info.append((child, str(child.label).lower(), False))

        # Sort: directories first, then by sort key
        reverse = self.sort_order == SortOrder.DESCENDING
        children_info.sort(key=lambda x: (not x[2], x[1]), reverse=reverse)

        # Update children order
        node._children = [info[0] for info in children_info]

    def on_mount(self):
        """Called when widget is mounted."""
        super().on_mount()
        # Apply initial sorting
        self.refresh_sorting()

    def set_sort_mode(self, mode: SortMode):
        """Set sort mode and refresh."""
        self.sort_mode = mode
        self.refresh_sorting()

    def set_sort_order(self, order: SortOrder):
        """Set sort order and refresh."""
        self.sort_order = order
        self.refresh_sorting()

    def refresh_sorting(self):
        """Refresh the sorting of all expanded nodes."""

        # Sort all expanded nodes
        def sort_node(node):
            if node.is_expanded:
                self.sort_children(node)
                for child in node.children:
                    sort_node(child)

        sort_node(self.root)
        self.refresh()

    def on_directory_tree_directory_selected(self, event):
        """Apply sorting when directory is expanded."""
        # Find the node that was selected
        node = event.node
        # Toggle the expansion state
        if node.is_expanded:
            node.collapse()
        else:
            node.expand()
            # Sort the newly loaded children
            self.sort_children(node)
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
    """

    BINDINGS = [
        Binding("q", "quit", "Quit", priority=True),
        Binding("escape", "quit", "Quit"),
        Binding("s", "show_sort_dialog", "Sort", show=True),
    ]

    def __init__(self, start_path: str = "."):
        """Initialize the file browser.

        Args:
            start_path: The directory to start browsing from.
        """
        super().__init__()
        self.start_path = Path(start_path).resolve()
        self.selected_file: Optional[str] = None
        self.current_sort_mode = SortMode.NAME
        self.current_sort_order = SortOrder.ASCENDING

    def compose(self) -> ComposeResult:
        """Create child widgets for the app."""
        yield Header()
        yield Label("", id="path-display")
        yield CustomDirectoryTree(str(self.start_path))
        yield Footer()

    def on_mount(self) -> None:
        """Called when the app is mounted."""
        self.title = "Select File Browser"
        self.sub_title = "Navigate with arrows, Enter to select, Q to quit"

        # Set initial focus to directory tree
        tree = self.query_one(CustomDirectoryTree)
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
    def on_node_highlighted(self, event: DirectoryTree.NodeHighlighted) -> None:
        """Update path display when node is highlighted."""
        if event.node and event.node.data:
            self._update_path_display(str(event.node.data))

    def _update_path_display(self, path: str):
        """Update the path display label."""
        path_label = self.query_one("#path-display", Label)
        path_label.update(f"Path: {path}")

    def action_quit(self) -> None:
        """Quit the application without selecting a file."""
        self.exit(None)

    async def action_show_sort_dialog(self) -> None:
        """Show the sort options dialog."""
        dialog = SortDialog(self.current_sort_mode, self.current_sort_order)
        result = await self.push_screen(dialog)

        if result:
            # Update sort settings
            self.current_sort_mode, self.current_sort_order = result

            # Update the tree's sort settings
            tree = self.query_one(CustomDirectoryTree)
            tree.set_sort_mode(self.current_sort_mode)
            tree.set_sort_order(self.current_sort_order)
