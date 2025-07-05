#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Test script to verify loading indicators work properly."""

import asyncio
import tempfile
import os
from pathlib import Path
from selectfilecli import select_file

async def create_test_structure():
    """Create a test directory structure with some delay."""
    temp_dir = tempfile.mkdtemp(prefix="test_loading_")
    
    # Create nested structure
    for i in range(3):
        subdir = Path(temp_dir) / f"folder_{i}"
        subdir.mkdir()
        
        # Create some files
        for j in range(5):
            file = subdir / f"file_{j}.txt"
            file.write_text(f"Content of file {j} in folder {i}")
        
        # Create deeper nesting
        deep_dir = subdir / "deep_folder"
        deep_dir.mkdir()
        for k in range(3):
            deep_file = deep_dir / f"deep_file_{k}.txt"
            deep_file.write_text(f"Deep content {k}")
    
    return temp_dir

def main():
    """Test the loading indicator."""
    print("Creating test directory structure...")
    temp_dir = asyncio.run(create_test_structure())
    
    print(f"\nTest directory created at: {temp_dir}")
    print("Starting file browser...")
    print("\nInstructions:")
    print("1. Expand folders to see if <...loading...> appears")
    print("2. Navigate to different directories")
    print("3. Check if loading indicators show during navigation")
    print("\nPress 'q' or Escape to quit the browser\n")
    
    try:
        result = select_file(
            initial_path=temp_dir,
            select_files=True,
            select_dirs=True,
            show_hidden=True
        )
        
        if result:
            print(f"\nSelected: {result}")
        else:
            print("\nNo selection made")
    finally:
        # Cleanup
        import shutil
        shutil.rmtree(temp_dir, ignore_errors=True)
        print("Test directory cleaned up")

if __name__ == "__main__":
    main()