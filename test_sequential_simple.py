#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Simple test to verify sequential execution pipeline."""


def test_simple() -> None:
    """Basic test to verify the pipeline works."""
    assert True


def test_import() -> None:
    """Test that our module can be imported."""
    import selectfilecli

    assert selectfilecli is not None


if __name__ == "__main__":
    test_simple()
    test_import()
    print("All tests passed!")
