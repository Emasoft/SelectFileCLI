#!/usr/bin/env bash
# sequential_queue.sh - Universal sequential execution queue manager
# Version: 6.0.0
#
# This version implements the correct flow:
# 1. Detect if command can be atomified
# 2. If atomifiable, expand to atomic commands
# 3. Add all atomic commands to queue
# 4. Execute queue sequentially with wait_all.sh
# 5. Support queue management commands
#
set -euo pipefail

VERSION='6.0.0'

# Display help message
show_help() {
    cat << 'EOF'
sequential_queue.sh v6.0.0 - Universal sequential execution queue

USAGE:
    sequential_queue.sh [OPTIONS] -- COMMAND [ARGS...]
    sequential_queue.sh --queue-status
    sequential_queue.sh --queue-pause
    sequential_queue.sh --queue-resume
    sequential_queue.sh --queue-stop
    sequential_queue.sh --help

DESCRIPTION:
    Ensures only ONE command runs at a time across the entire project.
    Auto-detects git and make commands for special handling.
    Commands wait indefinitely for their turn in the queue.
    Automatically atomifies commands to process files individually.

OPTIONS:
    --help, -h             Show this help message
    --timeout SECONDS      Command timeout in seconds (default: 86400)
    --pipeline-timeout SEC Pipeline timeout in seconds (default: 86400)
    --memory-limit MB      Memory limit per process in MB (default: 2048)
    --log-dir PATH         Custom log directory (default: PROJECT_ROOT/logs)
    --verbose              Enable verbose output
    --no-atomify           Disable automatic command atomification
    --queue-status         Show current queue status
    --queue-pause          Pause queue execution
    --queue-resume         Resume queue execution
    --queue-stop           Stop queue and clear all pending commands

ENVIRONMENT VARIABLES:
    PIPELINE_TIMEOUT      Total pipeline timeout in seconds (default: 86400)
    MEMORY_LIMIT_MB       Memory limit per process in MB (default: 2048)
    TIMEOUT               Individual command timeout in seconds (default: 86400)
    VERBOSE               Set to 1 for verbose output
    ATOMIFY               Set to 0 to disable atomification globally

ATOMIFICATION:
    Commands are automatically broken down into atomic operations:
    - "ruff check src/" becomes individual "ruff check src/file.py" commands
    - Each atomic command is queued separately
    - All atomified commands are added to queue before execution starts
    - Single files are not atomified (already atomic)

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
    1. Atomify commands if possible
    2. Queue all commands before execution
    3. Process queue sequentially
    4. Only ONE process runs at a time
    5. Pipeline timeout applies to entire queue

EXAMPLES:
    # Git operations (auto-detected)
    sequential_queue.sh -- git commit -m "feat: new feature"
    sequential_queue.sh -- git push origin main

    # Make operations (auto-detected)
    sequential_queue.sh -- make test
    sequential_queue.sh -- make -j1 all

    # General commands (automatically atomified)
    sequential_queue.sh -- pytest tests/
    sequential_queue.sh -- ruff format src/
    sequential_queue.sh -- mypy --strict src/

    # Queue management
    sequential_queue.sh --queue-status
    sequential_queue.sh --queue-pause
    sequential_queue.sh --queue-resume

LOG FILES:
    Execution logs: PROJECT_ROOT/logs/sequential_queue_*.log
    Memory logs: PROJECT_ROOT/logs/memory_monitor_*.log

LOCK FILES:
    Lock directory: PROJECT_ROOT/.sequential-locks/seq-exec-PROJECT_HASH/
    Queue file: PROJECT_ROOT/.sequential-locks/seq-exec-PROJECT_HASH/queue.txt
    Pause file: PROJECT_ROOT/.sequential-locks/seq-exec-PROJECT_HASH/paused

EOF
    exit 0
}

# Queue management commands
queue_status() {
    if [[ ! -f "$QUEUE_FILE" ]]; then
        echo "Queue is empty"
        return
    fi

    echo "Queue Status:"
    echo "============="

    # Check if paused
    if [[ -f "$PAUSE_FILE" ]]; then
        echo "Status: PAUSED"
    else
        echo "Status: RUNNING"
    fi

    # Show current command
    if [[ -f "$CURRENT_PID_FILE" ]]; then
        local current_pid=$(cat "$CURRENT_PID_FILE" 2>/dev/null || echo 0)
        if [[ $current_pid -gt 0 ]] && kill -0 "$current_pid" 2>/dev/null; then
            local current_cmd=$(ps -p "$current_pid" -o args= 2>/dev/null || echo "unknown")
            echo "Current: PID $current_pid - $current_cmd"
        fi
    fi

    # Show queue
    echo ""
    echo "Queued Commands:"
    local count=0
    while IFS=: read -r pid timestamp cmd; do
        ((count++)) || true
        echo "  $count. PID $pid - $cmd"
    done < "$QUEUE_FILE"

    if [[ $count -eq 0 ]]; then
        echo "  (none)"
    fi
}

