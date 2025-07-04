#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Test script to verify resize functionality of the file browser."""

import sys
from pathlib import Path

# Add src to path
sys.path.insert(0, str(Path(__file__).parent / "src"))

from selectfilecli.file_browser_app import FileBrowserApp

if __name__ == "__main__":
    app = FileBrowserApp(start_path=".", select_files=True, select_dirs=True)
    print("Starting app... Try resizing the terminal window to test the fix.")
    print("The columns should automatically adjust when you resize.")
    result = app.run()

    if result:
        print(f"\nSelected: {result}")
    else:
        print("\nCancelled")
