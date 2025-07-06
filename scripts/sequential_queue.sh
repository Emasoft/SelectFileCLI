#!/usr/bin/env bash
# sequential_queue.sh - Universal sequential execution queue manager
# Version: 3.0.0
#
# This script consolidates:
# - sequential-executor.sh (general queue management)
# - git-specific safety checks (integrated)
# - make-sequential.sh (make-specific handling)
#
# Auto-detects git and make commands for special handling while
# maintaining a single queue for ALL operations.
#
set -euo pipefail

VERSION='3.0.0'

# Display help message
show_help() {
    cat << 'EOF'
sequential_queue.sh v3.0.0 - Universal sequential execution queue

USAGE:
    sequential_queue.sh [OPTIONS] -- COMMAND [ARGS...]
    sequential_queue.sh --help

DESCRIPTION:
    Ensures only ONE command runs at a time across the entire project.
    Auto-detects git and make commands for special handling.
    Commands wait indefinitely for their turn in the queue.

OPTIONS:
    --help, -h             Show this help message
    --timeout SECONDS      Command timeout in seconds (default: 86400)
    --pipeline-timeout SEC Pipeline timeout in seconds (default: 86400)
    --memory-limit MB      Memory limit per process in MB (default: 2048)
    --log-dir PATH         Custom log directory (default: PROJECT_ROOT/logs)
    --verbose              Enable verbose output

ENVIRONMENT VARIABLES:
    PIPELINE_TIMEOUT      Total pipeline timeout in seconds (default: 86400)
    MEMORY_LIMIT_MB       Memory limit per process in MB (default: 2048)
    TIMEOUT               Individual command timeout in seconds (default: 86400)
    VERBOSE               Set to 1 for verbose output

SPECIAL HANDLING:
    Git Commands:
        - Checks for concurrent git operations
        - Prevents git lock conflicts
        - Handles pre-commit hooks safely
        - Sets GIT_COMMIT_IN_PROGRESS for commits

    Make Commands:
        - Prevents parallel make execution
        - Automatically adds -j1 if not specified
        - Handles recursive makefiles safely

PRINCIPLES:
    1. Processes wait INDEFINITELY for their turn
    2. Only ONE process runs at a time - no exceptions
    3. Pipeline timeout applies to entire execution chain
    4. Commands should be ATOMIC (smallest units of work)

EXAMPLES:
    # Git operations (auto-detected)
    sequential_queue.sh -- git commit -m "feat: new feature"
    sequential_queue.sh -- git push origin main

    # Make operations (auto-detected)
    sequential_queue.sh -- make test
    sequential_queue.sh -- make -j1 all

    # General commands
    sequential_queue.sh -- pytest tests/test_one.py
    sequential_queue.sh -- ruff format src/main.py
    sequential_queue.sh -- mypy --strict src/

ATOMIC vs NON-ATOMIC:
    GOOD (atomic):
        sequential_queue.sh -- ruff format src/main.py
        sequential_queue.sh -- pytest tests/test_auth.py
        sequential_queue.sh -- git commit -m "fix: typo"

    BAD (non-atomic):
        sequential_queue.sh -- ruff format .
        sequential_queue.sh -- pytest
        sequential_queue.sh -- make all

LOG FILES:
    Execution logs: PROJECT_ROOT/logs/sequential_queue_*.log
    Memory logs: PROJECT_ROOT/logs/memory_monitor_*.log

LOCK FILES:
    Lock directory: PROJECT_ROOT/.sequential-locks/seq-exec-PROJECT_HASH/
    Queue file: PROJECT_ROOT/.sequential-locks/seq-exec-PROJECT_HASH/queue.txt

EOF
    exit 0
}

# Parse command line options
CUSTOM_LOG_DIR=""
while [[ $# -gt 0 ]]; do
    case $1 in
        --help|-h)
            show_help
            ;;
        --timeout)
            TIMEOUT="$2"
            shift 2
            ;;
        --pipeline-timeout)
            PIPELINE_TIMEOUT="$2"
            shift 2
            ;;
        --memory-limit)
            MEMORY_LIMIT_MB="$2"
            shift 2
            ;;
        --log-dir)
            CUSTOM_LOG_DIR="$2"
            shift 2
            ;;
        --verbose)
            VERBOSE=1
            shift
            ;;
        --)
            shift
            break
            ;;
        *)
            break
            ;;
    esac
