#!/usr/bin/env bash
# sep_memory_monitor.sh - Monitor and kill processes exceeding memory limits
# Version: 8.4.0
#
# This script monitors all child processes of the sequential executor
# and kills any that exceed the memory limit to prevent system lockup
#
set -euo pipefail

VERSION='8.4.0'

# Reverses the order of lines (cross-platform alternative to tac)
reverse_lines() {
    awk '{a[i++]=$0} END {for (j=i-1; j>=0;) print a[j--]}'
}

# Configuration
MEMORY_LIMIT_MB=${MEMORY_LIMIT_MB:-2048}  # 2GB default
CHECK_INTERVAL=${CHECK_INTERVAL:-5}       # Check every 5 seconds
MONITOR_PID_FILE="/tmp/sep_memory_monitor_$$.pid"

# Get project root
PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

# LOG_FILE will be set after argument parsing

# Colors
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m'

# Log functions - write to both stdout/stderr and log file
log_info() {
    local msg
    msg="[MEMORY-MONITOR] $(date '+%Y-%m-%d %H:%M:%S') - $*"
    echo -e "${GREEN}${msg}${NC}"
    [[ -n "${LOG_FILE:-}" ]] && echo "${msg}" >> "$LOG_FILE"
}

log_warn() {
    local msg
    msg="[MEMORY-MONITOR] $(date '+%Y-%m-%d %H:%M:%S') - $*"
    echo -e "${YELLOW}${msg}${NC}" >&2
    [[ -n "${LOG_FILE:-}" ]] && echo "WARNING: ${msg}" >> "$LOG_FILE"
}

log_error() {
    local msg
    msg="[MEMORY-MONITOR] $(date '+%Y-%m-%d %H:%M:%S') - $*"
    echo -e "${RED}${msg}${NC}" >&2
    [[ -n "${LOG_FILE:-}" ]] && echo "ERROR: ${msg}" >> "$LOG_FILE"
}

# Cleanup on exit
cleanup() {
    rm -f "$MONITOR_PID_FILE"
    if [[ -n "${LOG_FILE:-}" ]]; then
        log_info "Memory monitor stopped"
        echo "Log saved to: $LOG_FILE" >&2
    fi
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
    local all_pids
    all_pids="$pid $(get_descendants "$pid")"

    # Kill in reverse order (children first)
    for p in $(echo "$all_pids" | tr ' ' '\n' | reverse_lines); do
        if kill -0 "$p" 2>/dev/null; then
            log_warn "  Killing PID $p ($(ps -p "$p" -o comm= 2>/dev/null || echo 'unknown'))"
            kill -TERM "$p" 2>/dev/null || true
        fi
    done

    # Give processes time to terminate
    sleep 2

    # Force kill any remaining
    for p in $(echo "$all_pids" | tr ' ' '\n' | reverse_lines); do
        if kill -0 "$p" 2>/dev/null; then
            log_error "  Force killing PID $p"
            kill -KILL "$p" 2>/dev/null || true
        fi
    done
}

# Main monitoring loop
monitor_processes() {
    local parent_pid=${1:-$$}

    # Create log file now that we have LOGS_DIR
    LOG_FILE="${LOGS_DIR}/sep_memory_monitor_$(date '+%Y%m%d_%H%M%S')_$$.log"

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

# Display help message
show_help() {
    cat << EOF
sep_memory_monitor.sh v$VERSION - Process memory monitoring and enforcement
====================================================================

 USAGE
   ./sep_memory_monitor.sh [OPTIONS]

DESCRIPTION:
    Monitors process memory usage and kills processes that exceed specified limits.
    Designed to work with sep_queue.sh to prevent memory explosions.

OPTIONS:
    --pid PID           Process ID to monitor (default: parent process)
    --limit MB          Memory limit in megabytes (default: 2048)
    --interval SECONDS  Check interval in seconds (default: 5)
    --log-dir PATH      Custom log directory (default: PROJECT_ROOT/logs)
    --help              Show this help message
    --version           Show version information

EXAMPLES:
    # Monitor current shell with 2GB limit
    $0

    # Monitor specific process with 4GB limit
    $0 --pid 12345 --limit 4096

    # Fast monitoring (check every second)
    $0 --interval 1

    # Monitor a long-running process
    $0 --pid \$\$ --limit 8192 --interval 10

    # Use custom log directory
    $0 --log-dir /tmp/mylogs --pid 12345

FEATURES:
    - Monitors process and all its descendants
    - Kills process trees that exceed memory limit
    - Logs all actions with timestamps
    - Cross-platform (Linux/macOS/BSD)
    - Graceful termination (SIGTERM then SIGKILL)

LOG FILES:
    Logs are saved to: PROJECT_ROOT/logs/memory_monitor_*.log

ENVIRONMENT VARIABLES:
    MEMORY_LIMIT_MB    Default memory limit (overridden by --limit)
    CHECK_INTERVAL     Default check interval (overridden by --interval)

EOF
    exit 0
}

# Parse arguments
PARENT_PID=""
CUSTOM_LOG_DIR=""
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
        --log-dir)
            CUSTOM_LOG_DIR="$2"
            shift 2
            ;;
        --help|-h)
            show_help
            ;;
        --version)
            echo "sep_memory_monitor.sh v$VERSION"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--pid PID] [--limit MB] [--interval SECONDS] [--log-dir PATH]"
            echo "Run '$0 --help' for detailed information"
            exit 1
            ;;
    esac
done

# Create logs directory
if [[ -n "$CUSTOM_LOG_DIR" ]]; then
    LOGS_DIR="$CUSTOM_LOG_DIR"
else
    LOGS_DIR="${LOG_DIR:-${PROJECT_ROOT}/logs}"
fi
mkdir -p "$LOGS_DIR"

# Start monitoring
if [[ -n "$PARENT_PID" ]]; then
    monitor_processes "$PARENT_PID"
else
    # Monitor our parent process
    monitor_processes "$PPID"
fi
