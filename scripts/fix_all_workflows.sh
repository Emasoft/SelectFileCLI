#!/usr/bin/env bash
# fix_all_workflows.sh - Fix all workflows to properly use SEP with --queue-start
set -euo pipefail

echo "Fixing all workflows to properly use SEP..."

# Function to add SEP setup and queue-start to workflows
fix_workflow() {
    local workflow="$1"
    local workflow_name=$(basename "$workflow")

    echo "Processing $workflow_name..."

    # Skip already fixed workflows
    if grep -q "Setup SEP" "$workflow" && grep -q -- "--queue-start" "$workflow"; then
        echo "  ✓ Already fixed"
        return
    fi

    # Check if it uses sep_queue.sh
    if ! grep -q "sep_queue.sh" "$workflow"; then
        echo "  - Doesn't use SEP"
        return
    fi

    # Add --queue-start after last sep_queue.sh command if missing
    if ! grep -q -- "--queue-start" "$workflow"; then
        # Find the last occurrence of sep_queue.sh and add --queue-start after it
        # This is a simplified fix - in production, we'd need more sophisticated parsing
        echo "  ! Needs --queue-start added"

        # Create a temporary file
        temp_file=$(mktemp)

        # Process the file
        awk '
        {
            lines[NR] = $0
            if ($0 ~ /sep_queue\.sh/ && $0 !~ /--queue-start/) {
                last_sep_line = NR
            }
        }
        END {
            for (i = 1; i <= NR; i++) {
                print lines[i]
                if (i == last_sep_line) {
                    # Add queue start after the last sep_queue.sh
                    print "        ./scripts/sep_queue.sh --queue-start"
                }
            }
        }
        ' "$workflow" > "$temp_file"

        # Replace original
        mv "$temp_file" "$workflow"
        echo "  ✓ Added --queue-start"
    fi
}

# Process all workflows
for workflow in .github/workflows/*.yml; do
    fix_workflow "$workflow"
done

echo ""
echo "Checking results..."
./scripts/check_workflow_execution.sh
