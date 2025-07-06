#!/usr/bin/env bash
# sequential_wrapper.sh - Wrapper for pre-commit hooks to ensure ALL processes go through the queue
# Version: 3.0.0
#
# This script ensures that even the wrapper process itself goes through the sequential queue
#
set -euo pipefail

VERSION='3.0.0'
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Display help message
show_help() {
    cat << 'EOF'
sequential_wrapper.sh v3.0.0 - Sequential wrapper for pre-commit hooks

USAGE:
    sequential_wrapper.sh COMMAND [OPTIONS] -- FILES...
    sequential_wrapper.sh --help

DESCRIPTION:
    Wraps commands that need to process multiple files one at a time.
    Ensures each file is processed through the sequential queue.

EXAMPLES:
    sequential_wrapper.sh ruff format --line-length=320 -- file1.py file2.py
    sequential_wrapper.sh ruff check --fix -- src/*.py

EOF
    exit 0
}

# Check for help
if [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "-h" ]]; then
    show_help
fi

# Parse command and options
COMMAND=""
OPTIONS=()
FILES=()
PARSING_FILES=0

for arg in "$@"; do
    if [[ "$arg" == "--" ]]; then
        PARSING_FILES=1
    elif [[ $PARSING_FILES -eq 0 ]]; then
        if [[ -z "$COMMAND" ]]; then
            COMMAND="$arg"
        else
            OPTIONS+=("$arg")
        fi
    else
        FILES+=("$arg")
    fi
done

# Ensure we have a command and files
if [[ -z "$COMMAND" ]] || [[ ${#FILES[@]} -eq 0 ]]; then
    echo "Error: Command and files required" >&2
    echo "Usage: $0 COMMAND [OPTIONS] -- FILES..." >&2
    exit 1
fi

# Process each file through the sequential queue
EXIT_CODE=0
for file in "${FILES[@]}"; do
    if ! "$SCRIPT_DIR/sequential_queue.sh" --timeout 3600 -- "$COMMAND" "${OPTIONS[@]}" "$file"; then
        EXIT_CODE=1
    fi
done

exit $EXIT_CODE
