#!/usr/bin/env bash
# parse_pytest_results.sh - Parse pytest output and extract test results
# Version: 1.0.0
#
# This script parses pytest output to extract individual test results
# and saves them in a structured format for analysis
#
set -euo pipefail

# Function to parse pytest output and extract test results
parse_pytest_output() {
    local log_file="$1"
    local output_file="${2:-}"

    if [[ ! -f "$log_file" ]]; then
        echo "ERROR: Log file not found: $log_file" >&2
        return 1
    fi

    # Extract test results using Python for reliable parsing
    python3 -c "
import re
import sys
import json

log_file = '$log_file'
output_file = '$output_file' if '$output_file' else None

with open(log_file, 'r') as f:
    content = f.read()

# Patterns to match pytest output
test_pattern = r'^(tests/[^:]+::[^:]+(?:::[^:]+)?)\s+(\w+)'
summary_pattern = r'=+ (.*?) =+'
failed_pattern = r'FAILED (tests/[^:]+::[^:]+(?:::[^:]+)?)'
passed_pattern = r'PASSED'
skipped_pattern = r'SKIPPED'

# Parse individual test results
tests = []
for line in content.split('\n'):
    # Match test result lines
    match = re.match(test_pattern, line)
    if match:
        test_name = match.group(1)
        result = match.group(2)
        tests.append({
            'test': test_name,
            'result': result,
            'line': line.strip()
        })

    # Also capture FAILED tests with details
    failed_match = re.search(failed_pattern, line)
    if failed_match:
        test_name = failed_match.group(1)
        # Find if we already have this test, update its status
        found = False
        for test in tests:
            if test['test'] == test_name:
                test['result'] = 'FAILED'
                found = True
                break
        if not found:
            tests.append({
                'test': test_name,
                'result': 'FAILED',
                'line': line.strip()
            })

# Extract summary
summary = {}
summary_match = re.search(r'=+ (\d+ passed|)(?:, )?(\d+ failed|)(?:, )?(\d+ skipped|)(?:, )?(\d+ error|)?.*in [\d.]+s', content)
if summary_match:
    for group in summary_match.groups():
        if group:
            parts = group.strip().split()
            if len(parts) == 2:
                count, status = parts
                summary[status] = int(count)

# Extract total test count
total_match = re.search(r'collected (\d+) items?', content)
if total_match:
    summary['total'] = int(total_match.group(1))

# Calculate pass rate
if 'total' in summary and summary['total'] > 0:
    passed = summary.get('passed', 0)
    summary['pass_rate'] = round((passed / summary['total']) * 100, 2)

# Create result structure
result = {
    'summary': summary,
    'tests': tests,
    'total_tests': len(tests)
}

# Output results
if output_file:
    with open(output_file, 'w') as f:
        json.dump(result, f, indent=2)
else:
    print(json.dumps(result, indent=2))
"
}

# Function to generate a summary report
generate_summary() {
    local results_file="$1"

    python3 -c "
import json

with open('$results_file', 'r') as f:
    data = json.load(f)

summary = data.get('summary', {})
tests = data.get('tests', [])

print('=== PYTEST RESULTS SUMMARY ===')
print(f\"Total tests collected: {summary.get('total', 'unknown')}\")
print(f\"Passed: {summary.get('passed', 0)}\")
print(f\"Failed: {summary.get('failed', 0)}\")
print(f\"Skipped: {summary.get('skipped', 0)}\")
print(f\"Errors: {summary.get('error', 0)}\")
if 'pass_rate' in summary:
    print(f\"Pass rate: {summary['pass_rate']}%\")

if tests:
    print(f\"\\nDetailed results for {len(tests)} tests captured\")

    # Group by status
    by_status = {}
    for test in tests:
        status = test.get('result', 'UNKNOWN')
        if status not in by_status:
            by_status[status] = []
        by_status[status].append(test['test'])

    for status, test_list in by_status.items():
        print(f\"\\n{status} ({len(test_list)}):\")
        for test_name in test_list[:5]:  # Show first 5
            print(f\"  - {test_name}\")
        if len(test_list) > 5:
            print(f\"  ... and {len(test_list) - 5} more\")
"
}

# Main function
main() {
    local log_file="${1:-}"
    local output_file="${2:-}"

    if [[ -z "$log_file" ]]; then
        echo "Usage: $0 <pytest_log_file> [output_json_file]"
        echo ""
        echo "Parse pytest output and extract test results"
        echo ""
        echo "Examples:"
        echo "  $0 test_output.log                    # Print JSON to stdout"
        echo "  $0 test_output.log results.json       # Save to JSON file"
        echo "  $0 test_output.log results.json -s    # Save and show summary"
        exit 1
    fi

    # Parse pytest output
    if [[ -n "$output_file" ]]; then
        parse_pytest_output "$log_file" "$output_file"
        echo "Results saved to: $output_file"

        # Show summary if requested
        if [[ "${3:-}" == "-s" ]]; then
            echo ""
            generate_summary "$output_file"
        fi
    else
        parse_pytest_output "$log_file"
    fi
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
