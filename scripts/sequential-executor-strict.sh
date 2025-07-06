#!/usr/bin/env bash
# sequential-executor-strict.sh - TRUE sequential execution
#
# Principles:
# 1. Processes wait INDEFINITELY for their turn - no timeouts on lock acquisition
# 2. Only ONE process runs at a time - no exceptions
# 3. Pipeline timeout applies to the entire execution chain
# 4. If pipeline times out, ALL processes are killed
# 5. Commands should be ATOMIC - smallest possible units of work
#
# CRITICAL: This executor works with wait_all.sh to form a sequential chain.
# Each wait_all.sh command should be atomic to minimize memory usage and
# enable precise failure isolation.
#
# Example of ATOMIC commands (GOOD):
#   sequential-executor.sh ruff format src/main.py
#   sequential-executor.sh pytest tests/test_one.py
#   sequential-executor.sh mypy --strict src/module.py
#
# Example of NON-ATOMIC commands (BAD):
#   sequential-executor.sh ruff format .
#   sequential-executor.sh pytest
#   sequential-executor.sh mypy --strict src/
#
set -euo pipefail

# Check bash version (require 3.2+)
# Note: Bash 3.2 is the default on macOS
if [ "${BASH_VERSION%%.*}" -lt 3 ] || { [ "${BASH_VERSION%%.*}" -eq 3 ] && [ "${BASH_VERSION#*.}" -lt 2 ]; }; then
    echo "ERROR: This script requires bash 3.2 or higher" >&2
    exit 1
fi

# Global configuration
PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
PROJECT_HASH=$(echo "$PROJECT_ROOT" | shasum | cut -d' ' -f1 | head -c 8)

# Lock and state files
LOCK_DIR="/tmp/seq-exec-${PROJECT_HASH}"
LOCKFILE="${LOCK_DIR}/executor.lock"
QUEUE_FILE="${LOCK_DIR}/queue.txt"
CURRENT_PID_FILE="${LOCK_DIR}/current.pid"
# PIPELINE_START_FILE="${LOCK_DIR}/pipeline_start.txt"  # Not used
PIPELINE_TIMEOUT_FILE="${LOCK_DIR}/pipeline_timeout.txt"

# Pipeline timeout (applies to entire chain)
PIPELINE_TIMEOUT="${PIPELINE_TIMEOUT:-7200}"  # 2 hours default

# Ensure lock directory exists
mkdir -p "$LOCK_DIR"

# Create logs directory
LOGS_DIR="${PROJECT_ROOT}/logs"
mkdir -p "$LOGS_DIR"
EXEC_LOG="${LOGS_DIR}/sequential_executor_strict_$(date '+%Y%m%d_%H%M%S')_$$.log"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Logging functions
log() {
    local level=$1; shift
    local color=""
    case $level in
        ERROR) color=$RED ;;
        WARN)  color=$YELLOW ;;
        INFO)  color=$GREEN ;;
        DEBUG) color=$BLUE ;;
    esac
    local msg
    msg="[SEQ-STRICT] $(date '+%Y-%m-%d %H:%M:%S') [$level] $*"
    echo -e "${color}${msg}${NC}" >&2
    echo "$msg" >> "$EXEC_LOG"
}

# Get all descendant PIDs
get_descendants() {
    local pid=$1
    local children=$(pgrep -P "$pid" 2>/dev/null || true)
    for child in $children; do
        echo "$child"
        get_descendants "$child"
    done
}

# Kill entire process tree
kill_process_tree() {
    local pid=$1
    local signal=${2:-TERM}

    # Get all descendants first
    local all_pids="$pid $(get_descendants "$pid")"

    # Send signal to all
    for p in $all_pids; do
        if kill -0 "$p" 2>/dev/null; then
            kill -$signal "$p" 2>/dev/null || true
        fi
    done

    # Give time to terminate gracefully
    sleep 2

    # Force kill any remaining
    for p in $all_pids; do
        if kill -0 "$p" 2>/dev/null; then
            kill -KILL "$p" 2>/dev/null || true
        fi
    done
}

# Check and enforce pipeline timeout
check_pipeline_timeout() {
    if [ ! -f "$PIPELINE_TIMEOUT_FILE" ]; then
        # First process in pipeline - set timeout
        echo "$(date +%s):$PIPELINE_TIMEOUT" > "$PIPELINE_TIMEOUT_FILE"
        log INFO "Pipeline timeout set to ${PIPELINE_TIMEOUT}s"

        # Start timeout monitor in background
        (
            sleep $PIPELINE_TIMEOUT
            if [ -f "$PIPELINE_TIMEOUT_FILE" ]; then
                log ERROR "PIPELINE TIMEOUT after ${PIPELINE_TIMEOUT}s - killing all processes"

                # Kill all processes in queue
                if [ -f "$QUEUE_FILE" ]; then
                    while IFS=: read -r pid _ cmd; do
                        if kill -0 "$pid" 2>/dev/null; then
                            log WARN "Killing queued process PID $pid"
                            kill_process_tree "$pid"
                        fi
                    done < "$QUEUE_FILE"
                fi

                # Kill current process
                if [ -f "$CURRENT_PID_FILE" ]; then
                    current=$(cat "$CURRENT_PID_FILE" 2>/dev/null || echo 0)
                    if [ "$current" -gt 0 ] && kill -0 "$current" 2>/dev/null; then
                        log WARN "Killing current process PID $current"
                        kill_process_tree "$current"
                    fi
                fi

                # Clean up all locks
                rm -rf "$LOCK_DIR"
            fi
        ) &
    else
        # Check if pipeline already timed out
        local timeout_info=$(cat "$PIPELINE_TIMEOUT_FILE" 2>/dev/null || echo "0:0")
        local start_time=$(echo "$timeout_info" | cut -d: -f1)
        local timeout=$(echo "$timeout_info" | cut -d: -f2)
        local now=$(date +%s)
        local elapsed=$((now - start_time))

        if [ $elapsed -gt $timeout ]; then
            log ERROR "Pipeline already timed out (${elapsed}s > ${timeout}s)"
            exit 126  # Pipeline timeout exit code
        fi

        log INFO "Pipeline time remaining: $((timeout - elapsed))s"
    fi
}