done

# Check for help or no arguments
if [[ $# -eq 0 ]]; then
    show_help
fi

# Verify minimum bash version
if [ "${BASH_VERSION%%.*}" -lt 3 ] || { [ "${BASH_VERSION%%.*}" -eq 3 ] && [ "${BASH_VERSION#*.}" -lt 2 ]; }; then
    echo "ERROR: This script requires bash 3.2 or higher" >&2
    echo "Current version: $BASH_VERSION" >&2
    exit 1
fi

# Global configuration
PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
PROJECT_HASH=$(echo "$PROJECT_ROOT" | shasum | cut -d' ' -f1 | head -c 8)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Lock and state files (single queue for everything)
# Use project-local directory to avoid conflicts between projects
# Source .env.development if it exists
if [ -f "${PROJECT_ROOT}/.env.development" ]; then
    set -a  # Export all variables
    source "${PROJECT_ROOT}/.env.development"
    set +a
fi

# Use configured lock directory or default to project-local
LOCK_BASE_DIR="${SEQUENTIAL_LOCK_BASE_DIR:-${PROJECT_ROOT}/.sequential-locks}"
LOCK_DIR="${LOCK_BASE_DIR}/seq-exec-${PROJECT_HASH}"
LOCKFILE="${LOCK_DIR}/executor.lock"
QUEUE_FILE="${LOCK_DIR}/queue.txt"
CURRENT_PID_FILE="${LOCK_DIR}/current.pid"
PIPELINE_TIMEOUT_FILE="${LOCK_DIR}/pipeline_timeout.txt"

# Pipeline timeout (applies to entire chain)
PIPELINE_TIMEOUT="${PIPELINE_TIMEOUT:-86400}"  # 24 hours default
MEMORY_LIMIT_MB="${MEMORY_LIMIT_MB:-2048}"
TIMEOUT="${TIMEOUT:-86400}"  # 24 hours default
VERBOSE="${VERBOSE:-0}"

# Ensure lock directory exists
mkdir -p "$LOCK_DIR"

# Clean up stale pipeline timeout if no processes are running
if [ -f "$PIPELINE_TIMEOUT_FILE" ] && [ ! -f "$CURRENT_PID_FILE" ]; then
    log WARN "Found stale pipeline timeout file - cleaning up"
    rm -f "$PIPELINE_TIMEOUT_FILE"
fi

# Create logs directory
if [[ -n "$CUSTOM_LOG_DIR" ]]; then
    LOGS_DIR="$CUSTOM_LOG_DIR"
else
    LOGS_DIR="${LOG_DIR:-${PROJECT_ROOT}/logs}"
fi
mkdir -p "$LOGS_DIR"
EXEC_LOG="${LOGS_DIR}/sequential_queue_$(date '+%Y%m%d_%H%M%S')_$$.log"

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
    msg="[SEQ-QUEUE] $(date '+%Y-%m-%d %H:%M:%S') [$level] $*"
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

# Git-specific safety checks
check_git_safety() {
    local git_cmd="${1:-}"

    # Skip if already in a git hook to prevent deadlocks
    if [ -n "${GIT_DIR:-}" ] || [ -n "${GIT_WORK_TREE:-}" ]; then
        log INFO "Already in git hook - skipping safety checks"
        return 0
    fi

    # Check for existing git operations
    local git_procs
    git_procs=$(pgrep -f "git (commit|merge|rebase|cherry-pick|push|pull)" 2>/dev/null || true)

    for pid in $git_procs; do
        # Skip our own process
        [ "$pid" -eq "$$" ] && continue

        local cmd
        cmd=$(ps -p "$pid" -o args= 2>/dev/null || echo "unknown")
        log ERROR "Git operation already in progress: PID $pid - $cmd"
        return 1
    done

    # Check for git lock files
    if [ -f "$PROJECT_ROOT/.git/index.lock" ]; then
        log ERROR "Git index lock exists - another git process may be running"
        log WARN "To force remove: rm -f $PROJECT_ROOT/.git/index.lock"
        return 1
    fi

    # Set environment for commit hooks
    if [[ "$git_cmd" == "commit" ]]; then
        export GIT_COMMIT_IN_PROGRESS=1
        export SEQUENTIAL_EXECUTOR_PID=$$
        log INFO "Set GIT_COMMIT_IN_PROGRESS=1 for pre-commit hooks"
    fi

    return 0
}

# Make-specific handling
prepare_make_command() {
    local make_args=("$@")

    # Check if -j is already specified
    local has_j_flag=0
    for arg in "${make_args[@]}"; do
        if [[ "$arg" =~ ^-j ]]; then
            has_j_flag=1
            break
        fi
    done

    # Add -j1 if not specified
    if [ $has_j_flag -eq 0 ]; then
        make_args+=("-j1")
        log WARN "Added -j1 to make command for safety"
    fi

    echo "${make_args[@]}"
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
                    local current=$(cat "$CURRENT_PID_FILE" 2>/dev/null || echo 0)
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
            # Clean up stale timeout file
            rm -f "$PIPELINE_TIMEOUT_FILE"
            log INFO "Cleaned up stale pipeline timeout - restarting pipeline"
            # Restart pipeline with fresh timeout
            echo "$(date +%s):$PIPELINE_TIMEOUT" > "$PIPELINE_TIMEOUT_FILE"
            log INFO "Pipeline timeout reset to ${PIPELINE_TIMEOUT}s"
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

    log INFO "Sequential queue exiting with code: $exit_code"
    [[ $VERBOSE -eq 1 ]] && echo "Log saved to: $EXEC_LOG" >&2

    exit $exit_code
}

trap cleanup EXIT INT TERM

# Main execution

# Get the command and its arguments
COMMAND="${1:-}"
shift || true
ARGS=("$@")

# Apply special handling based on command type
case "$COMMAND" in
    git)
        log INFO "Detected git command - applying safety checks"
        if ! check_git_safety "${ARGS[0]:-}"; then
            exit 1
        fi
        ;;
    make)
        log INFO "Detected make command - enforcing sequential execution"
        # Prepare make arguments
        ARGS=($(prepare_make_command "${ARGS[@]}"))
        ;;
    *)
        # No special handling needed
        ;;
