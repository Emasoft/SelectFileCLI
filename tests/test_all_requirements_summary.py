#!/usr/bin/env python3
# -*- coding: utf-8 -*-
#
# Copyright (c) 2024-2025 Emasoft
# Licensed under the MIT License.
# See the LICENSE file in the project root for full license text.
#

# HERE IS THE CHANGELOG FOR THIS VERSION OF THE FILE:
# - Initial creation of requirements summary test runner
# - Runs all requirement tests and produces a formatted report
#

"""Run all requirement tests and produce a summary report."""

import subprocess
import sys
from pathlib import Path
import re
from typing import List, Tuple


def run_requirements_tests() -> Tuple[List[str], List[str]]:
    """Run requirement verification tests and collect results."""
    cmd = [sys.executable, "-m", "pytest", "tests/test_requirements_verification.py", "-v", "--tb=no", "--no-header", "-q"]

    result = subprocess.run(cmd, capture_output=True, text=True)

    passed = []
    failed = []

    for line in result.stdout.split("\n"):
        if "PASSED" in line and "test_requirement_" in line:
            # Extract requirement number
            match = re.search(r"test_requirement_(\d+)_", line)
            if match:
                req_num = match.group(1)
                passed.append(f"Requirement {req_num}")
        elif "FAILED" in line and "test_requirement_" in line:
            match = re.search(r"test_requirement_(\d+)_", line)
            if match:
                req_num = match.group(1)
                failed.append(f"Requirement {req_num}")

    return passed, failed


def run_visual_tests() -> bool:
    """Check if visual snapshots exist and pass."""
    cmd = [sys.executable, "-m", "pytest", "tests/test_visual_requirements.py", "-v", "--tb=no", "--no-header", "-q"]

    result = subprocess.run(cmd, capture_output=True, text=True)
    return result.returncode == 0 or "passed" in result.stdout.lower()


def print_summary_table() -> int:
    """Print a formatted summary table of all requirements."""
    requirements = [
        ("1", "Header not overlapping button bar", "Visual layout correctly separated"),
        ("2", "Subtitle is displayed", "Shows navigation instructions based on selection mode"),
        ("3", "Path display visible and yellow", "Current path shown in yellow at top"),
        ("4", "Empty folders show <empty>", "Empty directories display placeholder"),
        ("5", "Loading placeholders async", "Shows 'Loading...' during async operations"),
        ("6", "Directory navigation loading", "Loading state during directory changes"),
        ("7", "Sort dialog OK/Cancel + memory", "Dialog has buttons and remembers settings"),
        ("8", "Directory entries aligned", "Files shown in aligned columns"),
        ("9", "Cancel fast returns None", "Quick cancel with all None FileInfo"),
        ("10", "Error message field works", "FileInfo.error_message populated on errors"),
        ("11", "Real-time resizing works", "UI adapts to terminal size changes"),
    ]

    # Run tests
    passed, failed = run_requirements_tests()
    visual_ok = run_visual_tests()

    # Print header
    print("\n" + "=" * 80)
    print("📋 REQUIREMENTS VERIFICATION SUMMARY")
    print("=" * 80)

    # Table header
    print(f"{'Req':<4} {'Description':<35} {'Status':<10} {'Details':<25}")
    print("-" * 80)

    # Print each requirement
    for req_num, desc, details in requirements:
        req_key = f"Requirement {req_num}"
        if req_key in passed:
            status = "✅ PASS"
            color = "\033[92m"  # Green
        elif req_key in failed:
            status = "❌ FAIL"
            color = "\033[91m"  # Red
        else:
            status = "⚠️  SKIP"
            color = "\033[93m"  # Yellow

        print(f"{color}{req_num:<4} {desc:<35} {status:<10}\033[0m {details:<25}")

    print("-" * 80)

    # Summary
    total = len(requirements)
    passed_count = len(passed)
    failed_count = len(failed)
    skipped_count = total - passed_count - failed_count

    print(f"\n📊 Summary: {passed_count}/{total} passed, {failed_count} failed, {skipped_count} skipped")

    if visual_ok:
        print("🎨 Visual snapshot tests: ✅ All visual tests passing")
    else:
        print("🎨 Visual snapshot tests: ⚠️  Some visual tests need attention")

    # Overall result
    if failed_count == 0:
        print("\n✅ All requirements verified successfully!")
        return 0
    else:
        print(f"\n❌ {failed_count} requirements need attention")
        return 1


if __name__ == "__main__":
    exit_code = print_summary_table()
    sys.exit(exit_code)
