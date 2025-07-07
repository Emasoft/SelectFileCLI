#!/usr/bin/env bash
# test_intelligent_snapshot_demo.sh - Demo of intelligent snapshot detection
#
# This script demonstrates how the atomifier intelligently applies --snapshot-update
# only to tests that actually use snapshot comparisons
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== INTELLIGENT SNAPSHOT DETECTION DEMO ==="
echo ""
echo "This demo shows how --snapshot-update is only applied to tests that use snapshots"
echo ""

# Step 1: Detect snapshot tests
echo "1. Detecting which tests use snapshot comparisons:"
echo "   Running: python3 detect_snapshot_tests.py tests/test_file_browser_app.py"
echo ""

if [[ -x "${SCRIPT_DIR}/detect_snapshot_tests.py" ]]; then
    python3 "${SCRIPT_DIR}/detect_snapshot_tests.py" tests/test_file_browser_app.py 2>/dev/null | \
    python3 -c "
import sys, json
data = json.load(sys.stdin)
print(f'   Total tests: {len(data[\"all_tests\"])}')
print(f'   Snapshot tests: {len(data[\"snapshot_tests\"])}')
print()
print('   Snapshot tests detected:')
for t in data['snapshot_tests'][:5]:
    print(f'     - {t}')
if len(data['snapshot_tests']) > 5:
    print(f'     ... and {len(data[\"snapshot_tests\"]) - 5} more')
"
fi

echo ""
echo "2. Atomifying with --snapshot-update flag:"
echo "   Command: pytest --snapshot-update tests/test_file_browser_app.py"
echo ""

# Count different types of commands
snapshot_count=$(bash "${SCRIPT_DIR}/tool_atomifier.sh" pytest --snapshot-update tests/test_file_browser_app.py 2>&1 | grep -c "snapshot-update" || echo "0")
regular_count=$(bash "${SCRIPT_DIR}/tool_atomifier.sh" pytest --snapshot-update tests/test_file_browser_app.py 2>&1 | grep -v "snapshot-update" | grep -c "ATOMIC:" || echo "0")

echo "   Results:"
echo "   - Commands WITH --snapshot-update: $snapshot_count (only snapshot tests, batched in pairs)"
echo "   - Commands WITHOUT --snapshot-update: $regular_count (regular tests, run individually)"
echo ""

echo "3. Example commands generated:"
echo ""
echo "   Snapshot tests (batched with --snapshot-update):"
bash "${SCRIPT_DIR}/tool_atomifier.sh" pytest --snapshot-update tests/test_file_browser_app.py 2>&1 | grep "snapshot-update" | head -2 | sed 's/^/     /'
echo ""
echo "   Regular tests (individual, no --snapshot-update):"
bash "${SCRIPT_DIR}/tool_atomifier.sh" pytest --snapshot-update tests/test_file_browser_app.py 2>&1 | grep -v "snapshot-update" | grep "ATOMIC:" | head -3 | sed 's/^/     /'

echo ""
echo "4. Benefits of intelligent snapshot detection:"
echo "   ✓ Only tests that use snapshots get --snapshot-update flag"
echo "   ✓ Prevents unnecessary snapshot file writes for regular tests"
echo "   ✓ Snapshot tests are batched to reduce overhead"
echo "   ✓ Regular tests run individually for better isolation"
echo "   ✓ Memory usage is optimized by batching snapshot operations"

echo ""
echo "5. Using the snapshot-aware test runner:"
echo "   ./run_test_with_snapshot_detection.sh tests/test_app.py::test_snapshot"
echo ""
echo "   This script will:"
echo "   - Detect if the test uses snapshots"
echo "   - Run the test normally first"
echo "   - If it fails due to snapshot mismatch, automatically retry with --snapshot-update"
echo "   - But only if the test actually uses snapshot comparisons!"

echo ""
echo "=== END OF DEMO ==="
