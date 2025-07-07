#!/usr/bin/env bash
# tool_atomifier.sh - Tool configuration and atomification logic
# Version: 1.0.0
#
# This script contains the configuration and logic for atomifying commands
# into individual file operations for sequential execution.
#
set -euo pipefail

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Get file extensions for a given tool
get_tool_extensions() {
    local tool="$1"

    case "$tool" in
        # Python tools
        ruff|mypy|pytest|pytest-cov|pytest-watcher|pytest-asyncio|\
        pytest-sugar|pytest-mock|coverage|docformatter|nbqa|isort|\
        pyupgrade|hypothesis)
            echo "*.py *.pyi"
            ;;

        # JavaScript/TypeScript tools
        eslint|prettier|pnpm)
            echo "*.js *.jsx *.ts *.tsx *.mjs *.cjs"
            ;;

        # YAML tools
        yamllint|yamlfmt)
            echo "*.yml *.yaml"
            ;;

        # JSON tools
        jq|jsonlint)
            echo "*.json"
            ;;

        # GitHub Actions
        actionlint)
            echo "*.yml *.yaml"
            ;;

        # Shell script tools
        shellcheck)
            echo "*.sh *.bash"
            ;;

        # SQL tools
        sqlfluff)
            echo "*.sql"
            ;;

        # Documentation tools
        mkdocs)
            echo "*.md *.markdown"
            ;;

        # Generic tools that work on any file
        trufflehog|pre-commit|bfg)
            echo "*"
            ;;

        *)
            echo "*"
            ;;
    esac
}

# Check if a tool supports multiple files
supports_multiple_files() {
    local tool="$1"

    case "$tool" in
        # Tools that support multiple files
        ruff|eslint|prettier|shellcheck|yamllint)
            return 0
            ;;
        # Tools that require one file at a time
        mypy|pytest|jq|actionlint|yamlfmt)
            return 1
            ;;
        *)
            # Default to single file for safety
            return 1
            ;;
    esac
}

# Check if a tool requires special atomization
requires_special_atomization() {
    local tool="$1"

    case "$tool" in
        pytest)
            return 0
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
    local tool=""
    local subcommand=""
    local actual_tool=""

    # Handle uv run/tool run specially
    if [[ "${cmd_array[0]}" == "uv" ]]; then
        tool="uv"
        if [[ "${#cmd_array[@]}" -gt 1 ]]; then
            subcommand="${cmd_array[1]}"
            if [[ "$subcommand" == "run" ]] && [[ "${#cmd_array[@]}" -gt 2 ]]; then
                actual_tool="${cmd_array[2]}"
            elif [[ "$subcommand" == "tool" ]] && [[ "${#cmd_array[@]}" -gt 3 ]] && [[ "${cmd_array[2]}" == "run" ]]; then
                actual_tool="${cmd_array[3]}"
                subcommand="tool"
            fi
        fi
    else
        tool="${cmd_array[0]}"
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
        if [[ "$extensions" == "*" ]]; then
            # All files
            find "$path" -type f ! -path '*/\.*' -print
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
            find "$path" -type f \( "${find_args[@]}" \) ! -path '*/\.*' -print
        fi
    else
        # Might be a glob pattern
        local expanded
        expanded=($(compgen -G "$path" 2>/dev/null || true))
        if [[ ${#expanded[@]} -gt 0 ]]; then
            printf '%s\n' "${expanded[@]}"
        fi
    fi
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

        # Check if it's a file or directory
        if [[ "$arg" != -* ]] && [[ -e "$arg" ]]; then
            file_args+=("$arg")
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

# Generate atomic commands
generate_atomic_commands() {
    local original_cmd=("$@")
    local tool_info
    tool_info=$(parse_command "${original_cmd[@]}")

    local tool=$(echo "$tool_info" | cut -d'|' -f1)
    local subcommand=$(echo "$tool_info" | cut -d'|' -f2)
    local actual_tool=$(echo "$tool_info" | cut -d'|' -f3)

    # Debug output
    if [[ "${DEBUG:-0}" -eq 1 ]]; then
        echo "DEBUG: tool=$tool, subcommand=$subcommand, actual_tool=$actual_tool" >&2
    fi

    # Determine which tool to check for extensions
    local check_tool="$tool"
    if [[ -n "$actual_tool" ]]; then
        check_tool="$actual_tool"
    fi

    # Check if tool requires special atomization
    if requires_special_atomization "$check_tool"; then
        # Special handling for specific tools
        case "$check_tool" in
            pytest)
                generate_pytest_atomic_commands "${original_cmd[@]}"
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

    if [[ ${#unique_files[@]} -eq 0 ]]; then
        # No files found after expansion
        echo "ATOMIC:${original_cmd[*]}"
        return
    fi

    # Generate atomic commands
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

# Main function for testing
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Test mode
    if [[ $# -eq 0 ]]; then
        echo "Usage: $0 <command>"
        echo "Example: $0 ruff check src/"
        exit 1
    fi

    # Enable debug mode if DEBUG=1
    if [[ "${DEBUG:-0}" -eq 1 ]]; then
        set -x
    fi

    generate_atomic_commands "$@"
fi
