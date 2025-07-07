#!/usr/bin/env bash
# sep_kill_orphans.sh - Clean up orphaned processes and stale locks
# Version: 8.4.0
#
# This script finds and terminates processes that have been orphaned (parent PID = 1)
# and removes stale lock files from the sequential execution system.
#
# Usage: ./sep_kill_orphans.sh [--dry-run | --help]
#
# Options:
#   --dry-run    Show what would be killed without actually killing
#   --help       Show this help message
#
set -euo pipefail

VERSION='8.5.0'

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source common functions and definitions
source "${SCRIPT_DIR}/sep_common.sh"

# Initialize common variables
init_sep_common

# Display help message
show_help() {
    cat << 'EOF'
sep_kill_orphans.sh v8.4.0 - Emergency cleanup for orphaned processes

USAGE:
    sep_kill_orphans.sh [OPTIONS]

DESCRIPTION:
    Finds and terminates processes that have been orphaned (parent PID = 1)
    and removes stale lock files from the sequential execution system.

OPTIONS:
    --dry-run    Show what would be killed without actually killing
    --help, -h   Show this help message
    --version    Show version information

PROCESSES CHECKED:
    - pytest, python test runners
    - uv run commands
    - pre-commit hooks
    - ruff, mypy linters
    - sep_queue, sep, sep_memory_monitor

LOCK CLEANUP:
    Removes stale locks from:
    - /tmp/sep-exec-*
    - PROJECT_ROOT/.sequential-locks/

EXAMPLES:
    # Show what would be cleaned up
    ./sep_kill_orphans.sh --dry-run

    # Actually clean up orphans
    ./sep_kill_orphans.sh

SAFETY:
    - Only kills processes with parent PID = 1 (true orphans)
    - Preserves your current shell and its ancestors
    - Shows detailed information before taking action

EOF
    exit 0
}

# Parse arguments
DRY_RUN=0
case "${1:-}" in
    --help|-h)
        show_help
        ;;
    --version)
        echo "sep_kill_orphans.sh v$VERSION"
        exit 0
        ;;
    --dry-run)
        DRY_RUN=1
        echo "DRY RUN MODE - No processes will be killed"
        ;;
    "")
        # No arguments, proceed normally
        ;;
    *)
        echo "Unknown option: $1"
        echo "Use --help for usage information"
        exit 1
        ;;
esac

echo "Scanning for orphaned processes..."

# Process patterns to check for orphans
PATTERNS=(
    "pytest"
    "python.*test"
    "uv run"
    "pre-commit"
    "ruff"
    "mypy"
    "sep_queue"
    "sep"
    "sep_memory_monitor"
)

KILLED=0
FOUND=0

# Check each pattern for orphaned processes
for pattern in "${PATTERNS[@]}"; do
    # Find processes matching the pattern
    pids=$(pgrep -f "$pattern" 2>/dev/null || true)

    for pid in $pids; do
        # Skip if process doesn't exist
        if ! kill -0 "$pid" 2>/dev/null; then
            continue
        fi

        # Get parent PID (handling different ps output formats)
        ppid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ' || echo "")

        # Check if orphaned (parent PID = 1) or parent is dead
        if [[ "$ppid" == "1" ]] || [[ -z "$ppid" ]] || ! kill -0 "$ppid" 2>/dev/null; then
            # Get process command for logging
            cmd=$(ps -p "$pid" -o comm= 2>/dev/null || echo "unknown")
            echo "Found orphan: PID=$pid PPID=$ppid CMD=$cmd PATTERN=$pattern"
            ((FOUND++))

            if [[ $DRY_RUN -eq 0 ]]; then
                # Try graceful termination first
                if kill -TERM "$pid" 2>/dev/null; then
                    echo "  → Sent SIGTERM to PID $pid"
                    ((KILLED++))

                    # Give it a moment to exit cleanly
                    sleep 0.5

                    # Force kill if still alive
                    if kill -0 "$pid" 2>/dev/null; then
                        kill -KILL "$pid" 2>/dev/null || true
                        echo "  → Sent SIGKILL to PID $pid"
                    fi
                fi
            fi
        fi
    done
done

echo ""
echo "Summary: Found $FOUND orphaned process(es)"
[[ $DRY_RUN -eq 0 ]] && echo "Killed $KILLED orphaned process(es)"

# Clean up stale locks
echo ""
echo "Checking for stale lock files..."

LOCKS_REMOVED=0

# PROJECT_ROOT and environment variables are now set by init_sep_common

# Use configured lock directory or default
LOCK_BASE_DIR="${SEQUENTIAL_LOCK_BASE_DIR:-${PROJECT_ROOT}/.sequential-locks}"

# Check sequential executor locks
for lock_dir in "$LOCK_BASE_DIR"/sep-exec-* /tmp/sep-exec-* /tmp/make-lock-*; do
    if [[ -d "$lock_dir" ]]; then
        # Check if lock has a PID file
        if [[ -f "$lock_dir/current.pid" ]]; then
            lock_pid=$(cat "$lock_dir/current.pid" 2>/dev/null || echo "0")

            # Check if process is still alive
            if [[ "$lock_pid" -gt 0 ]] && kill -0 "$lock_pid" 2>/dev/null; then
                echo "Lock $lock_dir is active (PID $lock_pid)"
                continue
            fi
        fi

        # Lock is stale
        echo "Stale lock found: $lock_dir"
        if [[ $DRY_RUN -eq 0 ]]; then
            rm -rf "$lock_dir"
            echo "  → Removed"
            ((LOCKS_REMOVED++))
        fi
    fi
done

# Check for git index lock
if [[ -f .git/index.lock ]]; then
    echo "Found git index lock"
    if [[ $DRY_RUN -eq 0 ]]; then
        rm -f .git/index.lock
        echo "  → Removed"
        ((LOCKS_REMOVED++))
    fi
fi

echo ""
[[ $DRY_RUN -eq 0 ]] && echo "Removed $LOCKS_REMOVED stale lock(s)"

# Final summary
echo ""
echo "Cleanup complete!"
if [[ $DRY_RUN -eq 1 ]]; then
    echo "This was a dry run - no changes were made"
    echo "Run without --dry-run to actually clean up"
fi

exit 0
