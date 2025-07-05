#!/usr/bin/env bash
# git-safe.sh - Safe git wrapper that prevents concurrent git operations
# This wrapper ensures only ONE git operation runs at a time

set -euo pipefail

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
    local git_procs=$(pgrep -f "git (commit|merge|rebase|cherry-pick|push|pull)" 2>/dev/null || true)
    
    if [ -n "$git_procs" ]; then
        echo -e "${RED}ERROR: Git operations already in progress:${NC}" >&2
        for pid in $git_procs; do
            local cmd=$(ps -p "$pid" -o args= 2>/dev/null || echo "unknown")
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
            local current_op=$(cat "$GIT_OPERATION_FILE" 2>/dev/null || echo "unknown")
            local pid=$(echo "$current_op" | cut -d: -f1)
            
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
SEQUENTIAL_EXECUTOR="${SCRIPT_DIR}/sequential-executor.sh"
WAIT_ALL="${SCRIPT_DIR}/wait_all.sh"

# Use sequential executor if available, otherwise direct git
if [ -x "$SEQUENTIAL_EXECUTOR" ] && [ -x "$WAIT_ALL" ]; then
    # Execute through sequential pipeline
    "$WAIT_ALL" -- "$SEQUENTIAL_EXECUTOR" git "$@"
else
    # Direct execution (fallback)
    git "$@"
fi

EXIT_CODE=$?

echo -e "${GREEN}[GIT-SAFE]${NC} Git operation completed with exit code: $EXIT_CODE"

exit $EXIT_CODE