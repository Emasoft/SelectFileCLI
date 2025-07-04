#!/usr/bin/env python3
# -*- coding: utf-8 -*-
#
# Copyright (c) 2024-2025 Emasoft
# Licensed under the MIT License.
# See the LICENSE file in the project root for full license text.
#

# HERE IS THE CHANGELOG FOR THIS VERSION OF THE FILE:
# - Created FileInfo dataclass to represent comprehensive file/folder information
# - Added all fields requested by the user for the tuple return type
# - Made all fields optional to handle cases where info is not available
# - Added error_message field to handle file access errors (issue #10)
# - Fixed type annotations for __iter__ and as_tuple methods
#

"""File information data structure for selectfilecli."""

from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Optional, Iterator, Tuple, Union


@dataclass
class FileInfo:
    """Comprehensive file/folder information returned by the file browser.

    All fields are optional and will be None if the information is not available
    or not applicable (e.g., file_path for a directory selection).

    When error_message is not None, it indicates an error occurred while accessing
    the file/folder, and other fields should be ignored.
    """

    file_path: Optional[Path] = None
    """Path to the selected file (None if a directory was selected)."""

    folder_path: Optional[Path] = None
    """Path to the selected folder (None if a file was selected)."""

    last_modified_datetime: Optional[datetime] = None
    """Last modification timestamp of the file/folder."""

    creation_datetime: Optional[datetime] = None
    """Creation timestamp of the file/folder (may not be available on all systems)."""

    size_in_bytes: Optional[int] = None
    """Size in bytes (for files: actual size; for directories: calculated total size)."""

    readonly: Optional[bool] = None
    """True if the file/folder is read-only, False if writable."""

    folder_has_venv: Optional[bool] = None
    """True if the item is a folder containing a Python virtual environment."""

    is_symlink: Optional[bool] = None
    """True if the item is a symbolic link."""

    symlink_broken: Optional[bool] = None
    """True if the item is a broken symbolic link (target doesn't exist)."""

    error_message: Optional[str] = None
    """Error message if file/folder access failed (when not None, other fields should be ignored)."""

    def __iter__(self) -> Iterator[Optional[Union[Path, datetime, int, bool, str]]]:
        """Allow unpacking as tuple for backward compatibility.

        Returns values in the order specified by the user:
        (file_path, folder_path, last_modified_datetime, creation_datetime,
         size_in_bytes, readonly, folder_has_venv, is_symlink, symlink_broken, error_message)
        """
        return iter((self.file_path, self.folder_path, self.last_modified_datetime, self.creation_datetime, self.size_in_bytes, self.readonly, self.folder_has_venv, self.is_symlink, self.symlink_broken, self.error_message))

    def as_tuple(self) -> Tuple[Optional[Union[Path, datetime, int, bool, str]], ...]:
        """Convert to tuple representation."""
        return tuple(self)

    @property
    def path(self) -> Optional[Path]:
        """Get the selected path (either file or folder)."""
        return self.file_path or self.folder_path

    @property
    def path_str(self) -> Optional[str]:
        """Get the selected path as string (for backward compatibility)."""
        p = self.path
        return str(p) if p else None
