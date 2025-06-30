#!/usr/bin/env python3
# -*- coding: utf-8 -*-
#
# Copyright (c) 2024-2025 Emasoft
# Licensed under the MIT License.
# See the LICENSE file in the project root for full license text.
#

# HERE IS THE CHANGELOG FOR THIS VERSION OF THE FILE:
# - Created Dockerfile for testing with uv
# - Multi-stage build for optimal size
# - Supports both testing and runtime environments
# - Includes caching for uv dependencies
#

# syntax=docker/dockerfile:1
FROM python:3.12-slim AS builder

# Install uv
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /bin/

# Set working directory
WORKDIR /app

# Copy dependency files
COPY pyproject.toml uv.lock ./

# Install dependencies in a virtual environment
RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --frozen --no-install-project --all-extras --compile-bytecode

# Copy the project
COPY . .

# Install the project
RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --frozen --all-extras --compile-bytecode

# Final stage for testing
FROM python:3.12-slim AS test

# Install system dependencies needed for testing
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    && rm -rf /var/lib/apt/lists/*

# Copy uv from builder
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /bin/

# Set working directory
WORKDIR /app

# Copy the entire project and virtual environment from builder
COPY --from=builder /app /app

# Set environment variables
ENV PATH="/app/.venv/bin:$PATH"
ENV PYTHONPATH="/app/src:$PYTHONPATH"
ENV UV_SYSTEM_PYTHON=1

# Default command runs tests
CMD ["uv", "run", "pytest", "--cov=src/selectfilecli", "--cov-report=term-missing", "--cov-fail-under=80"]

# Production stage
FROM python:3.12-slim AS production

# Copy only the virtual environment and project files
COPY --from=builder /app/.venv /app/.venv
COPY --from=builder /app/src /app/src

# Set working directory
WORKDIR /app

# Set environment variables
ENV PATH="/app/.venv/bin:$PATH"
ENV PYTHONPATH="/app/src:$PYTHONPATH"

# The application can be run as a module
CMD ["python", "-m", "selectfilecli"]