queue_pause() {
    touch "$PAUSE_FILE"
    echo "Queue paused. Use --queue-resume to continue."
}

queue_resume() {
    rm -f "$PAUSE_FILE"
    echo "Queue resumed."
}

queue_stop() {
    echo "Stopping queue and clearing all pending commands..."

    # Kill current process if running
    if [[ -f "$CURRENT_PID_FILE" ]]; then
        local current_pid=$(cat "$CURRENT_PID_FILE" 2>/dev/null || echo 0)
        if [[ $current_pid -gt 0 ]] && kill -0 "$current_pid" 2>/dev/null; then
            echo "Killing current process: PID $current_pid"
            kill_process_tree "$current_pid"
        fi
    fi

    # Clear queue
    > "$QUEUE_FILE"
    rm -f "$PAUSE_FILE"
    echo "Queue stopped and cleared."
}

# Parse command line options
CUSTOM_LOG_DIR=""
ATOMIFY="${ATOMIFY:-1}"  # Enable atomification by default
PARSED_TIMEOUT=""
PARSED_PIPELINE_TIMEOUT=""
PARSED_MEMORY_LIMIT=""
PARSED_VERBOSE=""
QUEUE_COMMAND=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --help|-h)
            show_help
            ;;
        --timeout)
            PARSED_TIMEOUT="$2"
            shift 2
            ;;
        --pipeline-timeout)
            PARSED_PIPELINE_TIMEOUT="$2"
            shift 2
            ;;
        --memory-limit)
            PARSED_MEMORY_LIMIT="$2"
            shift 2
            ;;
        --log-dir)
            CUSTOM_LOG_DIR="$2"
            shift 2
            ;;
        --verbose)
            PARSED_VERBOSE=1
            shift
            ;;
        --no-atomify)
            ATOMIFY=0
            shift
            ;;
        --queue-status)
            QUEUE_COMMAND="status"
            shift
            ;;
        --queue-pause)
            QUEUE_COMMAND="pause"
            shift
            ;;
        --queue-resume)
            QUEUE_COMMAND="resume"
            shift
            ;;
        --queue-stop)
            QUEUE_COMMAND="stop"
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

# Lock and state files
LOCK_BASE_DIR="${SEQUENTIAL_LOCK_BASE_DIR:-${PROJECT_ROOT}/.sequential-locks}"
LOCK_DIR="${LOCK_BASE_DIR}/seq-exec-${PROJECT_HASH}"
LOCKFILE="${LOCK_DIR}/executor.lock"
QUEUE_FILE="${LOCK_DIR}/queue.txt"
CURRENT_PID_FILE="${LOCK_DIR}/current.pid"
PIPELINE_TIMEOUT_FILE="${LOCK_DIR}/pipeline_timeout.txt"
PAUSE_FILE="${LOCK_DIR}/paused"

# Ensure lock directory exists
mkdir -p "$LOCK_DIR"

# Handle queue management commands
if [[ -n "$QUEUE_COMMAND" ]]; then
    case "$QUEUE_COMMAND" in
        status) queue_status ;;
        pause) queue_pause ;;
        resume) queue_resume ;;
        stop) queue_stop ;;
    esac
    exit 0
fi

