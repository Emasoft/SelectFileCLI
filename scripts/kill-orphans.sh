#!/usr/bin/env bash
# kill-orphans.sh - Clean up orphaned processes and stale locks
# 
# This script finds and terminates processes that have been orphaned (parent PID = 1)
# and removes stale lock files from the sequential execution system.
#
# Usage: ./kill-orphans.sh [--dry-run]
#
# Options:
#   --dry-run    Show what would be killed without actually killing

set -euo pipefail

# Parse arguments
DRY_RUN=0
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=1
    echo "DRY RUN MODE - No processes will be killed"
fi

echo "Scanning for orphaned processes..."

# Process patterns to check for orphans
PATTERNS=(
    "pytest"
    "python.*test"
    "uv run"
    "pre-commit"
    "ruff"
    "mypy"
    "sequential-executor"
    "wait_all"
    "memory_monitor"
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

# Check sequential executor locks
for lock_dir in /tmp/seq-exec-* /tmp/make-lock-*; do
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