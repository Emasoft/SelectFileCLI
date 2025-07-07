#!/usr/bin/env bash
# sep_tool_config.sh - Comprehensive tool configuration for atomification
# Version: 8.5.0
#
# This script contains detailed configuration for all supported tools including:
# - Command syntax patterns
# - Ignore file formats and locations
# - File extension mappings
# - Special atomization rules
# - Runner enforcement mappings
# - Second-tier tool support
#

# Supported runners (SEP is uv-centric, these are the only allowed runners)
# Check if already defined to avoid readonly redefinition errors
if [[ -z "${SUPPORTED_RUNNERS+x}" ]]; then
    readonly SUPPORTED_RUNNERS=(
        "uv"      # UV - primary Python package manager
        "pipx"    # Python application installer
        "pnpm"    # Node.js package manager
        "go"      # Go language runner
        "npx"     # Node.js package executor
    )
fi

# Tool to runner mappings (enforced by default)
# Check if already defined to avoid redeclaration errors
if [[ -z "${TOOL_RUNNER_MAPPING+x}" ]]; then
    declare -gA TOOL_RUNNER_MAPPING=(
        # Python tools - use uv by default
        ["ruff"]="uv run"
    ["mypy"]="uv run"
    ["pytest"]="uv run"
    ["pytest-cov"]="uv run"
    ["coverage"]="uv run"
    ["black"]="uv run"
    ["isort"]="uv run"
    ["docformatter"]="uv run"
    ["nbqa"]="uv run"
    ["pyupgrade"]="uv run"
    ["deptry"]="uv run"
    ["hypothesis"]="uv run"
    ["syrupy"]="uv run"
    ["pytest-watcher"]="uv run"
    ["pytest-asyncio"]="uv run"
    ["pytest-sugar"]="uv run"
    ["pytest-mock"]="uv run"
    ["mkdocs"]="uv run"
    ["commitizen"]="uv run"
    ["cz"]="uv run"

    # Tools that should use pipx
    ["pre-commit"]="pipx run"
    ["uv-pre-commit"]="pipx run"

    # JavaScript tools - use npx or pnpm
    ["eslint"]="npx"
    ["prettier"]="npx"
    ["jsonlint"]="npx"

    # Shell/system tools - no runner needed
    ["shellcheck"]=""
    ["yamllint"]=""
    ["yamlfmt"]=""
    ["actionlint"]=""
    ["jq"]=""
    ["gh"]=""
    ["act"]=""
    ["bfg"]=""
    ["trufflehog"]=""
    ["sqlfluff"]=""
    )
fi

# Second-tier tools (less trusted, enabled with --enable-second-tier)
# Check if already defined to avoid redeclaration errors
if [[ -z "${SECOND_TIER_TOOLS+x}" ]]; then
    declare -gA SECOND_TIER_TOOLS=(
    # Python testing
    ["unittest"]="uv run"
    ["nose2"]="uv run"
    ["tox"]="uv run"

    # Security tools
    ["gitleaks"]=""
    ["bandit"]="uv run"
    ["safety"]="uv run"
    ["pip-audit"]="uv run"

    # Code quality
    ["vulture"]="uv run"
    ["radon"]="uv run"
    ["xenon"]="uv run"
    ["prospector"]="uv run"
    ["pylama"]="uv run"
    ["pydocstyle"]="uv run"
    ["darglint"]="uv run"

    # Type checking
    ["pyre"]="uv run"
    ["pyright"]="npx"
    ["pytype"]="uv run"

    # Other development tools
    ["invoke"]="uv run"
    ["nox"]="uv run"
    ["ward"]="uv run"
    ["behave"]="uv run"
    ["locust"]="uv run"
    )
fi

