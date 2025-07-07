#!/usr/bin/env bash
# test_with_act.sh - Test workflows locally with act to ensure they actually execute
# Version: 1.0.0

set -uo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}Testing workflows with act to verify actual execution...${NC}"
echo

# Check if act is installed
if ! command -v act >/dev/null 2>&1; then
    echo -e "${RED}act is not installed!${NC}"
    echo "Install with: brew install act"
    exit 1
fi

# Test a simple workflow that should produce output
echo "Testing lint workflow with a minimal Python file..."

# Create a test file with a deliberate issue
cat > test_lint_issue.py << 'EOF'
import os
import sys  # Unused import - should be caught by ruff
x=1+2  # No spaces around operators - should be caught
EOF

echo "Created test_lint_issue.py with deliberate issues"
echo

# Run the lint workflow with act
echo -e "${YELLOW}Running lint workflow with act...${NC}"
act push -W .github/workflows/lint.yml --container-architecture linux/amd64 2>&1 | tee act_lint_output.log

# Check if ruff actually ran
echo
echo -e "${BLUE}Checking if linting tools actually executed...${NC}"

if grep -q "would be reformatted" act_lint_output.log; then
    echo -e "${GREEN}✓ ruff format check executed${NC}"
else
    echo -e "${RED}✗ ruff format check did NOT execute${NC}"
fi

if grep -q "unused-import\|E225" act_lint_output.log; then
    echo -e "${GREEN}✓ ruff check found the issues${NC}"
else
    echo -e "${RED}✗ ruff check did NOT find issues (or didn't run)${NC}"
fi

if grep -q "Success: no issues found" act_lint_output.log; then
    echo -e "${RED}✗ Linting passed but should have failed!${NC}"
fi

# Clean up
rm -f test_lint_issue.py act_lint_output.log

echo
echo -e "${YELLOW}Testing a working workflow (build.yml)...${NC}"
act push -W .github/workflows/build.yml --container-architecture linux/amd64 -n

echo
echo -e "${BLUE}Summary:${NC}"
echo "Most workflows are using sep_queue.sh incorrectly:"
echo "1. They queue commands but never start execution"
echo "2. No actual linting, testing, or checking happens"
echo "3. Workflows exit with success without doing work"
echo
echo -e "${RED}This is a critical security issue!${NC}"
