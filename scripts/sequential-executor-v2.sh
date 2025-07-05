#!/usr/bin/env bash
# sequential-executor-v2.sh - Improved sequential execution with deadlock prevention
#
# Key improvements:
# 1. Deadlock detection using dependency tracking
# 2. Lock acquisition timeout with configurable retry
# 3. Better visibility into lock holders and waiters
# 4. Automatic deadlock resolution
#
set -euo pipefail

# Check if we're already inside a sequential executor to prevent deadlocks
if [ -n "${SEQUENTIAL_EXECUTOR_PID:-}" ]; then
    # We're already inside - check if it's the same process tree
    if [ "${SEQUENTIAL_EXECUTOR_PID}" -eq "$PPID" ] || [ "${SEQUENTIAL_EXECUTOR_PID}" -eq "$BASHPID" ]; then
        echo "[SEQUENTIAL-V2] Already inside sequential executor (PID $SEQUENTIAL_EXECUTOR_PID), bypassing lock" >&2
        exec "$@"
    fi
fi

# Set environment variable to detect nested calls
export SEQUENTIAL_EXECUTOR_PID=$$

# Check bash version (require 4.0+)
if [ "${BASH_VERSION%%.*}" -lt 4 ]; then
    echo "ERROR: This script requires bash 4.0 or higher" >&2
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
DEPS_FILE="${LOCK_DIR}/dependencies.txt"  # Track who's waiting for whom
DEADLOCK_CHECK_FILE="${LOCK_DIR}/deadlock_check.lock"

# Timeouts and limits
MAX_LOCK_WAIT="${MAX_LOCK_WAIT:-300}"  # 5 minutes default
DEADLOCK_CHECK_INTERVAL=10              # Check for deadlocks every 10 seconds
LOCK_TIMEOUT="${LOCK_TIMEOUT:-1800}"    # Max time to hold lock (30 min)

# Ensure lock directory exists
mkdir -p "$LOCK_DIR"

# Create logs directory
LOGS_DIR="${PROJECT_ROOT}/logs"
mkdir -p "$LOGS_DIR"
EXEC_LOG="${LOGS_DIR}/sequential_executor_v2_$(date '+%Y%m%d_%H%M%S')_$$.log"

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
    local msg="[SEQ-V2] $(date '+%Y-%m-%d %H:%M:%S') [$level] $*"
    echo -e "${color}${msg}${NC}" >&2
    echo "$msg" >> "$EXEC_LOG"
}

# Record dependency (who's waiting for whom)
record_dependency() {
    local waiter=$1
    local holder=$2
    echo "$waiter:$holder:$(date '+%s')" >> "$DEPS_FILE"
}

# Clear our dependencies
clear_dependencies() {
    if [ -f "$DEPS_FILE" ]; then
        grep -v "^$$:" "$DEPS_FILE" > "${DEPS_FILE}.tmp" 2>/dev/null || true
        mv -f "${DEPS_FILE}.tmp" "$DEPS_FILE" 2>/dev/null || true
    fi
}

# Check for circular dependencies (deadlock)
check_deadlock() {
    local start_pid=$1
    local current_pid=$2
    local visited=("$@")
    
    # Get who current_pid is waiting for
    if [ -f "$DEPS_FILE" ]; then
        local waiting_for=$(grep "^$current_pid:" "$DEPS_FILE" 2>/dev/null | cut -d: -f2 | head -1)
        
        if [ -n "$waiting_for" ]; then
            # Check if we've come full circle
            if [ "$waiting_for" -eq "$start_pid" ]; then
                log ERROR "DEADLOCK DETECTED: Circular dependency involving PIDs: ${visited[*]} -> $waiting_for"
                return 0  # Deadlock found
            fi
            
            # Check if we've already visited this PID (loop detection)
            for v in "${visited[@]}"; do
                if [ "$v" -eq "$waiting_for" ]; then
                    log WARN "Dependency loop detected at PID $waiting_for"
                    return 1
                fi
            done
            
            # Recurse to check the next link in the chain
            check_deadlock "$start_pid" "$waiting_for" "${visited[@]}" "$waiting_for"
            return $?
        fi
    fi
    
    return 1  # No deadlock found
}