# Cleanup function
cleanup() {
    local exit_code=$?

    # Stop memory monitor if running
    if [ -n "${MONITOR_PID:-}" ]; then
        kill $MONITOR_PID 2>/dev/null || true
    fi

    # Remove from queue
    if [ -f "$QUEUE_FILE" ]; then
        grep -v "^$$:" "$QUEUE_FILE" > "${QUEUE_FILE}.tmp" 2>/dev/null || true
        mv -f "${QUEUE_FILE}.tmp" "$QUEUE_FILE" 2>/dev/null || true
    fi

    # Release lock if we hold it
    if [ -f "$CURRENT_PID_FILE" ]; then
        local current=$(cat "$CURRENT_PID_FILE" 2>/dev/null || echo 0)
        if [ "$current" -eq "$$" ]; then
            rm -f "$CURRENT_PID_FILE"
            rmdir "$LOCKFILE" 2>/dev/null || true
            log INFO "Lock released"

            # If queue is empty, pipeline is complete
            if [ ! -s "$QUEUE_FILE" ]; then
                log INFO "Queue empty - pipeline complete"
                rm -f "$PIPELINE_TIMEOUT_FILE"
            fi
        fi
    fi

    log INFO "Sequential executor exiting with code: $exit_code"
    echo "Log saved to: $EXEC_LOG" >&2

    exit $exit_code
}

trap cleanup EXIT INT TERM

# Main execution
log INFO "Starting strict sequential executor for: $*"
log INFO "Project: $PROJECT_ROOT"

# Check pipeline timeout
check_pipeline_timeout

# Add to queue
echo "$$:$(date '+%s'):$*" >> "$QUEUE_FILE"
log INFO "Added to queue (PID $$)"

# Wait for our turn - INDEFINITELY
log INFO "Waiting for exclusive lock (will wait indefinitely)..."
WAIT_COUNT=0

while true; do
    # Try to acquire lock
    if mkdir "$LOCKFILE" 2>/dev/null; then
        echo $$ > "$CURRENT_PID_FILE"
        log INFO "Lock acquired"
        break
    fi

    # Get current lock holder
    HOLDER_PID=$(cat "$CURRENT_PID_FILE" 2>/dev/null || echo 0)

    if [ "$HOLDER_PID" -gt 0 ]; then
        # Check if holder is alive
        if kill -0 "$HOLDER_PID" 2>/dev/null; then
            # Log status periodically
            if [ $((WAIT_COUNT % 60)) -eq 0 ] && [ $WAIT_COUNT -gt 0 ]; then
                cmd=$(ps -p "$HOLDER_PID" -o args= 2>/dev/null | head -1 || echo "unknown")
                wait_time=$((WAIT_COUNT))
                log INFO "Still waiting for PID $HOLDER_PID: $cmd (${wait_time}s elapsed)"

                # Show queue position
                if [ -f "$QUEUE_FILE" ]; then
                    position=$(grep -n "^$$:" "$QUEUE_FILE" 2>/dev/null | cut -d: -f1 || echo "?")
                    total=$(wc -l < "$QUEUE_FILE" 2>/dev/null || echo "?")
                    log INFO "Queue position: $position of $total"
                fi
            fi
        else
            # Holder is dead, clean up
            log WARN "Lock holder (PID $HOLDER_PID) died unexpectedly"
            rm -f "$CURRENT_PID_FILE"
            rmdir "$LOCKFILE" 2>/dev/null || true

            # This is an error condition - previous process died
            log ERROR "Previous process died - sequential chain broken"
            # Continue to acquire lock and execute
        fi
    else
        # No PID file but lock exists - clean up
        log WARN "Stale lock detected, cleaning up"
        rmdir "$LOCKFILE" 2>/dev/null || true
    fi

    sleep 1
    ((WAIT_COUNT++))
done

# Execute the command
log INFO "Executing: $*"

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Start memory monitor
if [ -x "${SCRIPT_DIR}/memory_monitor.sh" ]; then
    log INFO "Starting memory monitor"
    "${SCRIPT_DIR}/memory_monitor.sh" --pid $$ --limit "${MEMORY_LIMIT_MB:-2048}" &
    MONITOR_PID=$!
fi

# Execute through wait_all.sh if available
if [ -x "${SCRIPT_DIR}/wait_all.sh" ]; then
    "${SCRIPT_DIR}/wait_all.sh" --timeout "${TIMEOUT:-1800}" -- "$@"
    EXIT_CODE=$?
else
    "$@"
    EXIT_CODE=$?
fi

log INFO "Command completed with exit code: $EXIT_CODE"
exit $EXIT_CODE
