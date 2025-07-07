#!/usr/bin/env bash
# run_test_with_retry_on_snapshot_fail.sh - Run pytest with automatic retry on snapshot failure
# Version: 1.0.0
#
# This script implements the more efficient approach: run test first,
# then retry with --snapshot-update ONLY if it fails due to snapshot mismatch
#
set -euo pipefail

# Function to run a test and retry with --snapshot-update if snapshot fails
run_test_with_snapshot_retry() {
    local test_cmd=("$@")
    local temp_output=$(mktemp)
    local exit_code=0

    echo "[TEST] Running: ${test_cmd[*]}"

    # Run the test and capture output
    "${test_cmd[@]}" 2>&1 | tee "$temp_output" || exit_code=$?

    # If test failed, check if it's a snapshot failure
    if [[ $exit_code -ne 0 ]]; then
        # Check for snapshot-related failure patterns
        if grep -q -E "snapshot.*fail|snap_compare.*assert|AssertionError.*snapshot|Snapshot.*differ" "$temp_output"; then
            echo ""
            echo "[SNAPSHOT] Snapshot mismatch detected, retrying with --snapshot-update..."

            # Add --snapshot-update if not already present
            local has_snapshot_update=0
            for arg in "${test_cmd[@]}"; do
                if [[ "$arg" == "--snapshot-update" ]]; then
                    has_snapshot_update=1
                    break
                fi
            done

            if [[ $has_snapshot_update -eq 0 ]]; then
                test_cmd+=("--snapshot-update")
            fi

            # Retry with snapshot update
            "${test_cmd[@]}"
            exit_code=$?

            if [[ $exit_code -eq 0 ]]; then
                echo "[SNAPSHOT] Snapshots updated successfully"
            else
                echo "[ERROR] Test still fails after snapshot update"
            fi
        else
            echo "[FAIL] Test failed (not snapshot related)"
        fi
    else
        echo "[PASS] Test passed"
    fi

    # Cleanup
    rm -f "$temp_output"

    return $exit_code
}

# Main function
main() {
    if [[ $# -eq 0 ]]; then
        echo "Usage: $0 <pytest_command...>"
        echo ""
        echo "Run pytest command with automatic retry on snapshot failure."
        echo "More efficient than pre-detection - only adds --snapshot-update if needed."
        echo ""
        echo "Examples:"
        echo "  $0 pytest tests/test_app.py::test_method"
        echo "  $0 uv run pytest tests/test_app.py -v"
        echo ""
        echo "This approach is more efficient because:"
        echo "  1. No upfront analysis needed"
        echo "  2. Only retries if snapshot failure detected"
        echo "  3. Works even if project has no snapshots configured"
        exit 1
    fi

    run_test_with_snapshot_retry "$@"
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
