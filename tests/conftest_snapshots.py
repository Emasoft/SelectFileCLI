#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Configuration for snapshot tests to ensure loading indicators are captured."""

import pytest
from pathlib import Path


# The snap_compare fixture is provided by pytest-textual-snapshot plugin
# We don't need to redefine it here


def pytest_configure(config):
    """Configure pytest for snapshot testing."""
    # Add markers for snapshot tests
    config.addinivalue_line(
        "markers", 
        "snapshot: mark test as a visual snapshot test"
    )
    config.addinivalue_line(
        "markers",
        "loading: mark test as testing loading indicators"
    )


# Helper functions for snapshot tests

def ensure_snapshots_dir():
    """Ensure the snapshots directory exists."""
    snapshots_dir = Path(__file__).parent / "__snapshots__"
    snapshots_dir.mkdir(exist_ok=True)
    return snapshots_dir


def clean_old_snapshots(keep_days=30):
    """Clean old snapshot files."""
    import time
    snapshots_dir = ensure_snapshots_dir()
    current_time = time.time()
    
    for snapshot_file in snapshots_dir.glob("*.svg"):
        file_age_days = (current_time - snapshot_file.stat().st_mtime) / 86400
        if file_age_days > keep_days:
            snapshot_file.unlink()


# Test utilities for loading indicator verification

class LoadingIndicatorTester:
    """Utility class for testing loading indicators."""
    
    @staticmethod
    def verify_loading_text_in_snapshot(snapshot_path: Path) -> bool:
        """Verify that loading text appears in the snapshot.
        
        Args:
            snapshot_path: Path to the SVG snapshot file
            
        Returns:
            True if loading indicator text is found
        """
        if not snapshot_path.exists():
            return False
        
        content = snapshot_path.read_text()
        
        # Check for loading indicator text patterns
        loading_patterns = [
            "&lt;...loading...&gt;",  # HTML-escaped in SVG
            "loading",
            "Loading",
            "bright_yellow",  # Style used for loading text
            "blink"  # Blink effect
        ]
        
        return any(pattern in content for pattern in loading_patterns)
    
    @staticmethod
    def verify_loading_spinner_in_snapshot(snapshot_path: Path) -> bool:
        """Verify that loading spinner/overlay appears in the snapshot.
        
        Args:
            snapshot_path: Path to the SVG snapshot file
            
        Returns:
            True if loading spinner is found
        """
        if not snapshot_path.exists():
            return False
        
        content = snapshot_path.read_text()
        
        # Check for spinner patterns (Textual's LoadingIndicator)
        spinner_patterns = [
            "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏",  # Spinner characters
            "LoadingIndicator",
            "loading-indicator"
        ]
        
        return any(pattern in content for pattern in spinner_patterns)