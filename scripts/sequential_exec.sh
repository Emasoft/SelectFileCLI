#!/usr/bin/env bash
# sequential_exec.sh - Execute commands immediately with sequential safety
# This is for pre-commit hooks and other situations that need immediate execution
#
# Usage: sequential_exec.sh [OPTIONS] -- COMMAND [ARGS...]
#

set -euo pipefail

# Default timeout
TIMEOUT=300

# Parse options
while [[ $# -gt 0 ]]; do
    case $1 in
        --timeout)
            TIMEOUT="$2"
            shift 2
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

# Execute the command directly with timeout
if command -v timeout >/dev/null 2>&1; then
    # GNU timeout
    timeout "$TIMEOUT" "$@"
else
    # No timeout command, just execute
    "$@"
fi