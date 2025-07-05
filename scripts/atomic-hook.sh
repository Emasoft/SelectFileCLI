#!/usr/bin/env bash
# atomic-hook.sh - Execute pre-commit hooks atomically
#
# This script ensures each file is processed individually through wait_all.sh,
# implementing the atomic command principle for the sequential pipeline.
#
# Usage: ./atomic-hook.sh <command> [files...]
# Example: ./atomic-hook.sh "ruff format" file1.py file2.py
#
set -euo pipefail

# Get the command to execute
if [ $# -lt 1 ]; then
    echo "Usage: $0 <command> [files...]" >&2
    exit 1
fi

COMMAND=$1
shift

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WAIT_ALL="${SCRIPT_DIR}/wait_all.sh"

# Verify wait_all.sh exists
if [ ! -x "$WAIT_ALL" ]; then
    echo "ERROR: wait_all.sh not found at: $WAIT_ALL" >&2
    exit 1
fi

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Track failures
FAILED=0
PROCESSED=0

# Process each file atomically
for file in "$@"; do
    ((PROCESSED++))
    echo -e "${YELLOW}[ATOMIC]${NC} Processing: $file"

    # Execute command atomically with timeout
    if "$WAIT_ALL" --timeout 60 -- $COMMAND "$file"; then
        echo -e "${GREEN}[ATOMIC]${NC} ✓ Success: $file"
    else
        echo -e "${RED}[ATOMIC]${NC} ✗ Failed: $file" >&2
        ((FAILED++))
    fi
done

# Summary
echo -e "\n${YELLOW}[ATOMIC]${NC} Processed $PROCESSED files, $FAILED failures"

# Exit with error if any file failed
if [ $FAILED -gt 0 ]; then
    exit 1
fi

exit 0
