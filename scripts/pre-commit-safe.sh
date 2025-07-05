#!/usr/bin/env bash
# pre-commit-safe.sh - Wrapper for pre-commit hooks to ensure sequential execution
#
# This script solves the deadlock issue by:
# 1. Detecting if we're already inside a pre-commit execution
# 2. Running commands directly if inside pre-commit (no double-locking)
# 3. Using sequential executor only for the initial pre-commit call
#
set -euo pipefail

# Check if we're already inside a pre-commit execution
if [ -n "${PRE_COMMIT_RUNNING:-}" ]; then
    # We're inside pre-commit, execute directly to avoid deadlock
    exec "$@"
fi

# Check if we're being called by pre-commit directly
if [[ "${BASH_SOURCE[1]:-}" == *"pre-commit"* ]] || [[ "${0}" == *"pre-commit"* ]]; then
    # Set flag for child processes
    export PRE_COMMIT_RUNNING=1
    # Execute directly - pre-commit handles its own serialization
    exec "$@"
fi

# Otherwise, use sequential executor for serialization
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "${SCRIPT_DIR}/sequential-executor.sh" "$@"
