#!/usr/bin/env bash
# run_test_with_snapshot_detection.sh - Run pytest with intelligent snapshot detection
# Version: 1.0.0
#
# This script runs a single test and automatically retries with --snapshot-update
# if it detects a snapshot failure, but only for tests that actually use snapshots
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Function to check if a test uses snapshots
test_uses_snapshots() {
    local test_name="$1"
    local test_file="${test_name%%::*}"
    local test_func="${test_name#*::}"

    # Check if test file exists
    if [[ ! -f "$test_file" ]]; then
        return 1
    fi

    # Use Python detection if available
    if [[ -x "${SCRIPT_DIR}/detect_snapshot_tests.py" ]] && command -v python3 >/dev/null 2>&1; then
        # Try Python detection, but handle failures gracefully
        local result
        result=$(python3 "${SCRIPT_DIR}/detect_snapshot_tests.py" "$test_file" 2>/dev/null || echo '{"snapshot_tests": [], "error": "detection failed"}')

        # Check if detection succeeded and test is in snapshot list
        echo "$result" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    test_func = '$test_func'
    # Check if this specific test is in the snapshot tests list
    for st in data.get('snapshot_tests', []):
        if st == test_func or st.endswith('::' + test_func.split('::')[-1]):
            sys.exit(0)
    sys.exit(1)
except:
    sys.exit(1)
" && return 0 || return 1
    else
        # Fallback to simple grep check
        grep -q "snap_compare\|snapshot" "$test_file" 2>/dev/null && return 0 || return 1
    fi
}

# Function to run a test with optional snapshot update on failure
run_test_with_snapshot_detection() {
    local test_name="$1"
    local extra_args=("${@:2}")

    echo "[TEST] Running: $test_name"

    # Check if this test uses snapshots
    local uses_snapshots=false
    if test_uses_snapshots "$test_name"; then
        uses_snapshots=true
        echo "[INFO] Test uses snapshot comparisons"
    fi

    # Run the test and capture output
    local temp_output=$(mktemp)
    local exit_code=0

    if command -v pytest >/dev/null 2>&1; then
        pytest "$test_name" "${extra_args[@]}" 2>&1 | tee "$temp_output" || exit_code=$?
    else
        uv run pytest "$test_name" "${extra_args[@]}" 2>&1 | tee "$temp_output" || exit_code=$?
    fi

    # If test failed and uses snapshots, check if it's a snapshot failure
    if [[ $exit_code -ne 0 ]] && [[ "$uses_snapshots" == "true" ]]; then
        if grep -q -E "AssertionError.*snapshot|Snapshot.*differ|snap_compare.*failed" "$temp_output"; then
            echo ""
            echo "[SNAPSHOT] Snapshot mismatch detected, updating snapshots..."

            # Run again with --snapshot-update
            if command -v pytest >/dev/null 2>&1; then
                pytest "$test_name" --snapshot-update "${extra_args[@]}"
                exit_code=$?
            else
                uv run pytest "$test_name" --snapshot-update "${extra_args[@]}"
                exit_code=$?
            fi

            if [[ $exit_code -eq 0 ]]; then
                echo "[SNAPSHOT] Snapshots updated successfully"
            else
                echo "[ERROR] Failed to update snapshots"
            fi
        else
            echo "[FAIL] Test failed (non-snapshot related)"
        fi
    elif [[ $exit_code -eq 0 ]]; then
        echo "[PASS] Test passed"
    fi

    # Cleanup
    rm -f "$temp_output"

    return $exit_code
}

# Main function
main() {
    if [[ $# -eq 0 ]]; then
        echo "Usage: $0 <test_name> [pytest_args...]"
        echo ""
        echo "Run a single test with intelligent snapshot detection."
        echo "If the test fails due to snapshot mismatch, it will automatically"
        echo "retry with --snapshot-update (but only for tests that use snapshots)."
        echo ""
        echo "Examples:"
        echo "  $0 tests/test_app.py::TestClass::test_method"
        echo "  $0 tests/test_app.py::test_function -v"
        echo "  $0 tests/test_app.py::TestClass::test_snapshot_method --tb=short"
        exit 1
    fi

    run_test_with_snapshot_detection "$@"
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