# Tool ignore file configurations
# Check if already defined to avoid redeclaration errors
if [[ -z "${TOOL_IGNORE_FILES+x}" ]]; then
    declare -gA TOOL_IGNORE_FILES=(
    # Python tools
    ["ruff"]=".ruffignore:.gitignore"
    ["mypy"]=".mypy.ini:mypy.ini:pyproject.toml:.gitignore"
    ["pytest"]=".pytest.ini:pytest.ini:pyproject.toml:tox.ini:setup.cfg"
    ["coverage"]=".coveragerc:pyproject.toml:setup.cfg"
    ["isort"]=".isort.cfg:pyproject.toml:setup.cfg:tox.ini:.gitignore"
    ["black"]=".black:pyproject.toml:.gitignore"
    ["docformatter"]=".docformatterrc:pyproject.toml:setup.cfg"
    ["nbqa"]="pyproject.toml:.gitignore"
    ["pyupgrade"]="pyproject.toml:.gitignore"
    ["deptry"]="pyproject.toml:.gitignore"

    # JavaScript/TypeScript tools
    ["eslint"]=".eslintignore:.gitignore"
    ["prettier"]=".prettierignore:.gitignore"
    ["pnpm"]="package.json:.npmignore:.gitignore"

    # YAML tools
    ["yamllint"]=".yamllint:.yamllint.yaml:.yamllint.yml"
    ["yamlfmt"]=".yamlfmt:.gitignore"

    # Other tools
    ["shellcheck"]=".shellcheckrc"
    ["actionlint"]=".gitignore"
    ["sqlfluff"]=".sqlfluff:.sqlfluffignore"
    ["mkdocs"]="mkdocs.yml:.gitignore"
    ["pre-commit"]=".pre-commit-config.yaml"
    ["trufflehog"]="trufflehog.yaml:.gitignore"
    ["commitizen"]="pyproject.toml:.cz.toml:.cz.json:.cz.yaml"

    # Generic fallback
    ["*"]=".gitignore"

    # Second-tier tools
    ["unittest"]="pyproject.toml:setup.cfg:.gitignore"
    ["nose2"]="nose2.cfg:pyproject.toml:.gitignore"
    ["tox"]="tox.ini:pyproject.toml:.gitignore"
    ["gitleaks"]=".gitleaks.toml:.gitignore"
    ["bandit"]=".bandit:pyproject.toml:.gitignore"
    ["safety"]="pyproject.toml:.gitignore"
    ["pip-audit"]="pyproject.toml:.gitignore"
    ["vulture"]="pyproject.toml:.gitignore"
    ["radon"]="pyproject.toml:.gitignore"
    ["xenon"]="pyproject.toml:.gitignore"
    ["prospector"]=".prospector.yaml:pyproject.toml:.gitignore"
    ["pylama"]="pylama.ini:pyproject.toml:.gitignore"
    ["pydocstyle"]=".pydocstyle:pyproject.toml:.gitignore"
    ["darglint"]=".darglint:pyproject.toml:.gitignore"
    ["pyre"]=".pyre_configuration:pyproject.toml:.gitignore"
    ["pyright"]="pyrightconfig.json:pyproject.toml:.gitignore"
    ["pytype"]=".pytype.cfg:pyproject.toml:.gitignore"
    ["invoke"]="invoke.yaml:tasks.py:.gitignore"
    ["nox"]="noxfile.py:.gitignore"
    ["ward"]="pyproject.toml:.gitignore"
    ["behave"]=".behaverc:behave.ini:.gitignore"
    ["locust"]="locust.conf:pyproject.toml:.gitignore"
    )
fi

