#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Test file to verify sequential commit pipeline."""


def hello_sequential() -> bool:
    """Test function for pipeline."""
    print("Sequential execution works!")
    return True


if __name__ == "__main__":
    if hello_sequential():
        print("✓ Test passed")
