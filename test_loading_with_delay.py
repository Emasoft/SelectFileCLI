#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Test loading indicators with artificial delay."""

import os
import sys
import time
import tempfile
import shutil
from pathlib import Path

# Add delay to directory reading to make loading visible
original_listdir = os.listdir
def delayed_listdir(path):
    """Add delay to directory listing to simulate slow file systems."""
    # Add 0.5 second delay for directories
    if os.path.isdir(path):
        time.sleep(0.5)
    return original_listdir(path)

# Monkey patch os.listdir to add delay
os.listdir = delayed_listdir

# Now import and use select_file
from selectfilecli import select_file

def create_test_structure():
    """Create a test directory structure."""
    temp_dir = tempfile.mkdtemp(prefix="test_loading_delay_")
    
    # Create nested structure
    for i in range(2):
        subdir = Path(temp_dir) / f"slow_folder_{i}"
        subdir.mkdir()
        
        # Create some files
        for j in range(3):
            file = subdir / f"file_{j}.txt"
            file.write_text(f"Content {j}")
        
        # Create deeper nesting
        deep_dir = subdir / "deep_slow_folder"
        deep_dir.mkdir()
        (deep_dir / "deep_file.txt").write_text("Deep content")
    
    return temp_dir

def main():
    """Test the loading indicator with delays."""
    print("Creating test directory structure...")
    temp_dir = create_test_structure()
    
    print(f"\nTest directory created at: {temp_dir}")
    print("\n⚠️  Directory listing has been slowed down to make loading indicators visible!")
    print("\nInstructions:")
    print("1. Click on folder arrows ► to expand them")
    print("2. You should see '<...loading...>' appear briefly")
    print("3. After 0.5 seconds, the folder contents will appear")
    print("\nPress 'q' or Escape to quit\n")
    
    try:
        result = select_file(
            start_path=temp_dir,
            select_files=True,
            select_dirs=True
        )
        
        if result:
            print(f"\nSelected: {result}")
        else:
            print("\nNo selection made")
    finally:
        # Restore original listdir
        os.listdir = original_listdir
        
        # Cleanup
        shutil.rmtree(temp_dir, ignore_errors=True)
        print("Test directory cleaned up")

if __name__ == "__main__":
    main()