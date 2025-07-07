#!/usr/bin/env bash
# sep_tool_atomifier.sh - Tool configuration and atomification logic
# Version: 8.6.0
#
# This script contains the configuration and logic for atomifying commands
# into individual file operations for sequential execution.
#
# CHANGELOG:
# v8.6.0:
# - Version bump for consistency across all SEP scripts
# - Added missing sep_common.sh sourcing
# - Added unittest support for test-method atomization (second-tier)
# - unittest atomization only enabled with --enable-second-tier flag
# - CRITICAL: Added safety check to block ALL second-tier tool atomization without flag
# - Fixed pytest to detect :: syntax and avoid double-atomization
# - Changed nose2, ward, behave to no-atomize (no implementation = no atomization)
# - Safety principle: When in doubt, don't atomize
#
set -euo pipefail

VERSION='8.6.0'

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source common functions and definitions
source "${SCRIPT_DIR}/sep_common.sh"

# Source the comprehensive tool configuration
if [[ -f "$SCRIPT_DIR/sep_tool_config.sh" ]]; then
    # shellcheck source=sep_tool_config.sh
    source "$SCRIPT_DIR/sep_tool_config.sh"
else
    echo "ERROR: sep_tool_config.sh not found in $SCRIPT_DIR" >&2
    exit 1
fi

# Get file extensions for a given tool
get_tool_extensions() {
    local tool="$1"
    # Use the extended configuration
    get_extended_tool_extensions "$tool"
}

# Check if a tool supports multiple files
supports_multiple_files() {
    local tool="$1"
    # Use the extended configuration
    extended_supports_multiple_files "$tool"
}

# Check if a tool is second-tier
is_second_tier_tool() {
    local tool="$1"

    # Check if tool is in SECOND_TIER_TOOLS
    if [[ -n "${SECOND_TIER_TOOLS[$tool]+x}" ]]; then
        return 0
    fi
    return 1
}

# Check if a tool requires special atomization
requires_special_atomization() {
    local tool="$1"
    local enable_second_tier="${ENABLE_SECOND_TIER:-0}"

    case "$tool" in
        pytest)
            return 0
            ;;
        unittest)
            # Only atomize unittest if second-tier tools are enabled
            if is_second_tier_tool "$tool"; then
                [[ "$enable_second_tier" -eq 1 ]] && return 0
                return 1
            fi
            return 0  # First-tier test runners always get special atomization
            ;;
        *)
            return 1
            ;;
    esac
}

# Get the position of file arguments for a tool
get_file_arg_position() {
    local tool="$1"
    local subcommand="${2:-}"

    case "$tool" in
        # Tools where files come at the end
        ruff|mypy|pytest|eslint|prettier|shellcheck|yamllint|yamlfmt|\
        jsonlint|jq|actionlint|isort|pyupgrade|docformatter|nbqa)
            echo "end"
            ;;

        # Tools where files come after subcommand
        uv)
            case "$subcommand" in
                run|tool)
                    # uv run <tool> <args> <files>
                    echo "after-tool"
                    ;;
                *)
                    echo "end"
                    ;;
            esac
            ;;

        gh)
            case "$subcommand" in
                repo|pr|issue|release)
                    echo "after-subcommand"
                    ;;
                *)
                    echo "end"
                    ;;
            esac
            ;;

        # Tools with special handling
        pre-commit)
            # pre-commit run --files <files>
            echo "after-files-flag"
            ;;

        deptry)
            # deptry <directory>
            echo "end"
            ;;

        *)
            echo "end"
            ;;
    esac
}

# Parse command and extract tool info
parse_command() {
    local cmd_array=("$@")
    local runner_info
    runner_info=$(detect_runner "${cmd_array[@]}")

    local runner=$(echo "$runner_info" | cut -d'|' -f1)
    local runner_end_idx=$(echo "$runner_info" | cut -d'|' -f2)
    local actual_tool=$(echo "$runner_info" | cut -d'|' -f3)

    local tool=""
    local subcommand=""

    if [[ -n "$runner" ]]; then
        tool="$runner"
        # Extract subcommand if applicable
        case "$runner" in
            uv)
                [[ "${#cmd_array[@]}" -gt 1 ]] && subcommand="${cmd_array[1]}"
                ;;
            pnpm)
                [[ "${#cmd_array[@]}" -gt 1 ]] && [[ "${cmd_array[1]}" =~ ^(run|exec)$ ]] && subcommand="${cmd_array[1]}"
                ;;
        esac
    else
        tool="${cmd_array[0]}"
        # Check for tool subcommands
        if [[ "${#cmd_array[@]}" -gt 1 ]]; then
            case "$tool" in
                ruff)
                    [[ "${cmd_array[1]}" =~ ^(check|format)$ ]] && subcommand="${cmd_array[1]}"
                    ;;
                gh)
                    [[ "${cmd_array[1]}" =~ ^(repo|pr|issue|release|api)$ ]] && subcommand="${cmd_array[1]}"
                    ;;
                coverage)
                    [[ "${cmd_array[1]}" =~ ^(run|report|html|xml)$ ]] && subcommand="${cmd_array[1]}"
                    ;;
                commitizen|cz)
                    [[ "${cmd_array[1]}" =~ ^(check|bump|changelog)$ ]] && subcommand="${cmd_array[1]}"
                    ;;
            esac
        fi
    fi

    echo "$tool|$subcommand|$actual_tool"
}

