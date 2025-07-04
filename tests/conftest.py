#!/usr/bin/env python3
# -*- coding: utf-8 -*-
#
# Copyright (c) 2024-2025 Emasoft
# Licensed under the MIT License.
# See the LICENSE file in the project root for full license text.
#

# HERE IS THE CHANGELOG FOR THIS VERSION OF THE FILE:
# - Added copyright header
# - Added environment detection for Docker/CI
# - Configured retry counts based on environment
# - Added fixtures for common test operations
# - Added type annotations to all functions and fixtures
#

"""Pytest configuration for selectfilecli tests.
Prevents multiple processes from spawning during tests.
"""

import os
import sys
from pathlib import Path
from typing import Dict, Any

import pytest

# Add src to path for imports
sys.path.insert(0, str(Path(__file__).parent.parent / "src"))

# The snap_compare fixture is provided by pytest-textual-snapshot plugin
# No additional configuration needed for basic SVG snapshot testing


def pytest_configure(config):
    """Configure pytest to run sequentially and with resource limits."""
    # Force sequential execution
    os.environ["PYTEST_MAX_WORKERS"] = "1"
    os.environ["PYTEST_DISABLE_XDIST"] = "1"

    # Set resource limits
    os.environ["PYTHONDONTWRITEBYTECODE"] = "1"
    os.environ["PYTHONUNBUFFERED"] = "1"

    # Disable any parallel execution plugins
    if hasattr(config.option, "numprocesses"):
        config.option.numprocesses = 1
    if hasattr(config.option, "dist"):
        config.option.dist = "no"


def pytest_cmdline_preparse(config, args):
    """Preprocess command line arguments to enforce sequential execution."""
    # Remove any parallel execution flags
    filtered_args = []
    skip_next = False

    for arg in args:
        if skip_next:
            skip_next = False
            continue

        if arg in ["-n", "--numprocesses", "--dist"]:
            skip_next = True
            continue
        elif arg.startswith("-n=") or arg.startswith("--numprocesses="):
            continue
        elif arg == "--dist=loadscope" or arg == "--dist=each":
            continue
        else:
            filtered_args.append(arg)

    args[:] = filtered_args


@pytest.fixture(autouse=True)
def enforce_sequential_execution():
    """Fixture that runs for every test to enforce sequential execution."""
    # Set environment variables for each test
    os.environ["PYTEST_CURRENT_TEST"] = "1"
    os.environ["PROJECT_SEQUENTIAL_MODE"] = "1"

    yield

    # Cleanup after test
    os.environ.pop("PYTEST_CURRENT_TEST", None)


def is_running_in_docker() -> bool:
    """Check if running inside a Docker container."""
    return os.path.exists("/.dockerenv") or os.environ.get("DOCKER_CONTAINER") == "true" or (os.path.exists("/proc/1/cgroup") and "docker" in Path("/proc/1/cgroup").read_text())


def is_running_in_ci() -> bool:
    """Check if running in CI environment."""
    return os.environ.get("CI") == "true" or os.environ.get("GITHUB_ACTIONS") == "true"


def get_max_retries() -> int:
    """Get maximum retries based on environment."""
    if is_running_in_ci() or is_running_in_docker():
        return int(os.environ.get("DEFAULT_MAX_RETRIES_TEST", "2"))
    return 10


def get_timeout() -> int:
    """Get timeout based on environment."""
    if is_running_in_ci() or is_running_in_docker():
        return int(os.environ.get("PYTEST_TIMEOUT", "60"))
    return 300


@pytest.fixture
def test_env() -> Dict[str, Any]:
    """Provide test environment information."""
    return {
        "is_docker": is_running_in_docker(),
        "is_ci": is_running_in_ci(),
        "max_retries": get_max_retries(),
        "timeout": get_timeout(),
    }


@pytest.fixture
def temp_dir(tmp_path: Path) -> Path:
    """Create a temporary directory with test files."""
    # Create test structure
    (tmp_path / "file1.txt").write_text("Test file 1")
    (tmp_path / "file2.py").write_text("print('test')")
    subdir = tmp_path / "subdir"
    subdir.mkdir()
    (subdir / "file3.md").write_text("# Test")
    return tmp_path
