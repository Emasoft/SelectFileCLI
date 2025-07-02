#!/usr/bin/env bash
set -euo pipefail

# Use project-local environment variables
MEMORY_LIMIT_MB="${MEMORY_LIMIT_MB:-2048}"
TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-600}"

if [ $# -lt 1 ]; then
    echo "Usage: $0 <command> [args...]"
    exit 1
fi

COMMAND="$1"
shift

# Platform-specific memory limiting
if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    ulimit -v $((MEMORY_LIMIT_MB * 1024)) 2>/dev/null || true
    ulimit -d $((MEMORY_LIMIT_MB * 1024)) 2>/dev/null || true
fi

# Global variable to store command PID
CMD_PID=""

# Cleanup on exit
cleanup() {
    # Kill the command process if it exists
    if [ -n "${CMD_PID:-}" ] && kill -0 "$CMD_PID" 2>/dev/null; then
        kill -TERM "$CMD_PID" 2>/dev/null || true
        sleep 0.5
        kill -KILL "$CMD_PID" 2>/dev/null || true
    fi
    if [[ "$COMMAND" == *"python"* ]] || [[ "$COMMAND" == *"uv"* ]]; then
        python3 -c "import gc; gc.collect()" 2>/dev/null || true
    fi
}
trap cleanup EXIT INT TERM

echo "Running (memory limited to ${MEMORY_LIMIT_MB}MB): $COMMAND $*"

# Execute with timeout - can't use exec because we need cleanup to run
if command -v timeout &> /dev/null; then
    timeout "$TIMEOUT_SECONDS" "$COMMAND" "$@" &
    CMD_PID=$!
    wait $CMD_PID
    exit_code=$?
elif command -v gtimeout &> /dev/null; then
    gtimeout "$TIMEOUT_SECONDS" "$COMMAND" "$@" &
    CMD_PID=$!
    wait $CMD_PID
    exit_code=$?
else
    "$COMMAND" "$@" &
    CMD_PID=$!
    wait $CMD_PID
    exit_code=$?
fi

exit $exit_code