# Find file arguments in command
find_file_args() {
    local position="$1"
    shift
    local cmd_array=("$@")
    local file_args=()
    local collecting=0

    case "$position" in
        end)
            # Collect arguments from the end until we hit an option
            local i
            for ((i=${#cmd_array[@]}-1; i>=0; i--)); do
                local arg="${cmd_array[$i]}"
                # Skip if this is the tool name itself
                if [[ $i -eq 0 ]]; then
                    continue
                fi
                # Skip if this is a subcommand (like 'check' for ruff)
                if [[ $i -eq 1 ]] && [[ "${cmd_array[0]}" == "ruff" ]] && [[ "$arg" =~ ^(check|format)$ ]]; then
                    continue
                fi

                if [[ "$arg" == -* ]]; then
                    # This is an option, stop collecting if we were collecting
                    if [[ $collecting -eq 1 ]]; then
                        break
                    fi
                else
                    # This is not an option, it might be a file/directory
                    collecting=1
                    file_args=("$arg" "${file_args[@]}")
                fi
            done
            ;;

        after-tool)
            # For uv run <tool> <args> <files>
            # Find the tool, then collect non-option arguments after it
            local found_tool=0
            local tool_index=0

            for ((i=0; i<${#cmd_array[@]}; i++)); do
                if [[ $found_tool -eq 0 ]] && [[ "${cmd_array[$i]}" == "run" ]]; then
                    tool_index=$((i+1))
                    found_tool=1
                elif [[ $i -gt $tool_index ]] && [[ $found_tool -eq 1 ]] && [[ "${cmd_array[$i]}" != -* ]]; then
                    # Check if this looks like a file/directory
                    if [[ -e "${cmd_array[$i]}" ]] || [[ "${cmd_array[$i]}" == */* ]] || [[ "${cmd_array[$i]}" == *.* ]]; then
                        file_args+=("${cmd_array[$i]}")
                    fi
                fi
            done
            ;;

        after-files-flag)
            # For pre-commit run --files <files>
            local found_flag=0
            for ((i=0; i<${#cmd_array[@]}; i++)); do
                if [[ "${cmd_array[$i]}" == "--files" ]]; then
                    found_flag=1
                elif [[ $found_flag -eq 1 ]] && [[ "${cmd_array[$i]}" != -* ]]; then
                    file_args+=("${cmd_array[$i]}")
                elif [[ $found_flag -eq 1 ]] && [[ "${cmd_array[$i]}" == -* ]]; then
                    break
                fi
            done
            ;;
    esac

    # Return file args
    printf '%s\n' "${file_args[@]}"
}

# Expand a path to individual files
expand_path() {
    local path="$1"
    local extensions="$2"
    local files=()

    # Resolve special paths
    path="${path/#\~/$HOME}"
    path="$(eval echo "$path")"

    if [[ -f "$path" ]]; then
        # Single file
        echo "$path"
    elif [[ -d "$path" ]]; then
        # Directory - expand based on extensions
        # Common directories to exclude
        local common_excludes=(
            -path '*/\.*' -o
            -path '*/__pycache__/*' -o
            -path '*/\.venv/*' -o
            -path '*/venv/*' -o
            -path '*/env/*' -o
            -path '*/node_modules/*' -o
            -path '*/\.git/*' -o
            -path '*/\.pytest_cache/*' -o
            -path '*/\.mypy_cache/*' -o
            -path '*/\.ruff_cache/*' -o
            -path '*/build/*' -o
            -path '*/dist/*' -o
            -path '*/.tox/*' -o
            -path '*/.eggs/*' -o
            -path '*/htmlcov/*' -o
            -path '*/.coverage/*'
        )

        if [[ "$extensions" == "*" ]]; then
            # All files
            find "$path" -type f ! \( "${common_excludes[@]}" \) -print
        else
            # Specific extensions - use array to prevent globbing
            local ext_array=()
            # Read extensions into array, preserving wildcards
            read -ra ext_array <<< "$extensions"

            # Build find arguments
            local find_args=()
            for ext in "${ext_array[@]}"; do
                find_args+=(-name "$ext" -o)
            done
            # Remove last -o
            unset 'find_args[-1]'

            # Execute find with proper quoting
            find "$path" -type f \( "${find_args[@]}" \) ! \( "${common_excludes[@]}" \) -print
        fi
    else
        # Might be a glob pattern
        local expanded
        expanded=($(compgen -G "$path" 2>/dev/null || true))
        if [[ ${#expanded[@]} -gt 0 ]]; then
            # Filter out common excluded patterns
            for file in "${expanded[@]}"; do
                # Skip if file is in an excluded directory
                if [[ ! "$file" =~ /(\.venv|venv|env|__pycache__|node_modules|\.git|\.pytest_cache|\.mypy_cache|build|dist)/ ]]; then
                    echo "$file"
                fi
            done
        fi
    fi
}

# Extract unittest test methods from a Python test file
extract_unittest_methods() {
    local test_file="$1"

    # Use Python to find unittest test methods
    python3 -c "
import ast
import sys
import os

test_file = '$test_file'

if not os.path.exists(test_file):
    sys.exit(1)

try:
    with open(test_file, 'r') as f:
        tree = ast.parse(f.read())

    # Find all test methods in TestCase classes
    for node in ast.walk(tree):
        if isinstance(node, ast.ClassDef):
            # Check if it inherits from TestCase or starts with Test
            is_test_class = False
            if node.name.startswith('Test'):
                is_test_class = True
            else:
                # Check base classes
                for base in node.bases:
                    if isinstance(base, ast.Name) and 'TestCase' in base.id:
                        is_test_class = True
                        break
                    elif isinstance(base, ast.Attribute) and base.attr == 'TestCase':
                        is_test_class = True
                        break

            if is_test_class:
                # Find test methods
                for item in node.body:
                    if isinstance(item, ast.FunctionDef) and item.name.startswith('test'):
                        print(f'{node.name}.{item.name}')
                    elif isinstance(item, ast.AsyncFunctionDef) and item.name.startswith('test'):
                        print(f'{node.name}.{item.name}')
except Exception as e:
    # Fallback to regex if AST parsing fails
    import re
    try:
        with open(test_file, 'r') as f:
            content = f.read()
            # Find test classes
            class_pattern = r'^class\\s+(\\w+)\\s*\\([^)]*TestCase[^)]*\\)|^class\\s+(Test\\w+)'
            method_pattern = r'^\\s+(async\\s+)?def\\s+(test_\\w+)'

            current_class = None
            for line in content.split('\\n'):
                class_match = re.match(class_pattern, line)
                if class_match:
                    current_class = class_match.group(1) or class_match.group(2)
                elif current_class:
                    method_match = re.match(method_pattern, line)
                    if method_match:
                        print(f'{current_class}.{method_match.group(2)}')
    except:
        sys.exit(1)
" 2>/dev/null
}

# Extract test functions from a Python test file using pytest --collect-only
extract_test_functions() {
    local test_file="$1"

    # Use Python to parse pytest collection output and format test names
    python3 -c "
import subprocess
import sys
import re

test_file = '$test_file'

# Run pytest --collect-only
try:
    # Try direct pytest first, then uv run pytest
    import shutil
    if shutil.which('pytest'):
        cmd = ['pytest', test_file, '--collect-only', '--quiet', '--no-header', '--tb=no']
    else:
        cmd = ['uv', 'run', 'pytest', test_file, '--collect-only', '--quiet', '--no-header', '--tb=no']

    result = subprocess.run(
        cmd,
        capture_output=True,
        text=True
    )

    # Parse the collection output which has a tree structure
    content = result.stdout

    # Find all test items using regex
    test_pattern = r'<(Function|Coroutine)\\s+(test_\\w+)>'
    class_pattern = r'<Class\\s+(Test\\w+)>'

    current_class = None

    for line in content.split('\\n'):
        # Check for class
        class_match = re.search(class_pattern, line)
        if class_match:
            current_class = class_match.group(1)
            continue

        # Check for test
        test_match = re.search(test_pattern, line)
        if test_match:
            test_name = test_match.group(2)
            if current_class:
                print(f'{current_class}::{test_name}')
            else:
                print(test_name)

except Exception as e:
    # Fallback to simple grep if pytest fails
    import os
    if os.path.exists(test_file):
        with open(test_file, 'r') as f:
            content = f.read()
            # Find test functions
            for match in re.finditer(r'^\\s*(async\\s+)?def\\s+(test_\\w+)', content, re.MULTILINE):
                print(match.group(2))
            # Find test classes and their methods
            class_matches = re.finditer(r'^class\\s+(Test\\w+).*?(?=^class|\\Z)', content, re.MULTILINE | re.DOTALL)
            for class_match in class_matches:
                class_name = class_match.group(1)
                class_content = class_match.group(0)
                for method_match in re.finditer(r'^\\s+(async\\s+)?def\\s+(test_\\w+)', class_content, re.MULTILINE):
                    print(f'{class_name}::{method_match.group(2)}')
" 2>/dev/null
}

# Check if a test file contains snapshot tests
has_snapshot_tests() {
    local test_file="$1"
    grep -q "snap_compare\|snapshot" "$test_file"
}

# Get list of snapshot tests in a file
get_snapshot_tests() {
    local test_file="$1"

    # Use Python script if available
    if [[ -x "${SCRIPT_DIR}/detect_snapshot_tests.py" ]] && command -v python3 >/dev/null 2>&1; then
        # Try to detect snapshot tests, but handle failures gracefully
        python3 "${SCRIPT_DIR}/detect_snapshot_tests.py" "$test_file" 2>/dev/null | \
            python3 -c "import sys, json; d=json.load(sys.stdin); [print(t) for t in d.get('snapshot_tests', [])]" 2>/dev/null || true
    else
        # Fallback to grep - returns empty if no matches found
        grep -B5 "snap_compare\|snapshot" "$test_file" 2>/dev/null | \
            grep -E "^[[:space:]]*(async[[:space:]]+)?def[[:space:]]+test_|^class[[:space:]]+Test" | \
            sed -E 's/^[[:space:]]*(async[[:space:]]+)?def[[:space:]]+//' | \
            sed -E 's/^class[[:space:]]+//' | \
            sed -E 's/[(:].*$//' | \
            grep -E '^(test_|Test)' || true
    fi
}

# Generate pytest atomic commands for individual test functions
generate_pytest_atomic_commands() {
    set +e  # Temporarily disable error exit
    local original_cmd=("$@")
    local file_args=()
    local non_file_args=()
    local has_k_flag=0
    local has_snapshot_update=0

    # Parse arguments
    for ((i=0; i<${#original_cmd[@]}; i++)); do
        local arg="${original_cmd[$i]}"

        # Skip pytest itself
        if [[ $i -eq 0 ]] && [[ "$arg" == "pytest" ]]; then
            non_file_args+=("$arg")
            continue
        fi

        # Check for -k flag
        if [[ "$arg" == "-k" ]]; then
            has_k_flag=1
            non_file_args+=("$arg")
            if [[ $((i + 1)) -lt ${#original_cmd[@]} ]]; then
                ((i++))
                non_file_args+=("${original_cmd[$i]}")
            fi
            continue
        fi

        # Check for --snapshot-update
        if [[ "$arg" == "--snapshot-update" ]]; then
            has_snapshot_update=1
            non_file_args+=("$arg")
            continue
        fi

        # Check if it's a file, directory, or test specification
        if [[ "$arg" != -* ]]; then
            # Check for pytest :: syntax (file::class::method or file::function)
            if [[ "$arg" == *"::"* ]]; then
                # This is already a specific test selection, don't atomize
                echo "ATOMIC:${original_cmd[*]}"
                return
            elif [[ -e "$arg" ]]; then
                file_args+=("$arg")
            else
                # Might be a module name or other argument
                non_file_args+=("$arg")
            fi
        else
            non_file_args+=("$arg")
        fi
    done

    # If -k flag is present, don't atomize (already selecting specific tests)
    if [[ $has_k_flag -eq 1 ]]; then
        echo "ATOMIC:${original_cmd[*]}"
        return
    fi

    # If no files specified, use current directory
    if [[ ${#file_args[@]} -eq 0 ]]; then
        file_args=(".")
    fi

    # Expand directories to test files
    local test_files=()
    for arg in "${file_args[@]}"; do
        if [[ -f "$arg" ]] && [[ "$arg" == *.py ]]; then
            test_files+=("$arg")
        elif [[ -d "$arg" ]]; then
            # Find all test files in directory
            while IFS= read -r -d '' test_file; do
                test_files+=("$test_file")
            done < <(find "$arg" -name "test_*.py" -o -name "*_test.py" -print0)
        fi
    done

    # If no test files found, run as-is
    if [[ ${#test_files[@]} -eq 0 ]]; then
        echo "ATOMIC:${original_cmd[*]}"
        return
    fi

    if [[ "${DEBUG:-0}" -eq 1 ]]; then
        echo "DEBUG: Processing ${#test_files[@]} test files" >&2
    fi

    # Generate atomic commands for each test function
    for test_file in "${test_files[@]}"; do
        # Skip if file doesn't exist or is empty
        if [[ ! -s "$test_file" ]]; then
            continue
        fi

        # Check if this is a snapshot test file
        local is_snapshot_test=0
        if has_snapshot_tests "$test_file"; then
            is_snapshot_test=1
        fi

        # Extract test functions
        local test_functions=()
        if ! mapfile -t test_functions < <(extract_test_functions "$test_file"); then
            if [[ "${DEBUG:-0}" -eq 1 ]]; then
                echo "DEBUG: Failed to extract test functions from $test_file" >&2
            fi
            # Fall back to running the whole file
            echo "ATOMIC:${non_file_args[*]} $test_file"
            continue
        fi

        if [[ "${DEBUG:-0}" -eq 1 ]]; then
            echo "DEBUG: Found ${#test_functions[@]} test functions" >&2
        fi

        if [[ ${#test_functions[@]} -eq 0 ]]; then
            # No test functions found, run the whole file
            echo "ATOMIC:${non_file_args[*]} $test_file"
        else
            # For tests with --snapshot-update, intelligently handle based on actual snapshot usage
            if [[ $has_snapshot_update -eq 1 ]]; then
                if [[ "${DEBUG:-0}" -eq 1 ]]; then
                    echo "DEBUG: Intelligent snapshot detection mode" >&2
                fi

                # Get list of snapshot tests (safe handling if detection fails)
                local snapshot_tests=()
                if command -v python3 >/dev/null 2>&1 && [[ -x "${SCRIPT_DIR}/detect_snapshot_tests.py" ]]; then
                    # Try to get snapshot tests, but continue even if it fails
                    mapfile -t snapshot_tests < <(get_snapshot_tests "$test_file" 2>/dev/null || true)
                fi

                # If snapshot detection failed or no snapshots found, treat all as regular tests
                if [[ ${#snapshot_tests[@]} -eq 0 ]]; then
                    if [[ "${DEBUG:-0}" -eq 1 ]]; then
                        echo "DEBUG: No snapshot tests detected, treating all as regular tests" >&2
                    fi
                fi

                # Separate snapshot and non-snapshot tests
                local snapshot_test_funcs=()
                local regular_test_funcs=()

                for test_func in "${test_functions[@]}"; do
                    local is_snapshot=0
                    for snap_test in "${snapshot_tests[@]}"; do
                        if [[ "$test_func" == "$snap_test" ]]; then
                            is_snapshot=1
                            break
                        fi
                    done

                    if [[ $is_snapshot -eq 1 ]]; then
                        snapshot_test_funcs+=("$test_func")
                    else
                        regular_test_funcs+=("$test_func")
                    fi
                done

                if [[ "${DEBUG:-0}" -eq 1 ]]; then
                    echo "DEBUG: Found ${#snapshot_test_funcs[@]} snapshot tests and ${#regular_test_funcs[@]} regular tests" >&2
                fi

                # Generate commands for snapshot tests (batched in pairs)
                if [[ ${#snapshot_test_funcs[@]} -gt 0 ]]; then
                    local batch_size=2
                    local batch_count=0
                    local batch_tests=""

                    for test_func in "${snapshot_test_funcs[@]}"; do
                        if [[ $batch_count -eq 0 ]]; then
                            batch_tests="$test_file::$test_func"
                        else
                            batch_tests="$batch_tests $test_file::$test_func"
                        fi

                        ((batch_count++))

                        if [[ $batch_count -eq $batch_size ]]; then
                            echo "ATOMIC:${non_file_args[*]} $batch_tests"
                            batch_count=0
                            batch_tests=""
                        fi
                    done

                    # Handle remaining snapshot tests
                    if [[ -n "$batch_tests" ]]; then
                        echo "ATOMIC:${non_file_args[*]} $batch_tests"
                    fi
                fi

                # Generate commands for regular tests (without --snapshot-update)
                if [[ ${#regular_test_funcs[@]} -gt 0 ]]; then
                    # Remove --snapshot-update for non-snapshot tests
                    local cmd_without_snapshot=()
                    for arg in "${non_file_args[@]}"; do
                        if [[ "$arg" != "--snapshot-update" ]]; then
                            cmd_without_snapshot+=("$arg")
                        fi
                    done

                    for test_func in "${regular_test_funcs[@]}"; do
                        echo "ATOMIC:${cmd_without_snapshot[*]} $test_file::$test_func"
                    done
                fi
            else
                # For non-snapshot tests or without --snapshot-update, run individually
                # But check if individual tests need snapshot update
                if [[ $has_snapshot_update -eq 1 ]]; then
                    # Get list of snapshot tests
                    local snapshot_tests=()
                    if command -v python3 >/dev/null 2>&1 && [[ -x "${SCRIPT_DIR}/detect_snapshot_tests.py" ]]; then
                        mapfile -t snapshot_tests < <(get_snapshot_tests "$test_file")
                    fi

                    # Generate commands based on whether test uses snapshots
                    for test_func in "${test_functions[@]}"; do
                        local needs_snapshot=0

                        # Check if this test is in the snapshot tests list
                        for snap_test in "${snapshot_tests[@]}"; do
                            if [[ "$test_func" == "$snap_test" ]]; then
                                needs_snapshot=1
                                break
                            fi
                        done

                        if [[ $needs_snapshot -eq 1 ]]; then
                            echo "ATOMIC:${non_file_args[*]} $test_file::$test_func"
                        else
                            # Remove --snapshot-update for non-snapshot tests
                            local cmd_without_snapshot=()
                            for arg in "${non_file_args[@]}"; do
                                if [[ "$arg" != "--snapshot-update" ]]; then
                                    cmd_without_snapshot+=("$arg")
                                fi
                            done
                            echo "ATOMIC:${cmd_without_snapshot[*]} $test_file::$test_func"
                        fi
                    done
                else
                    # No snapshot update requested, run normally
                    for test_func in "${test_functions[@]}"; do
                        echo "ATOMIC:${non_file_args[*]} $test_file::$test_func"
                    done
                fi
            fi
        fi
    done
    set -e  # Re-enable error exit
}

# Generate unittest atomic commands for individual test methods
generate_unittest_atomic_commands() {
    set +e  # Temporarily disable error exit
    local original_cmd=("$@")
    local file_args=()
    local non_file_args=()
    local has_k_flag=0
    local has_m_flag=0
    local discover_mode=0

    # Parse arguments
    for ((i=0; i<${#original_cmd[@]}; i++)); do
        local arg="${original_cmd[$i]}"

        # Skip unittest itself or python -m unittest
        if [[ "$arg" == "unittest" ]] || [[ "$arg" == "-m" && "${original_cmd[$((i+1))]}" == "unittest" ]]; then
            non_file_args+=("$arg")
            continue
        fi

        # Check for -k flag (pattern matching)
        if [[ "$arg" == "-k" ]]; then
            has_k_flag=1
            non_file_args+=("$arg")
            if [[ $((i + 1)) -lt ${#original_cmd[@]} ]]; then
                ((i++))
                non_file_args+=("${original_cmd[$i]}")
            fi
            continue
        fi

        # Check for -m flag (already running specific method)
        if [[ "$arg" =~ ^.*\.test_.*$ ]]; then
            has_m_flag=1
            non_file_args+=("$arg")
            continue
        fi

        # Check for discover mode
        if [[ "$arg" == "discover" ]]; then
            discover_mode=1
            non_file_args+=("$arg")
            continue
        fi

        # Check if it's a file or module
        if [[ "$arg" != -* ]]; then
            # Check if it's a file path
            if [[ -f "$arg" ]] || [[ "$arg" == *.py ]]; then
                file_args+=("$arg")
            # Check if it's a module.class.method pattern
            elif [[ "$arg" =~ ^[a-zA-Z_][a-zA-Z0-9_]*(\.[a-zA-Z_][a-zA-Z0-9_]*)*$ ]]; then
                # Could be a module or test spec
                if [[ "$arg" =~ \.test_ ]]; then
                    # Already specific test method
                    has_m_flag=1
                    non_file_args+=("$arg")
                else
                    # Module or class
                    file_args+=("$arg")
                fi
            else
                non_file_args+=("$arg")
            fi
        else
            non_file_args+=("$arg")
        fi
    done

    # If already running specific test or in discover mode, don't atomize
    if [[ $has_m_flag -eq 1 ]] || [[ $has_k_flag -eq 1 ]] || [[ $discover_mode -eq 1 ]]; then
        echo "ATOMIC:${original_cmd[*]}"
        return
    fi

    # If no files/modules specified, don't atomize
    if [[ ${#file_args[@]} -eq 0 ]]; then
        echo "ATOMIC:${original_cmd[*]}"
        return
    fi

    # Process each file/module
    for arg in "${file_args[@]}"; do
        local test_file=""

        # Convert module to file path if needed
        if [[ -f "$arg" ]]; then
            test_file="$arg"
        else
            # Try to find the file for the module
            local module_path="${arg//.//}.py"
            if [[ -f "$module_path" ]]; then
                test_file="$module_path"
            else
                # Can't find file, run as-is
                echo "ATOMIC:${non_file_args[*]} $arg"
                continue
            fi
        fi

        # Extract test methods
        local test_methods=()
        if ! mapfile -t test_methods < <(extract_unittest_methods "$test_file"); then
            if [[ "${DEBUG:-0}" -eq 1 ]]; then
                echo "DEBUG: Failed to extract test methods from $test_file" >&2
            fi
            # Fall back to running the whole file
            echo "ATOMIC:${non_file_args[*]} $arg"
            continue
        fi

        if [[ "${DEBUG:-0}" -eq 1 ]]; then
            echo "DEBUG: Found ${#test_methods[@]} test methods" >&2
        fi

        if [[ ${#test_methods[@]} -eq 0 ]]; then
            # No test methods found, run the whole file
            echo "ATOMIC:${non_file_args[*]} $arg"
        else
            # Generate commands for each test method
            for test_method in "${test_methods[@]}"; do
                # For unittest, use module.class.method format
                local module_name="${arg%.py}"
                module_name="${module_name//\//.}"
                echo "ATOMIC:${non_file_args[*]} ${module_name}.${test_method}"
            done
        fi
    done
    set -e  # Re-enable error exit
}

# Generate atomic commands
generate_atomic_commands() {
    local original_cmd=("$@")
    local tool_info
    tool_info=$(parse_command "${original_cmd[@]}")

    local tool=$(echo "$tool_info" | cut -d'|' -f1)
    local subcommand=$(echo "$tool_info" | cut -d'|' -f2)
    local actual_tool=$(echo "$tool_info" | cut -d'|' -f3)

    # Get project root (assuming we're in a git repo or use current directory)
    local project_root
    project_root=$(git rev-parse --show-toplevel 2>/dev/null || pwd)

    # Debug output
    if [[ "${DEBUG:-0}" -eq 1 ]]; then
        echo "DEBUG: tool=$tool, subcommand=$subcommand, actual_tool=$actual_tool" >&2
        echo "DEBUG: project_root=$project_root" >&2
    fi

    # Determine which tool to check for extensions
    local check_tool="$tool"
    if [[ -n "$actual_tool" ]]; then
        check_tool="$actual_tool"
    fi

    # CRITICAL SAFETY CHECK: Block second-tier tools if flag not set
    local enable_second_tier="${ENABLE_SECOND_TIER:-0}"
    if is_second_tier_tool "$check_tool" && [[ "$enable_second_tier" -ne 1 ]]; then
        if [[ "${DEBUG:-0}" -eq 1 ]]; then
            echo "DEBUG: Second-tier tool '$check_tool' blocked - --enable-second-tier not set" >&2
        fi
        # Don't atomize second-tier tools without explicit permission
        echo "ATOMIC:${original_cmd[*]}"
        return
    fi

    # Get atomization rules
    local atomization_rule
    atomization_rule=$(get_tool_atomization_rules "$check_tool")

    # Handle tools that shouldn't be atomized
    if [[ "$atomization_rule" == "no-atomize" ]]; then
        echo "ATOMIC:${original_cmd[*]}"
        return
    fi

    # Check if tool requires special atomization
    if requires_special_atomization "$check_tool"; then
        # Special handling for specific tools
        case "$check_tool" in
            pytest*)
                generate_pytest_atomic_commands "${original_cmd[@]}"
                return $?
                ;;
            unittest)
                generate_unittest_atomic_commands "${original_cmd[@]}"
                return $?
                ;;
        esac
    fi

    # Get tool configuration
    local extensions
    extensions=$(get_tool_extensions "$check_tool")
    local position
    position=$(get_file_arg_position "$tool" "$subcommand")

    # Debug output
    if [[ "${DEBUG:-0}" -eq 1 ]]; then
        echo "DEBUG: check_tool=$check_tool, extensions=$extensions, position=$position" >&2
        echo "DEBUG: atomization_rule=$atomization_rule" >&2
    fi

    # Find file arguments
    local file_args
    mapfile -t file_args < <(find_file_args "$position" "${original_cmd[@]}")

    # Debug output
    if [[ "${DEBUG:-0}" -eq 1 ]]; then
        echo "DEBUG: file_args=(${file_args[*]})" >&2
    fi

    if [[ ${#file_args[@]} -eq 0 ]]; then
        # No file arguments found, run as-is
        echo "ATOMIC:${original_cmd[*]}"
        return
    fi

    # Expand file arguments
    local all_files=()
    for arg in "${file_args[@]}"; do
        if [[ "${DEBUG:-0}" -eq 1 ]]; then
            echo "DEBUG: Expanding arg: $arg" >&2
        fi
        mapfile -t expanded < <(expand_path "$arg" "$extensions")
        if [[ "${DEBUG:-0}" -eq 1 ]]; then
            echo "DEBUG: Expanded to: ${#expanded[@]} files" >&2
            for f in "${expanded[@]}"; do
                echo "DEBUG:   - $f" >&2
            done
        fi
        all_files+=("${expanded[@]}")
    done

    # Remove duplicates
    local unique_files=()
    local seen=()
    for file in "${all_files[@]}"; do
        if [[ ! " ${seen[*]} " =~ " $file " ]]; then
            unique_files+=("$file")
            seen+=("$file")
        fi
    done

    # Filter files based on ignore patterns
    if [[ ${#unique_files[@]} -gt 0 ]]; then
        mapfile -t unique_files < <(filter_files_by_ignores "$check_tool" "$project_root" "${unique_files[@]}")

        if [[ "${DEBUG:-0}" -eq 1 ]]; then
            echo "DEBUG: After filtering ignores: ${#unique_files[@]} files remain" >&2
        fi
    fi

    if [[ ${#unique_files[@]} -eq 0 ]]; then
        # No files found after expansion and filtering
        echo "ATOMIC:${original_cmd[*]}"
        return
    fi

    # Handle directory-level atomization
    if [[ "$atomization_rule" == "directory" ]]; then
        # Group files by directory
        declare -A dirs
        for file in "${unique_files[@]}"; do
            local dir=$(dirname "$file")
            dirs["$dir"]=1
        done

        # Generate commands for each directory
        for dir in "${!dirs[@]}"; do
            local atomic_cmd=()
            for ((i=0; i<${#original_cmd[@]}; i++)); do
                local arg="${original_cmd[$i]}"
                local is_file_arg=0

                for file_arg in "${file_args[@]}"; do
                    if [[ "$arg" == "$file_arg" ]]; then
                        is_file_arg=1
                        break
                    fi
                done

                if [[ $is_file_arg -eq 1 ]]; then
                    # Replace with directory
                    if [[ $i -eq $((${#original_cmd[@]}-1)) ]] || [[ "${original_cmd[$((i+1))]}" == -* ]]; then
                        atomic_cmd+=("$dir")
                    fi
                else
                    atomic_cmd+=("$arg")
                fi
            done

            # Ensure directory is added
            local has_dir=0
            for cmd_part in "${atomic_cmd[@]}"; do
                if [[ "$cmd_part" == "$dir" ]]; then
                    has_dir=1
                    break
                fi
            done

            [[ $has_dir -eq 0 ]] && atomic_cmd+=("$dir")
            echo "ATOMIC:${atomic_cmd[*]}"
        done
        return
    fi

    # Check if tool supports multiple files
    if supports_multiple_files "$check_tool" && [[ ${#unique_files[@]} -gt 1 ]]; then
        # Tool supports multiple files, output single command with all files
        local atomic_cmd=()
        local replaced_files=0

        for ((i=0; i<${#original_cmd[@]}; i++)); do
            local arg="${original_cmd[$i]}"
            local is_file_arg=0

            for file_arg in "${file_args[@]}"; do
                if [[ "$arg" == "$file_arg" ]]; then
                    is_file_arg=1
                    break
                fi
            done

            if [[ $is_file_arg -eq 1 ]] && [[ $replaced_files -eq 0 ]]; then
                # Replace with all files
                atomic_cmd+=("${unique_files[@]}")
                replaced_files=1
            elif [[ $is_file_arg -eq 0 ]]; then
                atomic_cmd+=("$arg")
            fi
        done

        # If files weren't added yet, add them now
        if [[ $replaced_files -eq 0 ]]; then
            atomic_cmd+=("${unique_files[@]}")
        fi

        echo "ATOMIC:${atomic_cmd[*]}"
        return
    fi

    # Generate atomic commands for each file
    for file in "${unique_files[@]}"; do
        local atomic_cmd=()
        local skip_next=0

        # Reconstruct command with single file
        for ((i=0; i<${#original_cmd[@]}; i++)); do
            local arg="${original_cmd[$i]}"

            if [[ $skip_next -eq 1 ]]; then
                skip_next=0
                continue
            fi

            # Check if this is a file argument
            local is_file_arg=0
            for file_arg in "${file_args[@]}"; do
                if [[ "$arg" == "$file_arg" ]]; then
                    is_file_arg=1
                    break
                fi
            done

            if [[ $is_file_arg -eq 1 ]]; then
                # Replace with single file
                if [[ $i -eq $((${#original_cmd[@]}-1)) ]] || [[ "${original_cmd[$((i+1))]}" == -* ]]; then
                    # This is the last file argument position
                    atomic_cmd+=("$file")
                fi
            else
                atomic_cmd+=("$arg")
            fi
        done

        # If file wasn't added yet (for 'end' position), add it now
        local has_file=0
        for cmd_part in "${atomic_cmd[@]}"; do
            if [[ "$cmd_part" == "$file" ]]; then
                has_file=1
                break
            fi
        done

        if [[ $has_file -eq 0 ]]; then
            atomic_cmd+=("$file")
        fi

        echo "ATOMIC:${atomic_cmd[*]}"
    done
}

# Display help message
show_help() {
    cat << 'EOF'
sep_tool_atomifier.sh v8.5.0 - Command atomification for sequential execution

USAGE:
    sep_tool_atomifier.sh [OPTIONS] -- COMMAND [ARGS...]
    sep_tool_atomifier.sh COMMAND [ARGS...]

DESCRIPTION:
    Breaks down tool commands into atomic file-level operations.
    Used internally by sep_queue.sh to process files individually.
    Respects tool-specific ignore files and configuration.

OPTIONS:
    --help, -h     Show this help message
    --version      Show version information
    --debug        Enable debug output

SUPPORTED TOOLS WITH RUNNERS:
    uv run <tool>      Run tools via uv
    uv tool run <tool> Run tools via uv tool
    npx <tool>         Run Node.js tools
    pnpm run <tool>    Run via pnpm scripts
    pnpm exec <tool>   Execute via pnpm

SUPPORTED PYTHON TOOLS:
    ruff               Fast Python linter
    mypy               Static type checker
    pytest             Test framework (atomizes to individual tests)
    pytest-cov         Coverage plugin for pytest
    coverage           Code coverage measurement
    black              Code formatter
    isort              Import sorter
    docformatter       Docstring formatter
    nbqa               Run tools on Jupyter notebooks
    pyupgrade          Upgrade syntax for newer Python versions
    deptry             Dependency checker
    hypothesis         Property-based testing
    syrupy             Snapshot testing
    pytest-watcher     Auto-run tests on file changes
    pytest-asyncio     Async test support
    pytest-sugar       Better test output
    pytest-mock        Mock fixture for pytest

SUPPORTED JAVASCRIPT/TYPESCRIPT TOOLS:
    eslint             JavaScript/TypeScript linter
    prettier           Code formatter
    pnpm               Package manager

SUPPORTED YAML/CONFIG TOOLS:
    yamllint           YAML linter
    yamlfmt            YAML formatter
    actionlint         GitHub Actions linter

SUPPORTED OTHER TOOLS:
    shellcheck         Shell script linter
    jq                 JSON processor
    jsonlint           JSON validator
    sqlfluff           SQL linter and formatter
    mkdocs             Documentation generator
    gh                 GitHub CLI
    act                Run GitHub Actions locally
    bfg                Git history cleaner
    commitizen         Conventional commits
    cz-conventional-gitmoji  Gitmoji commits
    trufflehog         Secret scanner
    pre-commit         Git hook framework
    uv-pre-commit      Pre-commit for uv

IGNORE FILE SUPPORT:
    Each tool respects its specific ignore files:
    - .gitignore (fallback for most tools)
    - .ruffignore, .prettierignore, .eslintignore
    - pyproject.toml sections for Python tools
    - .yamllint for YAML tools
    - Tool-specific config files

EXAMPLES:
    # Atomify ruff check with runner
    sep_tool_atomifier.sh uv run ruff check src/

    # Atomify pytest (creates commands per test function)
    sep_tool_atomifier.sh pytest tests/

    # Run with npm package
    sep_tool_atomifier.sh npx prettier --write src/

    # Debug mode to see ignore filtering
    DEBUG=1 sep_tool_atomifier.sh mypy src/

OUTPUT FORMAT:
    Each line starts with "ATOMIC:" followed by the atomified command.
    These are consumed by sep_queue.sh for execution.

EOF
    exit 0
}

# Main function for testing
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Check for help or version flags
    case "${1:-}" in
        --help|-h)
            show_help
            ;;
        --version)
            echo "sep_tool_atomifier.sh v$VERSION"
            exit 0
            ;;
        --debug)
            DEBUG=1
            shift
            ;;
    esac

    # Test mode
    if [[ $# -eq 0 ]]; then
        echo "Usage: $0 <command>"
        echo "Example: $0 ruff check src/"
        echo "Run '$0 --help' for detailed information"
        exit 1
    fi

    # Enable debug mode if DEBUG=1
    if [[ "${DEBUG:-0}" -eq 1 ]]; then
        set -x
    fi

    generate_atomic_commands "$@"
fi
