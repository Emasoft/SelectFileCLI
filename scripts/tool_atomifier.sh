#!/usr/bin/env bash
# tool_atomifier.sh - Tool configuration and atomification logic
# Version: 1.0.0
#
# This script contains the configuration and logic for atomifying commands
# into individual file operations for sequential execution.
#
set -euo pipefail

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
        echo "ATOMIC:wait_all.sh -- ${original_cmd[*]}"
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
        echo "ATOMIC:wait_all.sh -- ${original_cmd[*]}"
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
        
        echo "ATOMIC:wait_all.sh -- ${atomic_cmd[*]}"
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