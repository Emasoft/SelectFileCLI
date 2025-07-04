#!/usr/bin/env python3
# -*- coding: utf-8 -*-
#
# Copyright (c) 2024-2025 Emasoft
# Licensed under the MIT License.
# See the LICENSE file in the project root for full license text.
#

# HERE IS THE CHANGELOG FOR THIS VERSION OF THE FILE:
# - Added proper shebang and encoding declaration
# - Fixed path handling to use absolute paths, preventing issues with relative paths in recursion
#

import os
from typing import Dict, List, Optional, Union, Any


class FileList:
    """A class to represent and search through file system directories."""

    def __init__(self, path: str) -> None:
        """Initialize FileList with a directory path.

        Args:
            path: The directory path to start from
        """
        # Always use absolute path to avoid relative path issues in recursion
        self.path = os.path.abspath(path)
        self.tree: Dict[str, List[os.DirEntry[Any]]] = dict()

    def get_entry_list(self) -> List[os.DirEntry[Any]]:
        """Get list of DirEntry objects for the current path.

        Returns:
            List of os.DirEntry objects in the directory
        """
        entryList = []
        with os.scandir(self.path) as entries:
            for entry in entries:
                entryList.append(entry)
        return entryList

    def get_entry_type(self, entry: os.DirEntry[Any]) -> str:
        """Get the type of a directory entry as a string.

        Args:
            entry: The directory entry to check

        Returns:
            'File ' or 'Dir ' depending on entry type
        """
        if entry.is_file():
            return "File "
        else:
            return "Dir "

    def get_dir_list(self) -> List[os.DirEntry[Any]]:
        """Get list of subdirectories in the current path.

        Returns:
            List of os.DirEntry objects that are directories
        """
        entry_list = self.get_entry_list()
        return [entry for entry in entry_list if entry.is_dir()]

    def search_dir(self, current_depth_relative: int = 0, max_depth: int = 2) -> None:
        """recursively searches files downwards to a max depth"""
        if current_depth_relative <= max_depth:
            dir_list = self.get_dir_list()
            self.tree[self.path] = [entry for entry in self.get_entry_list()]

            # creating new FileList class based on new path
            for dir_entry in dir_list:
                # Fix: Use self.path instead of os.getcwd()
                newpath = os.path.join(self.path, dir_entry.name)
                sub_dir = FileList(newpath)
                sub_dir.search_dir(current_depth_relative + 1, max_depth)
                self.tree.update(sub_dir.tree)


if __name__ == "__main__":
    # Example usage
    test_path = os.path.join(os.getcwd(), "tests")
    if os.path.exists(test_path):
        test = FileList(test_path)
        test.search_dir(max_depth=1)
        print(f"Found {len(test.tree)} directories")
        for path, entries in test.tree.items():
            print(f"{path}: {len(entries)} entries")