# Tool-specific ignore patterns (in addition to ignore files)
# Check if already defined to avoid redeclaration errors
if [[ -z "${TOOL_BUILTIN_IGNORES+x}" ]]; then
    declare -gA TOOL_BUILTIN_IGNORES=(
    ["ruff"]="__pycache__:*.pyc:.venv:venv:env:.git:.pytest_cache:.mypy_cache:.ruff_cache"
    ["mypy"]="__pycache__:*.pyc:.venv:venv:env:.git:.pytest_cache:.mypy_cache"
    ["pytest"]="__pycache__:*.pyc:.venv:venv:env:.git:.pytest_cache:build:dist"
    ["eslint"]="node_modules:.git:dist:build:coverage:.next:.nuxt"
    ["prettier"]="node_modules:.git:dist:build:coverage:.next:.nuxt:*.min.js:*.min.css"
    ["yamllint"]=".git:node_modules:vendor"
    ["shellcheck"]=".git"
    ["*"]=".git:.svn:.hg"
    )
fi

# Tool command patterns for detection
# Check if already defined to avoid redeclaration errors
if [[ -z "${TOOL_PATTERNS+x}" ]]; then
    declare -gA TOOL_PATTERNS=(
    # Direct tool invocations
    ["ruff"]="^ruff( |$)"
    ["mypy"]="^mypy( |$)"
    ["pytest"]="^pytest( |$)"
    ["eslint"]="^eslint( |$)"
    ["prettier"]="^prettier( |$)"
    ["yamllint"]="^yamllint( |$)"
    ["shellcheck"]="^shellcheck( |$)"
    ["black"]="^black( |$)"
    ["isort"]="^isort( |$)"
    ["coverage"]="^coverage( |$)"
    ["pre-commit"]="^pre-commit( |$)"
    ["trufflehog"]="^trufflehog( |$)"
    ["commitizen"]="^(commitizen|cz)( |$)"
    ["deptry"]="^deptry( |$)"
    ["actionlint"]="^actionlint( |$)"
    ["sqlfluff"]="^sqlfluff( |$)"
    ["mkdocs"]="^mkdocs( |$)"
    ["jq"]="^jq( |$)"
    ["jsonlint"]="^jsonlint( |$)"
    ["gh"]="^gh( |$)"
    ["act"]="^act( |$)"
    ["bfg"]="^bfg( |$)"
    ["docformatter"]="^docformatter( |$)"
    ["nbqa"]="^nbqa( |$)"
    ["pyupgrade"]="^pyupgrade( |$)"
    ["yamlfmt"]="^yamlfmt( |$)"
    ["syrupy"]="^syrupy( |$)"
    ["hypothesis"]="^hypothesis( |$)"

    # Runner patterns
    ["uv"]="^uv( |$)"
    ["npx"]="^npx( |$)"
    ["pnpm"]="^pnpm( |$)"
    )
fi