esac

log INFO "Starting sequential queue for: $COMMAND ${ARGS[*]}"
log INFO "Project: $PROJECT_ROOT"

# Check pipeline timeout
check_pipeline_timeout

# Add to queue
echo "$$:$(date '+%s'):$COMMAND ${ARGS[*]}" >> "$QUEUE_FILE"
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
log INFO "Executing: $COMMAND ${ARGS[*]}"

# Start memory monitor
# NOTE: memory_monitor.sh is NOT wrapped in wait_all.sh because:
# 1. It needs to run in background as a monitor
# 2. It's part of the process management infrastructure
# 3. Wrapping it would prevent proper background execution
if [ -x "${SCRIPT_DIR}/memory_monitor.sh" ]; then
    log INFO "Starting memory monitor"
    "${SCRIPT_DIR}/memory_monitor.sh" --pid $$ --limit "$MEMORY_LIMIT_MB" &
    MONITOR_PID=$!
fi

# Ensure wait_all.sh is available
if [ ! -x "${SCRIPT_DIR}/wait_all.sh" ]; then
    log ERROR "wait_all.sh not found at: ${SCRIPT_DIR}/wait_all.sh"
    log ERROR "This script requires wait_all.sh for atomic execution"
    exit 1
fi

# Execute through wait_all.sh
"${SCRIPT_DIR}/wait_all.sh" --timeout "$TIMEOUT" -- "$COMMAND" "${ARGS[@]}"
EXIT_CODE=$?

log INFO "Command completed with exit code: $EXIT_CODE"
exit $EXIT_CODE
