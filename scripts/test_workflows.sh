#!/usr/bin/env bash
# test_workflows.sh - Test GitHub Actions workflows locally and validate they actually run
# Version: 1.0.0
#
# This script tests that workflows actually execute their commands, not just queue them
#
# Usage:
#   ./scripts/test_workflows.sh                    # Run all tests
#   ./scripts/test_workflows.sh lint              # Test specific workflow
#   ./scripts/test_workflows.sh --validate-only   # Only run static validation
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
WORKFLOWS_DIR="$PROJECT_ROOT/.github/workflows"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Test results
TESTS_PASSED=0
TESTS_FAILED=0
VALIDATION_ERRORS=()

echo -e "${BLUE}=== GitHub Workflows Testing Suite ===${NC}"
echo

# Function to validate workflow syntax
validate_workflow_syntax() {
    local workflow="$1"
    local workflow_name=$(basename "$workflow")

    echo -n "Validating syntax of $workflow_name... "

    # Check YAML syntax
    if ! yamllint -d relaxed "$workflow" >/dev/null 2>&1; then
        echo -e "${RED}FAILED${NC} (YAML syntax error)"
        VALIDATION_ERRORS+=("$workflow_name: YAML syntax error")
        ((TESTS_FAILED++))
        return 1
    fi

    # Check with actionlint
    if command -v actionlint >/dev/null 2>&1; then
        if ! actionlint "$workflow" 2>/dev/null; then
            echo -e "${RED}FAILED${NC} (actionlint error)"
            VALIDATION_ERRORS+=("$workflow_name: actionlint validation failed")
            ((TESTS_FAILED++))
            return 1
        fi
    fi

    echo -e "${GREEN}PASSED${NC}"
    ((TESTS_PASSED++))
    return 0
}

# Function to check if workflow actually executes commands
check_workflow_execution() {
    local workflow="$1"
    local workflow_name=$(basename "$workflow")

    echo -n "Checking command execution in $workflow_name... "

    # Check for sep_queue.sh usage without --queue-start
    if grep -q "sep_queue.sh" "$workflow" && ! grep -q -- "--queue-start" "$workflow"; then
        echo -e "${RED}FAILED${NC} (uses sep_queue.sh but never starts queue)"
        VALIDATION_ERRORS+=("$workflow_name: Commands are queued but never executed!")
        ((TESTS_FAILED++))
        return 1
    fi

    # Check if sep_installer.sh is run before using SEP
    if grep -q "sep_queue.sh\|sep.sh" "$workflow" && ! grep -q "sep_installer.sh" "$workflow"; then
        echo -e "${YELLOW}WARNING${NC} (uses SEP without installation)"
        VALIDATION_ERRORS+=("$workflow_name: SEP used without running sep_installer.sh")
    fi

    echo -e "${GREEN}PASSED${NC}"
    ((TESTS_PASSED++))
    return 0
}

# Function to test workflow with act (dry run)
test_with_act() {
    local workflow="$1"
    local workflow_name=$(basename "$workflow" .yml)

    if ! command -v act >/dev/null 2>&1; then
        echo -e "${YELLOW}SKIPPED${NC} act not installed"
        return 0
    fi

    echo -n "Testing $workflow_name with act (dry-run)... "

    # Run act in dry-run mode to validate workflow
    if act -W "$workflow" -n --container-architecture linux/amd64 2>&1 | grep -q "Job succeeded"; then
        echo -e "${GREEN}PASSED${NC}"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}FAILED${NC}"
        ((TESTS_FAILED++))
    fi
}

# Function to check for common issues
check_common_issues() {
    local workflow="$1"
    local workflow_name=$(basename "$workflow")

    echo "Checking common issues in $workflow_name:"

    # Check for hardcoded paths
    if grep -q "/Users/\|/home/runner/work" "$workflow" 2>/dev/null; then
        echo -e "  ${YELLOW}WARNING${NC}: Contains hardcoded paths"
    fi

    # Check for missing checkout action
    if grep -q "uv \|npm \|yarn \|pnpm " "$workflow" && ! grep -q "actions/checkout" "$workflow"; then
        echo -e "  ${RED}ERROR${NC}: Uses commands but missing checkout action"
        ((TESTS_FAILED++))
    fi

    # Check for uv sync --locked
    if grep -q "uv sync" "$workflow" && ! grep -q "uv sync --locked" "$workflow"; then
        echo -e "  ${YELLOW}WARNING${NC}: Uses 'uv sync' without --locked flag"
    fi
}

