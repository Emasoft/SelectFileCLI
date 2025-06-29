#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
Example script demonstrating how to use selectfilecli library.
"""

from selectfilecli import select_file


def main():
    """Run the example."""
    print("Welcome to selectfilecli example!")
    print("Navigate with arrow keys, Enter to select a file, 'q' to quit")
    print("-" * 50)

    # Example 1: Start from current directory
    selected = select_file()

    if selected:
        print(f"\nYou selected: {selected}")
    else:
        print("\nNo file selected (cancelled)")

    # Example 2: Start from a specific directory (uncomment to test)
    # import os
    # home_dir = os.path.expanduser("~")
    # selected = select_file(home_dir)
    # if selected:
    #     print(f"\nYou selected: {selected}")


if __name__ == "__main__":
    main()
