#!/usr/bin/env bash
# make-sequential.sh - Wrapper for make commands to ensure sequential execution
#
# This script ensures that only one make command runs at a time
# preventing the issue where multiple make commands spawn multiple
# sequential executors
#
set -euo pipefail

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
            echo "$$:$*" >> "$MAKE_QUEUE"
            log_info "Added to queue (PID $$): make $*"
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
