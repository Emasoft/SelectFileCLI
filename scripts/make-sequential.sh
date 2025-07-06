#!/usr/bin/env bash
# make-sequential.sh - Wrapper for make commands to ensure sequential execution
# Version: 3.0.0
#
# This script ensures that only one make command runs at a time
# preventing the issue where multiple make commands spawn multiple
# sequential executors
#
set -euo pipefail

VERSION='3.0.0'

# Display help message
show_help() {
    cat << 'EOF'
make-sequential.sh v3.0.0 - Sequential make command wrapper

USAGE:
    make-sequential.sh [OPTIONS] [MAKE_ARGS...]

DESCRIPTION:
    Ensures only one make command runs at a time across the project.
    Prevents multiple make commands from spawning parallel executors.

OPTIONS:
    --help, -h    Show this help message

    All other arguments are passed directly to make.

EXAMPLES:
    # Run make test sequentially
    make-sequential.sh test

    # Run make with multiple targets
    make-sequential.sh clean build test

    # Pass make options
    make-sequential.sh -j1 all

    # Run specific makefile
    make-sequential.sh -f custom.mk target

FEATURES:
    - Global lock per project
    - Queue management for waiting processes
    - Stale lock detection and cleanup
    - Integration with wait_all.sh for atomic execution

LOCK FILES:
    Lock directory: /tmp/make-lock-PROJECT_HASH
    Queue file: /tmp/make-queue-PROJECT_HASH

TIMEOUT:
    Maximum wait time: 300 seconds (5 minutes)

LOG OUTPUT:
    All operations are logged with timestamps and color coding:
    - GREEN: Info messages
    - YELLOW: Warnings
    - RED: Errors

EOF
    exit 0
}

# Check for help flag
if [[ $# -eq 0 ]] || [[ "$1" == "--help" ]] || [[ "$1" == "-h" ]]; then
    show_help
fi

# Store script arguments for use in functions
SCRIPT_ARGS="$*"

# Get project info
PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
PROJECT_HASH=$(echo "$PROJECT_ROOT" | shasum | cut -d' ' -f1 | head -c 8)

# Global make lock
MAKE_LOCK="/tmp/make-lock-${PROJECT_HASH}"
MAKE_QUEUE="/tmp/make-queue-${PROJECT_HASH}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Log functions
log_info() {
    echo -e "${GREEN}[MAKE-SEQ]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $*"
}

log_warn() {
    echo -e "${YELLOW}[MAKE-SEQ]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $*" >&2
}

log_error() {
    echo -e "${RED}[MAKE-SEQ]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $*" >&2
}

# Cleanup on exit
cleanup() {
    # Remove our entry from queue
    if [ -f "$MAKE_QUEUE" ]; then
        grep -v "^$$:" "$MAKE_QUEUE" > "${MAKE_QUEUE}.tmp" 2>/dev/null || true
        mv -f "${MAKE_QUEUE}.tmp" "$MAKE_QUEUE" 2>/dev/null || true
    fi

    # Release lock if we hold it
    if [ -d "$MAKE_LOCK" ]; then
        local lock_pid=$(cat "$MAKE_LOCK/pid" 2>/dev/null || echo 0)
        if [ "$lock_pid" -eq "$$" ]; then
            rm -f "$MAKE_LOCK/pid"
            rmdir "$MAKE_LOCK" 2>/dev/null || true
        fi
    fi
}
trap cleanup EXIT

# Try to acquire lock
acquire_lock() {
    # Note: function doesn't use arguments, will use global script args
    local max_wait=300  # 5 minutes max wait
    local waited=0

    while true; do
        # Try to create lock directory
        if mkdir "$MAKE_LOCK" 2>/dev/null; then
            echo $$ > "$MAKE_LOCK/pid"
            return 0
        fi

        # Check if lock holder is still alive
        local lock_pid=$(cat "$MAKE_LOCK/pid" 2>/dev/null || echo 0)
        if ! kill -0 "$lock_pid" 2>/dev/null; then
            log_warn "Stale lock detected (PID $lock_pid), removing"
            rm -f "$MAKE_LOCK/pid"
            rmdir "$MAKE_LOCK" 2>/dev/null || true
            continue
        fi

        # Add to queue if not already there
        if ! grep -q "^$$:" "$MAKE_QUEUE" 2>/dev/null; then
            # Use global script arguments (passed to main script)
            echo "$$:$SCRIPT_ARGS" >> "$MAKE_QUEUE"
            log_info "Added to queue (PID $$): make $SCRIPT_ARGS"
        fi

        # Show status every 10 seconds
        if (( waited % 10 == 0 )); then
            log_info "Waiting for make lock (held by PID $lock_pid)..."
            if [ -f "$MAKE_QUEUE" ]; then
                local queue_size=$(wc -l < "$MAKE_QUEUE" | tr -d ' ')
                log_info "Queue size: $queue_size"
            fi
        fi

        sleep 1
        ((waited++))

        if (( waited > max_wait )); then
            log_error "Timeout waiting for make lock"
            exit 1
        fi
    done
}

# Main execution
log_info "Requesting make lock for: make $*"

# Acquire lock
acquire_lock

# Remove from queue
if [ -f "$MAKE_QUEUE" ]; then
    grep -v "^$$:" "$MAKE_QUEUE" > "${MAKE_QUEUE}.tmp" 2>/dev/null || true
    mv -f "${MAKE_QUEUE}.tmp" "$MAKE_QUEUE" 2>/dev/null || true
fi

log_info "Lock acquired, executing: make $*"

# Execute make command
cd "$PROJECT_ROOT"

# Get script directory for wait_all.sh
if command -v realpath >/dev/null 2>&1; then
    SCRIPT_DIR="$(realpath "$(dirname "${BASH_SOURCE[0]}")")"
elif command -v readlink >/dev/null 2>&1 && readlink -f "${BASH_SOURCE[0]}" >/dev/null 2>&1; then
    SCRIPT_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
else
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi
WAIT_ALL="${SCRIPT_DIR}/wait_all.sh"

if [ ! -x "$WAIT_ALL" ]; then
    log_error "wait_all.sh not found at: $WAIT_ALL"
    exit 1
fi

# Use wait_all.sh instead of exec
"$WAIT_ALL" -- make "$@"
