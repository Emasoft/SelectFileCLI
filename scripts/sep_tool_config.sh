#!/usr/bin/env bash
# sep_tool_config.sh - Comprehensive tool configuration for atomification
# Version: 8.4.0
#
# This script contains detailed configuration for all supported tools including:
# - Command syntax patterns
# - Ignore file formats and locations
# - File extension mappings
# - Special atomization rules
#

# Tool ignore file configurations
declare -A TOOL_IGNORE_FILES=(
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
)

# Tool-specific ignore patterns (in addition to ignore files)
declare -A TOOL_BUILTIN_IGNORES=(
    ["ruff"]="__pycache__:*.pyc:.venv:venv:env:.git:.pytest_cache:.mypy_cache:.ruff_cache"
    ["mypy"]="__pycache__:*.pyc:.venv:venv:env:.git:.pytest_cache:.mypy_cache"
    ["pytest"]="__pycache__:*.pyc:.venv:venv:env:.git:.pytest_cache:build:dist"
    ["eslint"]="node_modules:.git:dist:build:coverage:.next:.nuxt"
    ["prettier"]="node_modules:.git:dist:build:coverage:.next:.nuxt:*.min.js:*.min.css"
    ["yamllint"]=".git:node_modules:vendor"
    ["shellcheck"]=".git"
    ["*"]=".git:.svn:.hg"
)

# Tool command patterns for detection
declare -A TOOL_PATTERNS=(
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

    # Get builtin ignores
    local builtin="${TOOL_BUILTIN_IGNORES[$tool]:-${TOOL_BUILTIN_IGNORES['*']}}"
    IFS=':' read -ra builtin_array <<< "$builtin"
    all_patterns+=("${builtin_array[@]}")

    # Get ignore files for this tool
    local ignore_files="${TOOL_IGNORE_FILES[$tool]:-${TOOL_IGNORE_FILES['*']}}"
    IFS=':' read -ra files_array <<< "$ignore_files"

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
        *)
            echo "file"  # Default to file-level atomization
            ;;
    esac
}