# Check for help or no arguments
if [[ $# -eq 0 ]]; then
    show_help
fi

# Get the command and its arguments
COMMAND="${1:-}"
shift || true
ARGS=("$@")

# Source .env.development if it exists
if [ -f "${PROJECT_ROOT}/.env.development" ]; then
    set -a  # Export all variables
    source "${PROJECT_ROOT}/.env.development"
    set +a
fi

# Pipeline timeout (applies to entire chain)
PIPELINE_TIMEOUT="${PARSED_PIPELINE_TIMEOUT:-${PIPELINE_TIMEOUT:-86400}}"  # 24 hours default
MEMORY_LIMIT_MB="${PARSED_MEMORY_LIMIT:-${MEMORY_LIMIT_MB:-2048}}"
TIMEOUT="${PARSED_TIMEOUT:-${TIMEOUT:-86400}}"  # 24 hours default
VERBOSE="${PARSED_VERBOSE:-${VERBOSE:-0}}"

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
    local children
    children=$(pgrep -P "$pid" 2>/dev/null || true)
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
    local all_pids
    all_pids="$pid $(get_descendants "$pid")"

    # Send signal to all
    for p in $all_pids; do
        if kill -0 "$p" 2>/dev/null; then
            kill -"$signal" "$p" 2>/dev/null || true
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
            sleep "$PIPELINE_TIMEOUT"
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
                    local current
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
        local timeout_info
        timeout_info=$(cat "$PIPELINE_TIMEOUT_FILE" 2>/dev/null || echo "0:0")
        local start_time
        start_time=$(echo "$timeout_info" | cut -d: -f1)
        local timeout_val
        timeout_val=$(echo "$timeout_info" | cut -d: -f2)
        local now
        now=$(date +%s)
        local elapsed=$((now - start_time))

        if [ $elapsed -gt "$timeout_val" ]; then
            log ERROR "Pipeline already timed out (${elapsed}s > ${timeout_val}s)"
            # Clean up stale timeout file
            rm -f "$PIPELINE_TIMEOUT_FILE"
            log INFO "Cleaned up stale pipeline timeout - restarting pipeline"
            # Restart pipeline with fresh timeout
            echo "$(date +%s):$PIPELINE_TIMEOUT" > "$PIPELINE_TIMEOUT_FILE"
            log INFO "Pipeline timeout reset to ${PIPELINE_TIMEOUT}s"
        fi

        log INFO "Pipeline time remaining: $((timeout_val - elapsed))s"
    fi
}

# Execute a single command from the queue
execute_command() {
    local cmd_string="$1"
    local cmd_array=()

    # Parse command string into array
    eval "cmd_array=($cmd_string)"

    local command="${cmd_array[0]}"
    local args=("${cmd_array[@]:1}")

    # Apply special handling based on command type
    case "$command" in
        git)
            log INFO "Detected git command - applying safety checks"
            if ! check_git_safety "${args[0]:-}"; then
                return 1
            fi
            ;;
        make)
            log INFO "Detected make command - enforcing sequential execution"
            # Prepare make arguments
            mapfile -t args < <(prepare_make_command "${args[@]}")
            ;;
        *)
            # No special handling needed
            ;;
    esac

    log INFO "Executing: $command ${args[*]}"

    # Start memory monitor
    local monitor_pid=""
    if [ -x "${SCRIPT_DIR}/memory_monitor.sh" ]; then
        log INFO "Starting memory monitor"
        "${SCRIPT_DIR}/memory_monitor.sh" --pid $$ --limit "$MEMORY_LIMIT_MB" &
        monitor_pid=$!
    fi

    # Ensure wait_all.sh is available
    if [ ! -x "${SCRIPT_DIR}/wait_all.sh" ]; then
        log ERROR "wait_all.sh not found at: ${SCRIPT_DIR}/wait_all.sh"
        log ERROR "This script requires wait_all.sh for atomic execution"
        return 1
    fi

    # Execute through wait_all.sh
    "${SCRIPT_DIR}/wait_all.sh" --timeout "$TIMEOUT" -- "$command" "${args[@]}"
    local exit_code=$?

    # Stop memory monitor
    if [[ -n "$monitor_pid" ]]; then
        kill "$monitor_pid" 2>/dev/null || true
    fi

    log INFO "Command completed with exit code: $exit_code"
    return $exit_code
}

# Process the queue
process_queue() {
    local overall_exit_code=0

    while true; do
        # Check if paused
        while [[ -f "$PAUSE_FILE" ]]; do
            log INFO "Queue is paused. Waiting..."
            sleep 5
        done

        # Check if queue is empty
        if [[ ! -s "$QUEUE_FILE" ]]; then
            log INFO "Queue is empty"
            break
        fi

        # Get next command from queue
        local next_cmd=""
        local next_pid=""

        # Read first line and remove it atomically
        {
            flock -x 200
            if [[ -s "$QUEUE_FILE" ]]; then
                IFS=: read -r next_pid _ next_cmd < "$QUEUE_FILE"
                tail -n +2 "$QUEUE_FILE" > "${QUEUE_FILE}.tmp"
                mv -f "${QUEUE_FILE}.tmp" "$QUEUE_FILE"
            fi
        } 200>"${QUEUE_FILE}.lock"

        if [[ -z "$next_cmd" ]]; then
            continue
        fi

        # Wait for lock
        log INFO "Waiting for exclusive lock..."
        while true; do
            if mkdir "$LOCKFILE" 2>/dev/null; then
                echo $$ > "$CURRENT_PID_FILE"
                log INFO "Lock acquired"
                break
            fi

            # Check if current holder is alive
            local holder_pid=$(cat "$CURRENT_PID_FILE" 2>/dev/null || echo 0)
            if [[ $holder_pid -gt 0 ]] && ! kill -0 "$holder_pid" 2>/dev/null; then
                log WARN "Lock holder died, cleaning up"
                rm -f "$CURRENT_PID_FILE"
                rmdir "$LOCKFILE" 2>/dev/null || true
            fi

            sleep 1
        done

        # Execute command
        execute_command "$next_cmd"
        local exit_code=$?

        if [[ $exit_code -ne 0 ]]; then
            log ERROR "Command failed with exit code: $exit_code"
            overall_exit_code=$exit_code
            # Continue processing queue even on failure
        fi

        # Release lock
        rm -f "$CURRENT_PID_FILE"
        rmdir "$LOCKFILE" 2>/dev/null || true
        log INFO "Lock released"
    done

    return $overall_exit_code
}

