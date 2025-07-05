#!/usr/bin/env bash
# example-atomic-pipeline.sh - Example of atomic sequential pipeline
#
# This script demonstrates how to build a proper atomic sequential pipeline
# using wait_all.sh as the atomic building block.
#
set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WAIT_ALL="${SCRIPT_DIR}/wait_all.sh"

# Check if wait_all.sh exists
if [ ! -x "$WAIT_ALL" ]; then
    echo "ERROR: wait_all.sh not found at: $WAIT_ALL" >&2
    exit 1
fi

# Example Python files to process
PYTHON_FILES=(
    "src/main.py"
    "src/module1.py"
    "src/module2.py"
    "tests/test_main.py"
    "tests/test_module1.py"
)

echo "=== Atomic Sequential Pipeline Example ==="
echo "Each command runs in isolation with complete cleanup"
echo

# Step 1: Format each file atomically
echo "Step 1: Formatting files atomically..."
for file in "${PYTHON_FILES[@]}"; do
    if [ -f "$file" ]; then
        echo "  Formatting: $file"
        "$WAIT_ALL" --timeout 30 -- ruff format "$file"
    fi
done

# Step 2: Lint each file atomically
echo -e "\nStep 2: Linting files atomically..."
for file in "${PYTHON_FILES[@]}"; do
    if [ -f "$file" ]; then
        echo "  Linting: $file"
        "$WAIT_ALL" --timeout 60 -- ruff check --fix "$file"
    fi
done

# Step 3: Type check each file atomically
echo -e "\nStep 3: Type checking files atomically..."
for file in "${PYTHON_FILES[@]}"; do
    if [ -f "$file" ]; then
        echo "  Type checking: $file"
        "$WAIT_ALL" --timeout 120 -- mypy --strict "$file"
    fi
done

# Step 4: Run tests atomically
echo -e "\nStep 4: Running tests atomically..."
for file in tests/test_*.py; do
    if [ -f "$file" ]; then
        echo "  Testing: $file"
        "$WAIT_ALL" --timeout 300 -- pytest -v "$file"
    fi
done

# Step 5: Example of package operations (atomic)
echo -e "\nStep 5: Package operations atomically..."
# Install packages one by one
PACKAGES=("requests" "click" "rich")
for pkg in "${PACKAGES[@]}"; do
    echo "  Installing: $pkg"
    "$WAIT_ALL" --timeout 120 -- pip install "$pkg"
done

echo -e "\n=== Pipeline Complete ==="
echo "All operations executed atomically through wait_all.sh"
echo "Check ./logs/ for detailed execution logs"

# Example of WRONG approach (commented out):
# echo "DON'T DO THIS - Non-atomic batch operations:"
# "$WAIT_ALL" -- ruff format .                    # Formats ALL files at once
# "$WAIT_ALL" -- pytest                           # Runs ALL tests at once
# "$WAIT_ALL" -- pip install -r requirements.txt  # Installs ALL packages at once
