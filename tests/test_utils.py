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
    """Get the path to the sequential executor if available."""
    # Try to find the sequential executor
    project_root = Path(__file__).parent.parent
    sequential_executor = project_root / "scripts" / "sequential-executor.sh"
    wait_all = project_root / "scripts" / "wait_all.sh"

    if sequential_executor.exists() and wait_all.exists():
        return sequential_executor
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
    sequential_executor = get_sequential_executor()
    wait_all = Path(__file__).parent.parent / "scripts" / "wait_all.sh"

    if use_sequential and sequential_executor and wait_all.exists():
        # Use wait_all.sh with sequential executor
        full_cmd = [str(wait_all), "--timeout", str(timeout), "--", str(sequential_executor)] + cmd
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