# Cleanup function
cleanup() {
    local exit_code=$?

    # Remove from queue
    if [ -f "$QUEUE_FILE" ]; then
        grep -v "^$$:" "$QUEUE_FILE" > "${QUEUE_FILE}.tmp" 2>/dev/null || true
        mv -f "${QUEUE_FILE}.tmp" "$QUEUE_FILE" 2>/dev/null || true
    fi

    # Release lock if we hold it
    if [ -f "$CURRENT_PID_FILE" ]; then
        local current
        current=$(cat "$CURRENT_PID_FILE" 2>/dev/null || echo 0)
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

log INFO "Starting sequential queue for: $COMMAND ${ARGS[*]}"
log INFO "Project: $PROJECT_ROOT"

# Check pipeline timeout
check_pipeline_timeout

# STEP 1: Check if command can be atomified
if [[ $ATOMIFY -eq 1 ]]; then
    # Source atomifier if available
    ATOMIFIER_SCRIPT="${SCRIPT_DIR}/tool_atomifier.sh"
    if [[ -f "$ATOMIFIER_SCRIPT" ]]; then
        source "$ATOMIFIER_SCRIPT"

        # Generate atomic commands
        mapfile -t ATOMIC_COMMANDS < <(generate_atomic_commands "$COMMAND" "${ARGS[@]}" | grep "^ATOMIC:")

        [[ "${VERBOSE:-0}" -eq 1 ]] && echo "[SEQ-QUEUE] DEBUG: Generated ${#ATOMIC_COMMANDS[@]} atomic commands" >&2

        if [[ ${#ATOMIC_COMMANDS[@]} -gt 1 ]]; then
            echo "[SEQ-QUEUE] Command will be atomified into ${#ATOMIC_COMMANDS[@]} atomic operations" >&2

            # STEP 2-7: Add all atomic commands to queue
            for atomic_cmd in "${ATOMIC_COMMANDS[@]}"; do
                # Remove ATOMIC: prefix
                actual_cmd="${atomic_cmd#ATOMIC:}"

                # Skip "wait_all.sh --" prefix if present (shouldn't be there)
                if [[ "$actual_cmd" =~ ^wait_all\.sh[[:space:]]+--[[:space:]]+ ]]; then
                    actual_cmd="${actual_cmd#wait_all.sh -- }"
                fi

                # Add to queue
                echo "$$:$(date '+%s'):$actual_cmd" >> "$QUEUE_FILE"
                log INFO "Added atomic command to queue: $actual_cmd"
            done

            # STEP 9: Process the queue
            log INFO "Processing queue with ${#ATOMIC_COMMANDS[@]} atomic commands"
            process_queue
            exit_code=$?

            if [[ $exit_code -eq 0 ]]; then
                echo "[SEQ-QUEUE] All ${#ATOMIC_COMMANDS[@]} atomic commands completed successfully" >&2
            else
                echo "[SEQ-QUEUE] Queue processing failed with exit code: $exit_code" >&2
            fi

            exit $exit_code
        elif [[ ${#ATOMIC_COMMANDS[@]} -eq 1 ]]; then
            # Single file - proceed with default sequence
            log INFO "Single atomic command detected, proceeding with default sequence"
        fi
    fi
fi

# STEP 8: DEFAULT SEQUENCE
# If we reach here, either:
# 1. Atomification is disabled
# 2. Command doesn't need atomification (single file)
# 3. Atomifier is not available
# 4. No atomic commands were generated

# Add single command to queue
echo "$$:$(date '+%s'):$COMMAND ${ARGS[*]}" >> "$QUEUE_FILE"
log INFO "Added to queue (PID $$)"

# Process the queue
process_queue
exit $?