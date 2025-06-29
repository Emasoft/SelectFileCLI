#!/usr/bin/env python3
# -*- coding: utf-8 -*-

# HERE IS THE CHANGELOG FOR THIS VERSION OF THE FILE:
# - Created new Textual-based file browser application
# - Implements FileBrowserApp with directory navigation
# - Returns selected file path via app.return_value
#

"""Textual-based file browser application."""

import os
from pathlib import Path
from typing import Optional, List

from textual import on
from textual.app import App, ComposeResult
from textual.widgets import DirectoryTree, Header, Footer
from textual.widgets.tree import TreeNode
from textual.binding import Binding


class FileBrowserApp(App[Optional[str]]):
    """A Textual app for browsing and selecting files.

    The app returns the selected file path via app.return_value.
    """

    CSS = """
    DirectoryTree {
        background: $surface;
        color: $text;
        padding: 1;
        border: solid $primary;
        height: 100%;
    }
    """

    BINDINGS = [
        Binding("q", "quit", "Quit", priority=True),
        Binding("escape", "quit", "Quit"),
    ]

    def __init__(self, start_path: str = "."):
        """Initialize the file browser.

        Args:
            start_path: The directory to start browsing from.
        """
        super().__init__()
        self.start_path = Path(start_path).resolve()
        self.selected_file: Optional[str] = None

    def compose(self) -> ComposeResult:
        """Create child widgets for the app."""
        yield Header()
        yield DirectoryTree(str(self.start_path))
        yield Footer()

    def on_mount(self) -> None:
        """Called when the app is mounted."""
        self.title = "Select File Browser"
        self.sub_title = "Navigate with arrows, Enter to select, Q to quit"

    @on(DirectoryTree.FileSelected)
    def on_file_selected(self, event: DirectoryTree.FileSelected) -> None:
        """Handle file selection.

        Args:
            event: The file selection event containing the selected path.
        """
        self.selected_file = str(event.path)
        self.exit(self.selected_file)

    def action_quit(self) -> None:
        """Quit the application without selecting a file."""
        self.exit(None)
