#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Visual test for loading indicators - creates a large directory structure."""

import tempfile
import shutil
from pathlib import Path
from selectfilecli import select_file

def create_large_test_structure():
    """Create a large directory structure to test loading indicators."""
    temp_dir = tempfile.mkdtemp(prefix="test_loading_visual_")
    
    print("Creating large test structure...")
    # Create multiple levels with many items
    for i in range(5):  # 5 top-level dirs
        level1 = Path(temp_dir) / f"Department_{i:02d}"
        level1.mkdir()
        
        # Add some files at this level
        for f in range(10):
            (level1 / f"document_{f:03d}.txt").write_text(f"Doc content {f}")
        
        # Create subdirectories
        for j in range(8):  # 8 subdirs per department
            level2 = level1 / f"Team_{j:02d}"
            level2.mkdir()
            
            # Add files
            for f in range(15):
                (level2 / f"file_{f:03d}.dat").write_text(f"Data {f}")
            
            # One more level
            for k in range(4):  # 4 subdirs per team
                level3 = level2 / f"Project_{k:02d}"
                level3.mkdir()
                
                # Add many files to make loading visible
                for f in range(20):
                    (level3 / f"item_{f:04d}.txt").write_text(f"Item {f}")
    
    return temp_dir

def main():
    """Run the visual test."""
    temp_dir = create_large_test_structure()
    
    print(f"\nCreated large test structure at: {temp_dir}")
    print("\n" + "="*60)
    print("LOADING INDICATOR TEST")
    print("="*60)
    print("\nThis test uses a large directory structure to test loading indicators.")
    print("\nWhat to look for:")
    print("1. When you expand a folder, '<...loading...>' should appear briefly")
    print("2. The loading text should be in yellow and blinking")
    print("3. Once loaded, the folder contents replace the loading indicator")
    print("4. When navigating to a new directory, a loading overlay should appear")
    print("\nTips:")
    print("- Try expanding folders with many items")
    print("- Navigate to different directories using arrow keys")
    print("- Press 'P' to go to parent directory")
    print("- Press 'q' or Escape to quit")
    print("\n" + "="*60 + "\n")
    
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
        # Cleanup
        print("\nCleaning up test directory...")
        shutil.rmtree(temp_dir, ignore_errors=True)
        print("Done!")

if __name__ == "__main__":
    main()