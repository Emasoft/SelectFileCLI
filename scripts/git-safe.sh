#!/usr/bin/env bash
# git-safe.sh - Safe git wrapper that prevents concurrent git operations
# Version: 3.0.0
#
# This wrapper ensures only ONE git operation runs at a time
# Enhanced to handle pre-commit hooks and prevent deadlocks

set -euo pipefail

VERSION='3.0.0'

# Display help message
show_help() {
    cat << 'EOF'
git-safe.sh v3.0.0 - Safe sequential git wrapper

USAGE:
    git-safe.sh [GIT_COMMAND] [GIT_ARGS...]
    git-safe.sh --help

DESCRIPTION:
    Ensures only ONE git operation runs at a time to prevent conflicts.
    Automatically detects and handles pre-commit hooks to avoid deadlocks.

EXAMPLES:
    # Safe commit
    git-safe.sh commit -m "Update feature"

    # Safe merge
    git-safe.sh merge feature-branch

    # Safe rebase
    git-safe.sh rebase -i main

    # Any git command
    git-safe.sh push origin main
    git-safe.sh pull --rebase
    git-safe.sh cherry-pick abc123

FEATURES:
    - Prevents concurrent git operations
    - Handles pre-commit hook deadlocks
    - Detects stale locks and cleans them up
    - Checks for existing git lock files
    - Works with sequential-executor.sh

LOCK MECHANISM:
    - Lock directory: /tmp/git-safe-PROJECT_HASH/
    - Tracks current operation with PID
    - Maximum wait time: 30 seconds
    - Automatic stale lock cleanup

SPECIAL HANDLING:
    - Commits set GIT_COMMIT_IN_PROGRESS flag
    - Pre-commit hooks see SEQUENTIAL_EXECUTOR_PID
    - Direct execution if already in git hook

INTEGRATION:
    Uses wait_all.sh for atomic execution when available.

EOF
    exit 0
}

# Check for help flag
if [[ $# -eq 0 ]] || [[ "$1" == "--help" ]] || [[ "$1" == "-h" ]]; then
    show_help
fi

# Skip if already in a git hook to prevent deadlocks
if [ -n "${GIT_DIR:-}" ] || [ -n "${GIT_WORK_TREE:-}" ]; then
    # We're inside a git hook - execute directly
    exec git "$@"
fi

# For commits, set flag so pre-commit hooks know they're part of this operation
if [[ $# -gt 0 ]] && [[ "$1" == "commit" ]]; then
    export GIT_COMMIT_IN_PROGRESS=1
    export SEQUENTIAL_EXECUTOR_PID=$$  # Prevent nested sequential execution
fi

# Get project info
PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
PROJECT_HASH=$(echo "$PROJECT_ROOT" | shasum | cut -d' ' -f1 | head -c 8)

# Git operation lock (separate from sequential executor lock)
GIT_LOCK_DIR="/tmp/git-safe-${PROJECT_HASH}"
GIT_LOCKFILE="${GIT_LOCK_DIR}/git.lock"
GIT_OPERATION_FILE="${GIT_LOCK_DIR}/current_operation.txt"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Ensure lock directory exists
mkdir -p "$GIT_LOCK_DIR"

# Function to check for existing git operations
check_existing_git_operations() {
    # Check for any running git processes
    local git_procs
    git_procs=$(pgrep -f "git (commit|merge|rebase|cherry-pick|push|pull)" 2>/dev/null || true)

    if [ -n "$git_procs" ]; then
        echo -e "${RED}ERROR: Git operations already in progress:${NC}" >&2
        for pid in $git_procs; do
            local cmd
            cmd=$(ps -p "$pid" -o args= 2>/dev/null || echo "unknown")
            echo -e "  ${YELLOW}PID $pid:${NC} $cmd" >&2
        done
        return 1
    fi

    # Check for git lock files
    if [ -f "$PROJECT_ROOT/.git/index.lock" ]; then
        echo -e "${RED}ERROR: Git index lock exists - another git process may be running${NC}" >&2
        echo -e "${YELLOW}To force remove: rm -f $PROJECT_ROOT/.git/index.lock${NC}" >&2
        return 1
    fi

    # Check for our own lock
    if [ -d "$GIT_LOCKFILE" ]; then
        if [ -f "$GIT_OPERATION_FILE" ]; then
            local current_op
            current_op=$(cat "$GIT_OPERATION_FILE" 2>/dev/null || echo "unknown")
            local pid
            pid=$(echo "$current_op" | cut -d: -f1)

            # Check if the process is still alive
            if kill -0 "$pid" 2>/dev/null; then
                echo -e "${RED}ERROR: Git operation already in progress:${NC}" >&2
                echo -e "  $current_op" >&2
                return 1
            else
                # Stale lock, clean it up
                echo -e "${YELLOW}Cleaning up stale git lock...${NC}" >&2
                rm -rf "$GIT_LOCKFILE" "$GIT_OPERATION_FILE"
            fi
        fi
    fi

    return 0
}

# Function to acquire git lock
acquire_git_lock() {
    local max_wait=30  # Maximum 30 seconds wait
    local waited=0

    while ! mkdir "$GIT_LOCKFILE" 2>/dev/null; do
        if [ "$waited" -ge "$max_wait" ]; then
            echo -e "${RED}ERROR: Could not acquire git lock after ${max_wait}s${NC}" >&2
            return 1
        fi

        if [ "$waited" -eq 0 ]; then
            echo -e "${YELLOW}Waiting for git lock...${NC}" >&2
        fi

        sleep 1
        waited=$((waited + 1))
    done

    # Record current operation
    echo "$$:$(date '+%Y-%m-%d %H:%M:%S'):git $*" > "$GIT_OPERATION_FILE"
    return 0
}

# Function to release git lock
release_git_lock() {
    rm -rf "$GIT_LOCKFILE" "$GIT_OPERATION_FILE" 2>/dev/null || true
}

# Cleanup function
cleanup() {
    local exit_code=$?
    release_git_lock
    exit $exit_code
}

trap cleanup EXIT INT TERM

# Main execution
echo -e "${GREEN}[GIT-SAFE]${NC} Checking for concurrent git operations..."

# Check for existing operations
if ! check_existing_git_operations; then
    echo -e "${RED}[GIT-SAFE]${NC} Aborting to prevent conflicts" >&2
    exit 1
fi

# Try to acquire lock
if ! acquire_git_lock "$@"; then
    exit 1
fi

echo -e "${GREEN}[GIT-SAFE]${NC} Executing: git $*"

# Get script directory for sequential executor
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# SEQUENTIAL_EXECUTOR="${SCRIPT_DIR}/sequential-executor.sh"  # Not used directly
WAIT_ALL="${SCRIPT_DIR}/wait_all.sh"

# Use wait_all.sh for atomic execution
if [ -x "$WAIT_ALL" ]; then
    # Execute atomically through wait_all.sh
    "$WAIT_ALL" -- git "$@"
else
    # Direct execution (fallback)
    git "$@"
fi

EXIT_CODE=$?

echo -e "${GREEN}[GIT-SAFE]${NC} Git operation completed with exit code: $EXIT_CODE"

exit $EXIT_CODE
