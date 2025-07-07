#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Test utilities for sequential subprocess execution.
Prevents multiple processes from spawning during tests.
"""

import subprocess
import os
from pathlib import Path
from typing import Optional, List, Tuple


def get_sequential_executor() -> Optional[Path]:
    """Get the path to the sequential queue executor if available."""
    # Try to find the sequential queue executor
    project_root = Path(__file__).parent.parent
    sep_queue = project_root / "scripts" / "sep_queue.sh"

    if sep_queue.exists():
        return sep_queue
    return None


def run_command_sequential(cmd: List[str], cwd: Optional[Path] = None, timeout: int = 300, use_sequential: bool = True) -> Tuple[int, str, str]:
    """
    Run a command with optional sequential execution.

    Args:
        cmd: Command and arguments as a list
        cwd: Working directory
        timeout: Timeout in seconds
        use_sequential: Whether to use the sequential executor

    Returns:
        Tuple of (exit_code, stdout, stderr)
    """
    # Check if we should use sequential execution
    sep_queue = get_sequential_executor()

    if use_sequential and sep_queue:
        # Use sep_queue.sh for sequential execution
        full_cmd = [str(sep_queue), "--timeout", str(timeout), "--"] + cmd
    else:
        # Direct execution (fallback)
        full_cmd = cmd

    try:
        result = subprocess.run(full_cmd, cwd=cwd, capture_output=True, text=True, timeout=timeout, check=False)
        return result.returncode, result.stdout, result.stderr
    except subprocess.TimeoutExpired:
        return -1, "", f"Command timed out after {timeout} seconds"


# For backward compatibility, create an alias
run_command = run_command_sequential
