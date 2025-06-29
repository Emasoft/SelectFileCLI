#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""Pytest configuration for selectfilecli tests."""

import pytest
from syrupy.extensions.single_file import SingleFileSnapshotExtension
from syrupy import SnapshotAssertion


@pytest.fixture
def snapshot(snapshot: SnapshotAssertion) -> SnapshotAssertion:
    """Configure snapshot testing for Textual apps."""
    return snapshot.use_extension(SingleFileSnapshotExtension)
