#!/usr/bin/env bash
# safe-run.sh - Wrapper that delegates to sequential-executor.sh
# Usage: ./scripts/safe-run.sh <command> [args...]

set -euo pipefail

# Get script directory with robust path resolution
if command -v realpath >/dev/null 2>&1; then
    SCRIPT_DIR="$(realpath "$(dirname "${BASH_SOURCE[0]}")")"
elif command -v readlink >/dev/null 2>&1 && readlink -f "${BASH_SOURCE[0]}" >/dev/null 2>&1; then
    SCRIPT_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
else
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi
SEQUENTIAL_EXECUTOR="${SCRIPT_DIR}/sequential-executor.sh"
WAIT_ALL="${SCRIPT_DIR}/wait_all.sh"

# Check if sequential executor exists
if [ ! -x "$SEQUENTIAL_EXECUTOR" ]; then
    echo "ERROR: sequential-executor.sh not found or not executable" >&2
    echo "Path: $SEQUENTIAL_EXECUTOR" >&2
    exit 1
fi

# Check if wait_all.sh exists
if [ ! -x "$WAIT_ALL" ]; then
    echo "ERROR: wait_all.sh not found or not executable" >&2
    echo "Path: $WAIT_ALL" >&2
    exit 1
fi

# Delegate to sequential executor using wait_all.sh
"$WAIT_ALL" -- "$SEQUENTIAL_EXECUTOR" "$@"
