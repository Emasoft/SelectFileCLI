#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
sep_detect_snapshot_tests.py - Detect which tests use snapshot testing
Version: 8.6.0

This script is part of the Sequential Execution Pipeline (SEP) toolkit.
It analyzes test files to detect which tests use snapshot testing
(via snap_compare or other snapshot methods) to optimize test execution.

CHANGELOG:
v8.6.0:
- Version bump for consistency across all SEP scripts
- Added SEP prefix to filename in docstring
- Added changelog
- Part of SEP toolkit for intelligent pytest atomization
"""

import ast
import sys
import json
from pathlib import Path
from typing import List, Dict, Set, Union


class SnapshotTestDetector(ast.NodeVisitor):
    """AST visitor to detect snapshot test usage in test functions."""

    def __init__(self) -> None:
        self.snapshot_tests: Set[str] = set()
        self.current_class: Union[str, None] = None
        self.current_function: Union[str, None] = None
        self.snapshot_indicators = {
            "snap_compare",
            "snapshot",
            "assert_matches_snapshot",
            "toMatchSnapshot",
            "snap_",
        }

    def visit_ClassDef(self, node: ast.ClassDef) -> None:
        """Visit class definitions to track test classes."""
        if node.name.startswith("Test"):
            old_class = self.current_class
            self.current_class = node.name
            self.generic_visit(node)
            self.current_class = old_class
        else:
            self.generic_visit(node)

    def visit_FunctionDef(self, node: ast.FunctionDef) -> None:
        """Visit function definitions to track test functions."""
        if node.name.startswith("test_"):
            old_function = self.current_function
            self.current_function = node.name

            # Check if this function uses snapshot testing
            if self._uses_snapshot(node):
                if self.current_class:
                    test_name = f"{self.current_class}::{node.name}"
                else:
                    test_name = node.name
                self.snapshot_tests.add(test_name)

            self.generic_visit(node)
            self.current_function = old_function
        else:
            self.generic_visit(node)

    def visit_AsyncFunctionDef(self, node: ast.AsyncFunctionDef) -> None:
        """Visit async function definitions (same logic as regular functions)."""
        # Type-ignore because we're intentionally reusing logic
        self.visit_FunctionDef(node)  # type: ignore[arg-type]

    def _uses_snapshot(self, node: Union[ast.FunctionDef, ast.AsyncFunctionDef]) -> bool:
        """Check if a function uses snapshot testing."""
        for child in ast.walk(node):
            # Check for function calls
            if isinstance(child, ast.Call):
                # Check function name
                if isinstance(child.func, ast.Name):
                    if any(indicator in child.func.id for indicator in self.snapshot_indicators):
                        return True
                # Check for method calls
                elif isinstance(child.func, ast.Attribute):
                    if any(indicator in child.func.attr for indicator in self.snapshot_indicators):
                        return True

            # Check for names (e.g., in function parameters)
            elif isinstance(child, ast.Name):
                if any(indicator in child.id for indicator in self.snapshot_indicators):
                    return True

            # Check for strings (sometimes snapshot paths are in strings)
            elif isinstance(child, ast.Constant) and isinstance(child.value, str):
                if "snapshot" in child.value.lower():
                    return True

        # Also check function parameters for snapshot fixtures
        for arg in node.args.args:
            if any(indicator in arg.arg for indicator in self.snapshot_indicators):
                return True

        return False


def detect_snapshot_tests(test_file: str) -> Dict[str, Union[List[str], str]]:
    """
    Detect which tests in a file use snapshot testing.

    Args:
        test_file: Path to the test file

    Returns:
        Dictionary with 'snapshot_tests' and 'all_tests' lists
    """
    result: Dict[str, Union[List[str], str]] = {"snapshot_tests": [], "all_tests": [], "file": test_file}

    try:
        # Check if file exists and is readable
        if not Path(test_file).exists():
            result["error"] = f"File not found: {test_file}"
            return result

        with open(test_file, "r") as f:
            content = f.read()

        # Return empty if file is empty
        if not content.strip():
            return result

        tree = ast.parse(content, filename=test_file)
        detector = SnapshotTestDetector()
        detector.visit(tree)

        # Also collect all tests for comparison
        all_tests = []
        for node in ast.walk(tree):
            if isinstance(node, ast.ClassDef) and node.name.startswith("Test"):
                for item in node.body:
                    if isinstance(item, (ast.FunctionDef, ast.AsyncFunctionDef)) and item.name.startswith("test_"):
                        all_tests.append(f"{node.name}::{item.name}")
            elif isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)) and node.name.startswith("test_"):
                # Top-level test function
                if node.col_offset == 0:  # Top-level function
                    all_tests.append(node.name)

        result["snapshot_tests"] = sorted(list(detector.snapshot_tests))
        result["all_tests"] = sorted(all_tests)

    except SyntaxError as e:
        result["error"] = f"Syntax error in test file: {e}"
    except Exception as e:
        result["error"] = f"Error analyzing file: {e}"

    return result


def main() -> None:
    """Main function for CLI usage."""
    if len(sys.argv) < 2:
        # Output empty result for missing arguments
        print(json.dumps({"snapshot_tests": [], "all_tests": [], "file": "", "error": "Usage: detect_snapshot_tests.py <test_file.py>"}))
        sys.exit(1)

    test_file = sys.argv[1]
    results = detect_snapshot_tests(test_file)

    # Always output valid JSON
    print(json.dumps(results, indent=2))


if __name__ == "__main__":
    main()
