#!/usr/bin/env bash
# check_workflow_execution.sh - Quick check for workflows that queue but never execute
# Version: 1.0.0

set -uo pipefail

WORKFLOWS_DIR=".github/workflows"
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "Checking workflows for execution issues..."
echo

ISSUES_FOUND=0

for workflow in $WORKFLOWS_DIR/*.yml; do
    workflow_name=$(basename "$workflow")

    # Skip if file doesn't exist
    [[ -f "$workflow" ]] || continue

    # Check if workflow uses sep_queue.sh
    if grep -q "sep_queue.sh" "$workflow"; then
        # Check if it ever starts the queue
        if ! grep -q -- "--queue-start\|--start" "$workflow"; then
            echo -e "${RED}❌ $workflow_name${NC}: Uses sep_queue.sh but NEVER starts the queue!"
            echo "   Commands are queued but not executed - this workflow does nothing!"
            ((ISSUES_FOUND++))
        else
            echo -e "${GREEN}✓ $workflow_name${NC}: Properly starts SEP queue"
        fi
    else
        # Check if it runs any actual commands
        if grep -qE "uv run|pytest|ruff|mypy|npm|yarn|pnpm" "$workflow"; then
            echo -e "${GREEN}✓ $workflow_name${NC}: Runs commands directly (no SEP)"
        fi
    fi
done

echo
if [[ $ISSUES_FOUND -gt 0 ]]; then
    echo -e "${RED}Found $ISSUES_FOUND workflows with execution issues!${NC}"
    echo
    echo "These workflows appear to pass but don't actually run any checks."
    echo "This is a CRITICAL security issue - broken code could be merged!"
    exit 1
else
    echo -e "${GREEN}All workflows properly execute their commands.${NC}"
fi