# Parse gitignore-style file
parse_gitignore_file() {
    local file="$1"
    local patterns=()

    if [[ -f "$file" ]]; then
        while IFS= read -r line; do
            # Skip empty lines and comments
            [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue

            # Remove leading/trailing whitespace
            line=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

            # Add pattern
            [[ -n "$line" ]] && patterns+=("$line")
        done < "$file"
    fi

    printf '%s\n' "${patterns[@]}"
}

# Parse YAML configuration for ignore patterns
parse_yaml_ignores() {
    local file="$1"
    local key="$2"

    if [[ -f "$file" ]] && command -v python3 >/dev/null 2>&1; then
        python3 -c "
import yaml
import sys
try:
    with open('$file', 'r') as f:
        data = yaml.safe_load(f)
        if isinstance(data, dict):
            # Navigate nested keys
            keys = '$key'.split('.')
            value = data
            for k in keys:
                if isinstance(value, dict) and k in value:
                    value = value[k]
                else:
                    sys.exit(1)

            # Print ignore patterns
            if isinstance(value, list):
                for item in value:
                    print(item)
            elif isinstance(value, str):
                print(value)
except:
    sys.exit(1)
" 2>/dev/null || true
    fi
}

# Parse TOML configuration for ignore patterns
parse_toml_ignores() {
    local file="$1"
    local section="$2"
    local key="$3"

    if [[ -f "$file" ]] && command -v python3 >/dev/null 2>&1; then
        python3 -c "
try:
    import tomllib
except ImportError:
    import tomli as tomllib
import sys

try:
    with open('$file', 'rb') as f:
        data = tomllib.load(f)

    # Navigate to section
    if '$section' in data:
        section_data = data['$section']
        if isinstance(section_data, dict) and '$key' in section_data:
            value = section_data['$key']
            if isinstance(value, list):
                for item in value:
                    print(item)
            elif isinstance(value, str):
                print(value)
except:
    sys.exit(1)
" 2>/dev/null || true
    fi
}

# Get ignore patterns for a tool
get_tool_ignore_patterns() {
    local tool="$1"
    local project_root="${2:-.}"
    local all_patterns=()

    # Get builtin ignores (safely handle missing keys)
    local builtin=""
    if [[ -n "${TOOL_BUILTIN_IGNORES[$tool]+x}" ]]; then
        builtin="${TOOL_BUILTIN_IGNORES[$tool]}"
    elif [[ -n "${TOOL_BUILTIN_IGNORES['*']+x}" ]]; then
        builtin="${TOOL_BUILTIN_IGNORES['*']}"
    fi
    if [[ -n "$builtin" ]]; then
        IFS=':' read -ra builtin_array <<< "$builtin"
        all_patterns+=("${builtin_array[@]}")
    fi

    # Get ignore files for this tool (safely handle missing keys)
    local ignore_files=""
    if [[ -n "${TOOL_IGNORE_FILES[$tool]+x}" ]]; then
        ignore_files="${TOOL_IGNORE_FILES[$tool]}"
    elif [[ -n "${TOOL_IGNORE_FILES['*']+x}" ]]; then
        ignore_files="${TOOL_IGNORE_FILES['*']}"
    fi

    local files_array=()
    if [[ -n "$ignore_files" ]]; then
        IFS=':' read -ra files_array <<< "$ignore_files"
    fi

    # Parse each ignore file
    for ignore_file in "${files_array[@]}"; do
        local full_path="$project_root/$ignore_file"

        case "$ignore_file" in
            *.gitignore|*.ruffignore|*.prettierignore|*.eslintignore|*.sqlfluffignore)
                mapfile -t patterns < <(parse_gitignore_file "$full_path")
                all_patterns+=("${patterns[@]}")
                ;;

            pyproject.toml)
                # Tool-specific TOML parsing
                case "$tool" in
                    ruff)
                        mapfile -t patterns < <(parse_toml_ignores "$full_path" "tool.ruff" "exclude")
                        all_patterns+=("${patterns[@]}")
                        ;;
                    mypy)
                        mapfile -t patterns < <(parse_toml_ignores "$full_path" "tool.mypy" "exclude")
                        all_patterns+=("${patterns[@]}")
                        ;;
                    black)
                        mapfile -t patterns < <(parse_toml_ignores "$full_path" "tool.black" "exclude")
                        all_patterns+=("${patterns[@]}")
                        ;;
                    isort)
                        mapfile -t patterns < <(parse_toml_ignores "$full_path" "tool.isort" "skip")
                        all_patterns+=("${patterns[@]}")
                        mapfile -t patterns < <(parse_toml_ignores "$full_path" "tool.isort" "skip_glob")
                        all_patterns+=("${patterns[@]}")
                        ;;
                    coverage)
                        mapfile -t patterns < <(parse_toml_ignores "$full_path" "tool.coverage.run" "omit")
                        all_patterns+=("${patterns[@]}")
                        ;;
                    pytest)
                        mapfile -t patterns < <(parse_toml_ignores "$full_path" "tool.pytest.ini_options" "norecursedirs")
                        all_patterns+=("${patterns[@]}")
                        ;;
                    deptry)
                        mapfile -t patterns < <(parse_toml_ignores "$full_path" "tool.deptry" "exclude")
                        all_patterns+=("${patterns[@]}")
                        ;;
                esac
                ;;

            .yamllint|.yamllint.yaml|.yamllint.yml)
                mapfile -t patterns < <(parse_yaml_ignores "$full_path" "ignore")
                all_patterns+=("${patterns[@]}")
                ;;

            setup.cfg)
                # INI-style parsing for some tools
                if [[ -f "$full_path" ]]; then
                    case "$tool" in
                        mypy)
                            patterns=$(grep -A10 '^\[mypy\]' "$full_path" 2>/dev/null | grep '^exclude' | cut -d'=' -f2- | tr ',' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
                            [[ -n "$patterns" ]] && all_patterns+=($patterns)
                            ;;
                        coverage)
                            patterns=$(grep -A10 '^\[coverage:run\]' "$full_path" 2>/dev/null | grep '^omit' | cut -d'=' -f2- | tr ',' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
                            [[ -n "$patterns" ]] && all_patterns+=($patterns)
                            ;;
                    esac
                fi
                ;;
        esac
    done

    # Remove duplicates and empty patterns
    local unique_patterns=()
    local seen=()
    for pattern in "${all_patterns[@]}"; do
        if [[ -n "$pattern" ]] && [[ ! " ${seen[*]} " =~ " $pattern " ]]; then
            unique_patterns+=("$pattern")
            seen+=("$pattern")
        fi
    done

    printf '%s\n' "${unique_patterns[@]}"
}

