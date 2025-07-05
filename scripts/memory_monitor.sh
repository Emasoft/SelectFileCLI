#!/usr/bin/env bash
# memory_monitor.sh - Monitor and kill processes exceeding memory limits
#
# This script monitors all child processes of the sequential executor
# and kills any that exceed the memory limit to prevent system lockup
#
set -euo pipefail

# Configuration
MEMORY_LIMIT_MB=${MEMORY_LIMIT_MB:-2048}  # 2GB default
CHECK_INTERVAL=${CHECK_INTERVAL:-5}       # Check every 5 seconds
MONITOR_PID_FILE="/tmp/memory_monitor_$$.pid"

# Get project root and create logs directory
PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
LOGS_DIR="${PROJECT_ROOT}/logs"
mkdir -p "$LOGS_DIR"

# Create timestamped log file
LOG_FILE="${LOGS_DIR}/memory_monitor_$(date '+%Y%m%d_%H%M%S')_$$.log"

# Colors
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m'

# Log functions - write to both stdout/stderr and log file
log_info() {
    local msg="[MEMORY-MONITOR] $(date '+%Y-%m-%d %H:%M:%S') - $*"
    echo -e "${GREEN}${msg}${NC}"
    echo "${msg}" >> "$LOG_FILE"
}

log_warn() {
    local msg="[MEMORY-MONITOR] $(date '+%Y-%m-%d %H:%M:%S') - $*"
    echo -e "${YELLOW}${msg}${NC}" >&2
    echo "WARNING: ${msg}" >> "$LOG_FILE"
}

log_error() {
    local msg="[MEMORY-MONITOR] $(date '+%Y-%m-%d %H:%M:%S') - $*"
    echo -e "${RED}${msg}${NC}" >&2
    echo "ERROR: ${msg}" >> "$LOG_FILE"
}

# Cleanup on exit
cleanup() {
    rm -f "$MONITOR_PID_FILE"
    log_info "Memory monitor stopped"
    echo "Log saved to: $LOG_FILE" >&2
}
trap cleanup EXIT

# Write our PID
echo $$ > "$MONITOR_PID_FILE"

# Get memory usage in MB for a process
get_memory_mb() {
    local pid=$1
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS: ps reports RSS in KB
        ps -p "$pid" -o rss= 2>/dev/null | awk '{print int($1/1024)}' || echo 0
    else
        # Linux: ps reports RSS in KB
        ps -p "$pid" -o rss= 2>/dev/null | awk '{print int($1/1024)}' || echo 0
    fi
}

# Get all descendant PIDs of a process
get_descendants() {
    local parent_pid=$1
    local children=""

    if command -v pgrep >/dev/null 2>&1; then
        children=$(pgrep -P "$parent_pid" 2>/dev/null || true)
    else
        children=$(ps --ppid "$parent_pid" -o pid= 2>/dev/null || true)
    fi

    for child in $children; do
        echo "$child"
        get_descendants "$child"
    done
}

# Kill process tree
kill_process_tree() {
    local pid=$1
    local reason=$2

    log_warn "Killing process tree for PID $pid: $reason"

    # Get all descendants
    local all_pids="$pid $(get_descendants "$pid")"

    # Kill in reverse order (children first)
    for p in $(echo "$all_pids" | tr ' ' '\n' | tac); do
        if kill -0 "$p" 2>/dev/null; then
            log_warn "  Killing PID $p ($(ps -p "$p" -o comm= 2>/dev/null || echo 'unknown'))"
            kill -TERM "$p" 2>/dev/null || true
        fi
    done

    # Give processes time to terminate
    sleep 2

    # Force kill any remaining
    for p in $(echo "$all_pids" | tr ' ' '\n' | tac); do
        if kill -0 "$p" 2>/dev/null; then
            log_error "  Force killing PID $p"
            kill -KILL "$p" 2>/dev/null || true
        fi
    done
}

# Main monitoring loop
monitor_processes() {
    local parent_pid=${1:-$$}
    log_info "Starting memory monitor for PID $parent_pid (limit: ${MEMORY_LIMIT_MB}MB)"
    log_info "Project: $PROJECT_ROOT"
    log_info "Log file: $LOG_FILE"
    
    # Log initial process tree
    log_info "Initial process tree:"
    local all_pids="$parent_pid $(get_descendants "$parent_pid")"
    for pid in $all_pids; do
        if kill -0 "$pid" 2>/dev/null; then
            local cmd=$(ps -p "$pid" -o comm= 2>/dev/null || echo "unknown")
            local mem_mb=$(get_memory_mb "$pid")
            log_info "  PID $pid: $cmd (${mem_mb}MB)"
        fi
    done
    
    local check_count=0
    while kill -0 "$parent_pid" 2>/dev/null; do
        ((check_count++))
        
        # Get parent and all child processes
        local all_pids="$parent_pid $(get_descendants "$parent_pid")"
        local total_mem=0
        local process_count=0
        
        # Log periodic status every 10 checks
        if (( check_count % 10 == 0 )); then
            log_info "Status check #$check_count:"
        fi
        
        for pid in $all_pids; do
            if kill -0 "$pid" 2>/dev/null; then
                local mem_mb=$(get_memory_mb "$pid")
                local cmd=$(ps -p "$pid" -o comm= 2>/dev/null || echo "unknown")
                ((total_mem += mem_mb))
                ((process_count++))
                
                # Always log to file, but only to console if high usage
                echo "  PID $pid: $cmd = ${mem_mb}MB" >> "$LOG_FILE"
                
                # Log high memory usage to console
                if (( mem_mb > MEMORY_LIMIT_MB / 2 )); then
                    log_warn "High memory usage: PID $pid ($cmd) using ${mem_mb}MB"
                fi
                
                # Kill if over limit
                if (( mem_mb > MEMORY_LIMIT_MB )); then
                    kill_process_tree "$pid" "Memory limit exceeded: ${mem_mb}MB > ${MEMORY_LIMIT_MB}MB"
                fi
            fi
        done
        
        # Log summary every 10 checks
        if (( check_count % 10 == 0 )); then
            log_info "Total: $process_count processes using ${total_mem}MB"
        fi
        
        sleep "$CHECK_INTERVAL"
    done
    
    log_info "Parent process $parent_pid terminated, monitor exiting"
}

# Parse arguments
PARENT_PID=""
while [[ $# -gt 0 ]]; do
    case $1 in
        --pid)
            PARENT_PID="$2"
            shift 2
            ;;
        --limit)
            MEMORY_LIMIT_MB="$2"
            shift 2
            ;;
        --interval)
            CHECK_INTERVAL="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--pid PID] [--limit MB] [--interval SECONDS]"
            exit 1
            ;;
    esac
done

# Start monitoring
if [[ -n "$PARENT_PID" ]]; then
    monitor_processes "$PARENT_PID"
else
    # Monitor our parent process
    monitor_processes "$PPID"
fi
