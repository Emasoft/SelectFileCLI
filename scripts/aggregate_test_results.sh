#!/usr/bin/env bash
# aggregate_test_results.sh - Aggregate pytest results from multiple job runs
# Version: 1.0.0
#
# This script aggregates pytest results from multiple sequential queue job runs
# to provide an overall summary of test execution
#
set -euo pipefail

# Default paths (can be overridden by environment variables)
RUNS_DIR="${SEQ_QUEUE_RUNS_DIR:-$HOME/.sequential_queue/runs}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Function to aggregate results from a specific run
aggregate_run_results() {
    local run_id="$1"
    local run_dir="${RUNS_DIR}/${run_id}"

    if [[ ! -d "$run_dir/jobs" ]]; then
        echo "ERROR: No jobs found for run $run_id" >&2
        return 1
    fi

    python3 -c "
import os
import json
import glob
from datetime import datetime

run_dir = '$run_dir'
jobs_dir = os.path.join(run_dir, 'jobs')

# Aggregate data
total_tests = 0
total_passed = 0
total_failed = 0
total_skipped = 0
total_errors = 0
all_tests = []
job_count = 0
pytest_job_count = 0

# Read all job metadata files
for job_file in sorted(glob.glob(os.path.join(jobs_dir, 'job_*.txt'))):
    if job_file.endswith('_pytest_results.json'):
        continue

    job_count += 1
    job_data = {}

    # Read job metadata
    with open(job_file, 'r') as f:
        for line in f:
            if '=' in line:
                key, value = line.strip().split('=', 1)
                job_data[key] = value

    # Check if this was a pytest job
    if 'PYTEST_RESULTS' in job_data:
        pytest_job_count += 1
        results_file = job_data['PYTEST_RESULTS']

        # Read pytest results
        if os.path.exists(results_file):
            with open(results_file, 'r') as f:
                results = json.load(f)

            summary = results.get('summary', {})
            total_passed += summary.get('passed', 0)
            total_failed += summary.get('failed', 0)
            total_skipped += summary.get('skipped', 0)
            total_errors += summary.get('error', 0)

            # Track individual test results
            for test in results.get('tests', []):
                test['job_id'] = job_data.get('JOB_ID', 'unknown')
                all_tests.append(test)

# Calculate totals
total_tests = total_passed + total_failed + total_skipped + total_errors

# Read run metadata
run_meta_file = os.path.join(run_dir, 'metadata.txt')
run_info = {}
if os.path.exists(run_meta_file):
    with open(run_meta_file, 'r') as f:
        for line in f:
            if '=' in line:
                key, value = line.strip().split('=', 1)
                run_info[key] = value

# Generate report
print('=' * 60)
print(f'TEST RESULTS SUMMARY FOR RUN: {run_info.get(\"RUN_ID\", \"unknown\")}')
print('=' * 60)
print(f'Start Time: {run_info.get(\"START_TIME\", \"unknown\")}')
print(f'End Time: {run_info.get(\"END_TIME\", \"unknown\")}')
print(f'Status: {run_info.get(\"STATUS\", \"unknown\")}')
print(f'Total Jobs: {job_count}')
print(f'Pytest Jobs: {pytest_job_count}')
print()
print('TEST STATISTICS:')
print(f'Total Tests Run: {total_tests}')
print(f'Passed: {total_passed} ({(total_passed/total_tests*100):.1f}%)' if total_tests > 0 else 'Passed: 0')
print(f'Failed: {total_failed} ({(total_failed/total_tests*100):.1f}%)' if total_tests > 0 else 'Failed: 0')
print(f'Skipped: {total_skipped}')
print(f'Errors: {total_errors}')
print()

# Group tests by result
by_result = {}
for test in all_tests:
    result = test.get('result', 'UNKNOWN')
    if result not in by_result:
        by_result[result] = []
    by_result[result].append(test)

# Show failed tests
if 'FAILED' in by_result:
    print(f'FAILED TESTS ({len(by_result[\"FAILED\"])}):')
    for test in by_result['FAILED'][:10]:  # Show first 10
        print(f'  - {test[\"test\"]} (job: {test[\"job_id\"]})')
    if len(by_result['FAILED']) > 10:
        print(f'  ... and {len(by_result[\"FAILED\"]) - 10} more')
    print()

# Summary
print('SUMMARY:')
if total_tests > 0:
    pass_rate = (total_passed / total_tests) * 100
    if pass_rate == 100:
        print('✅ All tests passed!')
    elif pass_rate >= 80:
        print(f'⚠️  {pass_rate:.1f}% tests passed - some failures detected')
    else:
        print(f'❌ Only {pass_rate:.1f}% tests passed - significant failures')
else:
    print('⚠️  No test results found')
"
}

# Function to find the latest run
find_latest_run() {
    local latest_run=""
    local latest_time=0

    for run_dir in "$RUNS_DIR"/run_*; do
        if [[ -d "$run_dir" ]]; then
            local run_id=$(basename "$run_dir")
            local meta_file="$run_dir/metadata.txt"

            if [[ -f "$meta_file" ]]; then
                local start_time=$(grep "^START_TIME=" "$meta_file" 2>/dev/null | cut -d= -f2- || echo "")
                if [[ -n "$start_time" ]]; then
                    # Convert to epoch for comparison
                    local epoch=$(date -j -f "%Y-%m-%d %H:%M:%S" "$start_time" "+%s" 2>/dev/null || echo "0")
                    if [[ $epoch -gt $latest_time ]]; then
                        latest_time=$epoch
                        latest_run=$run_id
                    fi
                fi
            fi
        fi
    done

    echo "$latest_run"
}

# Function to list all runs with pytest jobs
list_pytest_runs() {
    echo "Available runs with pytest jobs:"
    echo ""

    for run_dir in "$RUNS_DIR"/run_*; do
        if [[ -d "$run_dir/jobs" ]]; then
            local run_id=$(basename "$run_dir")
            local pytest_count=$(ls "$run_dir/jobs/"*_pytest_results.json 2>/dev/null | wc -l | tr -d ' ')

            if [[ $pytest_count -gt 0 ]]; then
                local meta_file="$run_dir/metadata.txt"
                local start_time="unknown"
                local status="unknown"

                if [[ -f "$meta_file" ]]; then
                    start_time=$(grep "^START_TIME=" "$meta_file" 2>/dev/null | cut -d= -f2- || echo "unknown")
                    status=$(grep "^STATUS=" "$meta_file" 2>/dev/null | cut -d= -f2- || echo "unknown")
                fi

                echo "  $run_id - $start_time [$status] ($pytest_count pytest jobs)"
            fi
        fi
    done
}

# Main function
main() {
    local run_id="${1:-}"

    if [[ -z "$run_id" ]]; then
        # Try to find the latest run
        run_id=$(find_latest_run)

        if [[ -z "$run_id" ]]; then
            echo "No runs found in $RUNS_DIR"
            echo ""
            echo "Usage: $0 [run_id|--list]"
            echo ""
            echo "Options:"
            echo "  run_id    Specific run ID to analyze"
            echo "  --list    List all runs with pytest jobs"
            echo ""
            echo "If no run_id is specified, analyzes the latest run"
            exit 1
        fi

        echo "Using latest run: $run_id"
        echo ""
    fi

    if [[ "$run_id" == "--list" ]]; then
        list_pytest_runs
        exit 0
    fi

    # Aggregate results for the specified run
    aggregate_run_results "$run_id"
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
