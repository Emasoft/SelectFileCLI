#!/usr/bin/env bash
# sep_common.sh - Common functions and definitions for SEP scripts
# Version: 8.6.0
#
# This file contains shared code used by multiple SEP (Sequential Execution Pipeline) scripts
# to reduce duplication and improve maintainability.
#
# CHANGELOG:
# v8.6.0:
# - Version bump for consistency across all SEP scripts
# - No functional changes from v8.5.0
#
# Usage: source "${SCRIPT_DIR}/sep_common.sh"
#

# Version
readonly SEP_COMMON_VERSION='8.6.0'

# Color definitions
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m'  # No Color

# Get project root directory
get_project_root() {
    if command -v git >/dev/null 2>&1 && git rev-parse --show-toplevel >/dev/null 2>&1; then
        git rev-parse --show-toplevel
    else
        # Fallback to script's parent directory
        cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd
    fi
}

# Source .env.development file if it exists
source_env_development() {
    local project_root="${1:-$(get_project_root)}"
    if [ -f "${project_root}/.env.development" ]; then
        set -a  # Export all variables
        # shellcheck source=/dev/null
        source "${project_root}/.env.development"
        set +a
    fi
}

# Log functions with colors
log_info() {
    echo -e "${GREEN}[INFO]${NC} $*" >&2
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $*" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

log_success() {
    echo -e "${GREEN}✓${NC} $*" >&2
}

log_fail() {
    echo -e "${RED}✗${NC} $*" >&2
}

# Alias for backward compatibility
log_warn() {
    log_warning "$@"
}

# Check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Get all descendant PIDs of a given process
get_descendants() {
    local parent_pid=$1
    local children=""

    if command_exists pgrep; then
        children=$(pgrep -P "$parent_pid" 2>/dev/null || true)
    else
        # Fallback for systems without pgrep
        children=$(ps --ppid "$parent_pid" -o pid= 2>/dev/null || true)
    fi

    for child in $children; do
        echo "$child"
        # Recursively get descendants
        get_descendants "$child"
    done
}

# Kill a process tree (all descendants)
kill_process_tree() {
    local pid=$1
    local signal=${2:-TERM}

    # Get all descendants
    local descendants=$(get_descendants "$pid")
    local all_pids="$pid $descendants"

    # Kill in reverse order (children first)
    for p in $(echo "$all_pids" | tr ' ' '\n' | tac 2>/dev/null || tail -r); do
        if kill -0 "$p" 2>/dev/null; then
            kill "-$signal" "$p" 2>/dev/null || true
        fi
    done
}

# Create a lock directory with PID file
create_lock_dir() {
    local lock_dir="$1"
    local pid="${2:-$$}"

    if mkdir -p "$lock_dir" 2>/dev/null; then
        echo "$pid" > "$lock_dir/pid"
        return 0
    else
        return 1
    fi
}

# Remove a lock directory
remove_lock_dir() {
    local lock_dir="$1"
    rm -rf "$lock_dir" 2>/dev/null || true
}

# Check if a lock is stale (process no longer exists)
is_lock_stale() {
    local lock_dir="$1"

    if [[ ! -d "$lock_dir" ]]; then
        return 1  # No lock exists
    fi

    if [[ -f "$lock_dir/pid" ]]; then
        local pid=$(cat "$lock_dir/pid" 2>/dev/null || echo "0")
        if [[ "$pid" -gt 0 ]] && kill -0 "$pid" 2>/dev/null; then
            return 1  # Process still alive, not stale
        fi
    fi

    return 0  # Lock is stale
}

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

# Initialize common variables
init_sep_common() {
    # Set PROJECT_ROOT if not already set
    : "${PROJECT_ROOT:=$(get_project_root)}"
    export PROJECT_ROOT

    # Source environment variables
    source_env_development "$PROJECT_ROOT"

    # Set common directories
    : "${LOGS_DIR:=${PROJECT_ROOT}/logs}"
    : "${SEQUENTIAL_LOCK_BASE_DIR:=${PROJECT_ROOT}/.sequential-locks}"

    # Create directories if they don't exist
    mkdir -p "$LOGS_DIR" "$SEQUENTIAL_LOCK_BASE_DIR" 2>/dev/null || true
}

# Validate integer
is_integer() {
    [[ ${1:-x} =~ ^[0-9]+$ ]]
}

# Portable sleep that handles fractional seconds
sleep_short() {
    local duration=$1

    # Try regular sleep first
    if sleep "$duration" 2>/dev/null; then
        return
    fi

    # Fallback to perl for fractional sleep
    if command_exists perl; then
        perl -e "select undef, undef, undef, $duration" 2>/dev/null || sleep 1
    else
        # Last resort: sleep for 1 second
        sleep 1
    fi
}

# Check if running in a virtual environment
in_virtual_env() {
    [[ -n "${VIRTUAL_ENV:-}" ]] || [[ -n "${CONDA_PREFIX:-}" ]]
}

# Reverse lines (portable alternative to tac)
reverse_lines() {
    if command_exists tac; then
        tac
    elif command_exists tail; then
        tail -r
    else
        # Fallback using awk
        awk '{a[i++]=$0} END {for (j=i-1; j>=0;) print a[j--]}'
    fi
}

# Export common version for scripts to verify
export SEP_COMMON_VERSION