# Cleanup function
cleanup() {
    local exit_code=$?
    
    # Stop memory monitor if running
    if [ -n "${MONITOR_PID:-}" ]; then
        kill $MONITOR_PID 2>/dev/null || true
    fi
    
    # Clear our dependencies
    clear_dependencies
    
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
        fi
    fi
    
    log INFO "Sequential executor exiting with code: $exit_code"
    echo "Log saved to: $EXEC_LOG" >&2
    
    exit $exit_code
}

trap cleanup EXIT INT TERM

# Main execution
log INFO "Starting sequential executor v2 for: $*"
log INFO "Project: $PROJECT_ROOT"
log INFO "Max lock wait: ${MAX_LOCK_WAIT}s"

# Add to queue
echo "$$:$(date '+%s'):$*" >> "$QUEUE_FILE"
log INFO "Added to queue (PID $$)"

# Try to acquire lock with timeout
WAIT_START=$(date +%s)
WAIT_COUNT=0

while true; do
    # Try to acquire lock
    if mkdir "$LOCKFILE" 2>/dev/null; then
        echo $$ > "$CURRENT_PID_FILE"
        clear_dependencies  # We're not waiting for anyone
        log INFO "Lock acquired"
        break
    fi
    
    # Check timeout
    ELAPSED=$(($(date +%s) - WAIT_START))
    if [ $ELAPSED -gt $MAX_LOCK_WAIT ]; then
        log ERROR "Timeout waiting for lock after ${MAX_LOCK_WAIT}s"
        exit 124  # Timeout exit code
    fi
    
    # Get current lock holder
    HOLDER_PID=$(cat "$CURRENT_PID_FILE" 2>/dev/null || echo 0)
    
    if [ "$HOLDER_PID" -gt 0 ]; then
        # Check if holder is alive
        if kill -0 "$HOLDER_PID" 2>/dev/null; then
            # Record that we're waiting for this holder
            record_dependency $$ "$HOLDER_PID"
            
            # Periodic deadlock check
            if [ $((WAIT_COUNT % DEADLOCK_CHECK_INTERVAL)) -eq 0 ] && [ $WAIT_COUNT -gt 0 ]; then
                log DEBUG "Checking for deadlocks..."
                
                # Use a lock to ensure only one process checks at a time
                if mkdir "$DEADLOCK_CHECK_FILE" 2>/dev/null; then
                    if check_deadlock $$ $$; then
                        log ERROR "Breaking deadlock by failing this request"
                        rmdir "$DEADLOCK_CHECK_FILE" 2>/dev/null || true
                        exit 125  # Special deadlock exit code
                    fi
                    rmdir "$DEADLOCK_CHECK_FILE" 2>/dev/null || true
                fi
            fi
            
            # Log status periodically
            if [ $((WAIT_COUNT % 30)) -eq 0 ]; then
                local cmd=$(ps -p "$HOLDER_PID" -o args= 2>/dev/null | head -1 || echo "unknown")
                log INFO "Waiting for lock held by PID $HOLDER_PID: $cmd (${ELAPSED}s elapsed)"
            fi
        else
            # Holder is dead, clean up
            log WARN "Lock holder (PID $HOLDER_PID) is dead, cleaning up"
            clear_dependencies
            rm -f "$CURRENT_PID_FILE"
            rmdir "$LOCKFILE" 2>/dev/null || true
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

# Set lock timeout alarm
(
    sleep $LOCK_TIMEOUT
    if [ -f "$CURRENT_PID_FILE" ]; then
        current=$(cat "$CURRENT_PID_FILE" 2>/dev/null || echo 0)
        if [ "$current" -eq "$$" ]; then
            log ERROR "Lock timeout after ${LOCK_TIMEOUT}s - forcibly releasing"
            kill -TERM $$ 2>/dev/null || true
        fi
    fi
) &
TIMEOUT_PID=$!

# Execute through wait_all.sh if available
if [ -x "${SCRIPT_DIR}/wait_all.sh" ]; then
    "${SCRIPT_DIR}/wait_all.sh" --timeout "${TIMEOUT:-1800}" -- "$@"
    EXIT_CODE=$?
else
    "$@"
    EXIT_CODE=$?
fi

# Kill timeout monitor
kill $TIMEOUT_PID 2>/dev/null || true

log INFO "Command completed with exit code: $EXIT_CODE"
exit $EXIT_CODE