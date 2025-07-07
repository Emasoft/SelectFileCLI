#!/usr/bin/env bash
# test_pytest_atomization_demo.sh - Demo script showing pytest atomization and result collection
#
# This script demonstrates how the sequential queue system atomizes pytest commands
# and collects test results
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== PYTEST ATOMIZATION DEMO ==="
echo ""
echo "This demo shows how pytest commands are atomized and results collected"
echo ""

# Step 1: Show atomization
echo "1. Atomizing pytest command for tests/test_file_browser_app.py"
echo "   Command: pytest tests/test_file_browser_app.py"
echo ""
echo "   Atomic commands generated:"
"$SCRIPT_DIR/../scripts/sep_tool_atomifier.sh" pytest tests/test_file_browser_app.py | head -5
echo "   ... (showing first 5 of many)"
echo ""

# Step 2: Show atomization with snapshot update
echo "2. Atomizing pytest with --snapshot-update (batches of 2)"
echo "   Command: pytest --snapshot-update tests/test_file_browser_app.py"
echo ""
echo "   Atomic commands generated:"
"$SCRIPT_DIR/../scripts/sep_tool_atomifier.sh" pytest --snapshot-update tests/test_file_browser_app.py | head -5
echo "   ... (notice tests are batched in pairs)"
echo ""

# Step 3: Show how to run atomized tests through sequential queue
echo "3. To run atomized tests through sequential queue:"
echo ""
echo "   # Add atomized pytest command to queue"
echo "   sep_queue.sh --atomify pytest tests/test_file_browser_app.py"
echo ""
echo "   # Start processing the queue"
echo "   sep_queue.sh --queue-start"
echo ""

# Step 4: Show how results are collected
echo "4. Test results are automatically collected:"
echo ""
echo "   - Job metadata stored in: ./logs/runs/run_*/jobs/*.txt"
echo "   - Pytest results in JSON: ./logs/runs/run_*/jobs/*_pytest_results.json"
echo "   - Summary stats added to job metadata (TESTS_PASSED, TESTS_FAILED, TESTS_TOTAL)"
echo ""

# Step 5: Show how to view aggregated results
echo "5. View aggregated test results:"
echo ""
echo "   # Show results from latest run"
echo "   aggregate_test_results.sh"
echo ""
echo "   # List all runs with pytest jobs"
echo "   aggregate_test_results.sh --list"
echo ""
echo "   # Show results from specific run"
echo "   aggregate_test_results.sh run_20240106_123456"
echo ""

echo "=== END OF DEMO ==="
echo ""
echo "Key benefits of atomization:"
echo "- Prevents memory explosions by running tests individually"
echo "- Provides better isolation between tests"
echo "- Enables parallel test execution (when queue runners support it)"
echo "- Detailed tracking of which specific tests fail"
echo "- Automatic result collection and aggregation"
