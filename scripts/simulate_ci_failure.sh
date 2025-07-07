#!/usr/bin/env bash
# simulate_ci_failure.sh - Demonstrate that CI would pass even with broken code
# Version: 1.0.0

set -uo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}Simulating what happens when broken code is pushed...${NC}"
echo

# Create a Python file with multiple issues
mkdir -p test_broken_code
cat > test_broken_code/broken.py << 'EOF'
# This file has multiple issues that should be caught

import os
import sys  # F401: unused import
import json
import requests  # Missing dependency

x=1+2  # E225: missing whitespace around operator
y    =     3  # E221, E222: multiple spaces

def broken_function(  ):  # E201, E202: whitespace issues
    print(  "hello"  )  # E201, E202
    undefined_variable  # NameError - should fail mypy
    return None

# Type annotation issues
def bad_types(x: int) -> str:
    return x  # Type error: returning int instead of str

# Missing docstring (D103)
class BadClass:
    pass

if __name__ == "__main__":
    broken_function()
EOF

echo "Created test_broken_code/broken.py with multiple issues:"
echo "- Unused imports (ruff should catch)"
echo "- Whitespace issues (ruff format should catch)"
echo "- Undefined variables (mypy should catch)"
echo "- Type errors (mypy should catch)"
echo "- Missing dependencies (deptry should catch)"
echo

# Simulate running the lint workflow commands
echo -e "${YELLOW}Simulating lint workflow execution...${NC}"

# This is what the workflow does - just queues and exits
echo "Running: ./scripts/sep_queue.sh -- uv run ruff check test_broken_code/"
./scripts/sep_queue.sh -- uv run ruff check test_broken_code/ 2>/dev/null
QUEUE_EXIT_CODE=$?

echo "Queue exit code: $QUEUE_EXIT_CODE"

if [[ $QUEUE_EXIT_CODE -eq 0 ]]; then
    echo -e "${RED}✗ Workflow would report SUCCESS despite broken code!${NC}"
else
    echo -e "${GREEN}✓ Workflow would fail${NC}"
fi

# Show what SHOULD happen if commands actually ran
echo
echo -e "${YELLOW}What SHOULD happen if commands actually executed:${NC}"

# Actually run the checks
echo
echo "Running ruff check directly:"
if command -v ruff >/dev/null 2>&1; then
    ruff check test_broken_code/broken.py || true
fi

echo
echo "Running mypy directly:"
if command -v mypy >/dev/null 2>&1; then
    mypy test_broken_code/broken.py || true
fi

# Clean up
rm -rf test_broken_code

echo
echo -e "${RED}CRITICAL: The CI pipeline is not protecting the codebase!${NC}"
echo "Broken code can be merged because checks aren't running."