# Main test execution
main() {
    local target_workflow="${1:-}"
    local validate_only=false

    if [[ "$target_workflow" == "--validate-only" ]]; then
        validate_only=true
        target_workflow=""
    fi

    # Install dependencies if needed
    if ! command -v yamllint >/dev/null 2>&1; then
        echo "Installing yamllint..."
        pip install --user yamllint
    fi

    if ! command -v actionlint >/dev/null 2>&1; then
        echo "Installing actionlint..."
        if [[ "$OSTYPE" == "darwin"* ]]; then
            brew install actionlint
        else
            # Download actionlint for Linux
            curl -s https://raw.githubusercontent.com/rhysd/actionlint/main/scripts/download-actionlint.bash | bash
            sudo mv actionlint /usr/local/bin/
        fi
    fi

    echo -e "${BLUE}Running workflow tests...${NC}"
    echo

    # Test each workflow
    for workflow in "$WORKFLOWS_DIR"/*.yml; do
        if [[ -n "$target_workflow" ]] && [[ "$(basename "$workflow" .yml)" != "$target_workflow" ]]; then
            continue
        fi

        echo -e "${CYAN}Testing $(basename "$workflow")${NC}"
        echo "----------------------------------------"

        validate_workflow_syntax "$workflow"
        check_workflow_execution "$workflow"
        check_common_issues "$workflow"

        if [[ "$validate_only" != true ]]; then
            test_with_act "$workflow"
        fi

        echo
    done

    # Summary
    echo -e "${BLUE}=== Test Summary ===${NC}"
    echo -e "Tests passed: ${GREEN}$TESTS_PASSED${NC}"
    echo -e "Tests failed: ${RED}$TESTS_FAILED${NC}"

    if [[ ${#VALIDATION_ERRORS[@]} -gt 0 ]]; then
        echo
        echo -e "${RED}Validation Errors:${NC}"
        for error in "${VALIDATION_ERRORS[@]}"; do
            echo "  - $error"
        done
    fi

    # Create detailed report
    create_test_report

    # Exit with error if any tests failed
    if [[ $TESTS_FAILED -gt 0 ]]; then
        exit 1
    fi
}

# Create detailed test report
create_test_report() {
    local report_file="$PROJECT_ROOT/workflow_test_report.md"

    cat > "$report_file" << EOF
# GitHub Workflows Test Report

Generated: $(date)

## Summary

- Total workflows tested: $(ls -1 "$WORKFLOWS_DIR"/*.yml | wc -l)
- Tests passed: $TESTS_PASSED
- Tests failed: $TESTS_FAILED

## Validation Errors

EOF

    if [[ ${#VALIDATION_ERRORS[@]} -gt 0 ]]; then
        for error in "${VALIDATION_ERRORS[@]}"; do
            echo "- $error" >> "$report_file"
        done
    else
        echo "No validation errors found." >> "$report_file"
    fi

    cat >> "$report_file" << EOF

## Recommendations

1. **Remove SEP from CI workflows** - SEP is designed for local development
2. **Run commands directly** - Like the fixed build.yml workflow
3. **Add workflow tests to CI** - Run this test script in CI
4. **Use act for local testing** - Test workflows before pushing

## Testing Commands

\`\`\`bash
# Test all workflows
./scripts/test_workflows.sh

# Test specific workflow
./scripts/test_workflows.sh lint

# Validate only (no act)
./scripts/test_workflows.sh --validate-only

# Test with act verbosely
act -W .github/workflows/lint.yml -v
\`\`\`
EOF

    echo
    echo -e "${GREEN}Test report saved to: $report_file${NC}"
}

# Run main function
main "$@"