# Check if a file matches any ignore pattern
file_matches_ignore() {
    local file="$1"
    shift
    local patterns=("$@")

    for pattern in "${patterns[@]}"; do
        # Handle different pattern types
        case "$pattern" in
            /*)
                # Absolute path pattern
                [[ "$file" == "$pattern"* ]] && return 0
                ;;
            */)
                # Directory pattern
                [[ "$file" == *"$pattern"* ]] && return 0
                ;;
            */*)
                # Path pattern
                [[ "$file" == *"$pattern"* ]] && return 0
                ;;
            *)
                # Simple pattern - check basename and path
                local basename=$(basename "$file")
                [[ "$basename" == $pattern ]] && return 0
                [[ "$file" == *"/$pattern/"* ]] && return 0
                ;;
        esac
    done

    return 1
}

# Filter files based on ignore patterns
filter_files_by_ignores() {
    local tool="$1"
    local project_root="$2"
    shift 2
    local files=("$@")

    # Get ignore patterns
    mapfile -t ignore_patterns < <(get_tool_ignore_patterns "$tool" "$project_root")

    # Filter files
    local filtered=()
    for file in "${files[@]}"; do
        if ! file_matches_ignore "$file" "${ignore_patterns[@]}"; then
            filtered+=("$file")
        fi
    done

    printf '%s\n' "${filtered[@]}"
}

# Detect runner and extract actual tool
detect_runner() {
    local cmd_array=("$@")
    local runner=""
    local runner_end_idx=0
    local actual_tool=""

    # Check first element for runner
    case "${cmd_array[0]}" in
        uv)
            runner="uv"
            if [[ "${#cmd_array[@]}" -gt 1 ]]; then
                case "${cmd_array[1]}" in
                    run)
                        runner_end_idx=1
                        [[ "${#cmd_array[@]}" -gt 2 ]] && actual_tool="${cmd_array[2]}"
                        ;;
                    tool)
                        if [[ "${#cmd_array[@]}" -gt 2 ]] && [[ "${cmd_array[2]}" == "run" ]]; then
                            runner_end_idx=2
                            [[ "${#cmd_array[@]}" -gt 3 ]] && actual_tool="${cmd_array[3]}"
                        fi
                        ;;
                esac
            fi
            ;;
        npx)
            runner="npx"
            runner_end_idx=0
            [[ "${#cmd_array[@]}" -gt 1 ]] && actual_tool="${cmd_array[1]}"
            ;;
        pnpm)
            runner="pnpm"
            if [[ "${#cmd_array[@]}" -gt 1 ]] && [[ "${cmd_array[1]}" == "run" ]]; then
                runner_end_idx=1
                [[ "${#cmd_array[@]}" -gt 2 ]] && actual_tool="${cmd_array[2]}"
            elif [[ "${#cmd_array[@]}" -gt 1 ]] && [[ "${cmd_array[1]}" == "exec" ]]; then
                runner_end_idx=1
                [[ "${#cmd_array[@]}" -gt 2 ]] && actual_tool="${cmd_array[2]}"
            fi
            ;;
        *)
            # No runner detected
            actual_tool="${cmd_array[0]}"
            ;;
    esac

    echo "$runner|$runner_end_idx|$actual_tool"
}

# Get file extensions for extended tool list
get_extended_tool_extensions() {
    local tool="$1"

    case "$tool" in
        # Python tools
        ruff|mypy|pytest|pytest-cov|pytest-watcher|pytest-asyncio|\
        pytest-sugar|pytest-mock|coverage|docformatter|nbqa|isort|\
        pyupgrade|hypothesis|black|deptry|packaging|pluggy|pygments|\
        watchdog|syrupy|colorama|ruff-pre-commit)
            echo "*.py *.pyi"
            ;;

        # JavaScript/TypeScript tools
        eslint|prettier|pnpm|npx)
            echo "*.js *.jsx *.ts *.tsx *.mjs *.cjs *.vue"
            ;;

        # YAML tools
        yamllint|yamlfmt)
            echo "*.yml *.yaml"
            ;;

        # JSON tools
        jq|jsonlint)
            echo "*.json *.jsonl *.geojson"
            ;;

        # GitHub Actions
        actionlint)
            echo ".github/workflows/*.yml .github/workflows/*.yaml"
            ;;

        # Shell script tools
        shellcheck)
            echo "*.sh *.bash *.zsh *.ksh"
            ;;

        # SQL tools
        sqlfluff)
            echo "*.sql *.ddl *.dml"
            ;;

        # Documentation tools
        mkdocs)
            echo "*.md *.markdown *.rst"
            ;;

        # Git/GitHub tools
        gh|bfg)
            echo "*"
            ;;

        # Pre-commit and similar
        pre-commit|uv-pre-commit|commitizen|cz-conventional-gitmoji)
            echo "*"
            ;;

        # Security tools
        trufflehog)
            echo "*"
            ;;

        # Container tools
        act)
            echo "*.yml *.yaml"
            ;;

        # Second-tier Python tools
        unittest|nose2|tox|bandit|safety|pip-audit|vulture|radon|\
        xenon|prospector|pylama|pydocstyle|darglint|pyre|pytype|\
        invoke|nox|ward|behave|locust)
            echo "*.py *.pyi"
            ;;

        # Second-tier JS tools
        pyright)
            echo "*.py *.pyi *.js *.ts"
            ;;

        # Second-tier security tools
        gitleaks)
            echo "*"
            ;;

        *)
            echo "*"
            ;;
    esac
}

# Check if tool supports multiple files in one command
extended_supports_multiple_files() {
    local tool="$1"

    case "$tool" in
        # Tools that support multiple files
        ruff|eslint|prettier|shellcheck|yamllint|black|isort|\
        docformatter|pyupgrade|nbqa|sqlfluff|jsonlint)
            return 0
            ;;

        # Tools that require one file at a time
        mypy|pytest|jq|actionlint|yamlfmt|coverage|deptry)
            return 1
            ;;

        # Tools that work on whole project/directory
        pre-commit|uv-pre-commit|trufflehog|gh|act|bfg|\
        commitizen|cz-conventional-gitmoji|mkdocs)
            return 1
            ;;

        # Second-tier tools that support multiple files
        bandit|vulture|radon|xenon|pylama|pydocstyle|darglint)
            return 0
            ;;

        # Second-tier tools that require single file
        unittest|nose2|tox|gitleaks|safety|pip-audit|prospector|\
        pyre|pyright|pytype|invoke|nox|ward|behave|locust)
            return 1
            ;;

        *)
            # Default to single file for safety
            return 1
            ;;
    esac
}

# Get special atomization rules for tools
get_tool_atomization_rules() {
    local tool="$1"

    case "$tool" in
        pytest*)
            echo "test-function"
            ;;
        pre-commit|uv-pre-commit)
            echo "no-atomize"  # Pre-commit runs its own file batching
            ;;
        trufflehog|gh|act|bfg|commitizen|cz-conventional-gitmoji)
            echo "no-atomize"  # These tools work on whole repos
            ;;
        coverage)
            echo "directory"  # Coverage works on directories
            ;;
        deptry)
            echo "directory"  # Dependency checking works on directories
            ;;

        # Second-tier tools with special atomization
        unittest|nose2|behave|ward)
            echo "test-function"  # Similar to pytest
            ;;

        tox|nox|invoke)
            echo "no-atomize"  # Task runners manage their own execution
            ;;

        gitleaks|safety|pip-audit)
            echo "no-atomize"  # Security scanners work on whole project
            ;;

        *)
            echo "file"  # Default to file-level atomization
            ;;
    esac
}

# Check if a runner is supported
is_supported_runner() {
    local runner="$1"
    for supported in "${SUPPORTED_RUNNERS[@]}"; do
        [[ "$runner" == "$supported" ]] && return 0
    done
    return 1
}

# Get the proper runner for a tool
get_tool_runner() {
    local tool="$1"
    local enable_second_tier="${2:-0}"

    # Check primary tools first (safely handle missing keys)
    if [[ -n "${TOOL_RUNNER_MAPPING[$tool]+x}" ]]; then
        echo "${TOOL_RUNNER_MAPPING[$tool]}"
        return 0
    fi

    # Check second-tier tools if enabled (safely handle missing keys)
    if [[ "$enable_second_tier" -eq 1 ]] && [[ -n "${SECOND_TIER_TOOLS[$tool]+x}" ]]; then
        echo "${SECOND_TIER_TOOLS[$tool]}"
        return 0
    fi

    # No runner mapping found
    return 1
}

# Check if a tool is recognized (first or second tier)
is_recognized_tool() {
    local tool="$1"
    local enable_second_tier="${2:-0}"

    # Check primary tools (safely handle missing keys)
    [[ -n "${TOOL_RUNNER_MAPPING[$tool]+x}" ]] && return 0

    # Check second-tier tools if enabled (safely handle missing keys)
    if [[ "$enable_second_tier" -eq 1 ]]; then
        [[ -n "${SECOND_TIER_TOOLS[$tool]+x}" ]] && return 0
    fi

    return 1
}

# Enforce runner for a command
enforce_runner() {
    local cmd_array=("$@")
    local tool="${cmd_array[0]}"
    local enable_second_tier="${ENABLE_SECOND_TIER:-0}"

    # Check if already using a runner
    local runner_info
    runner_info=$(detect_runner "${cmd_array[@]}")
    local current_runner=$(echo "$runner_info" | cut -d'|' -f1)

    # If already has a runner, check if it's supported
    if [[ -n "$current_runner" ]]; then
        if is_supported_runner "$current_runner"; then
            # Supported runner, return as-is
            printf '%s\n' "${cmd_array[@]}"
            return 0
        else
            # Unsupported runner (e.g., poetry, conda), return error
            return 2
        fi
    fi

    # No runner, check if tool needs one
    local proper_runner
    if proper_runner=$(get_tool_runner "$tool" "$enable_second_tier"); then
        if [[ -n "$proper_runner" ]]; then
            # Add runner to command
            echo "$proper_runner" "${cmd_array[@]}"
        else
            # Tool doesn't need a runner
            printf '%s\n' "${cmd_array[@]}"
        fi
        return 0
    fi

    # Tool not recognized
    return 1
}
