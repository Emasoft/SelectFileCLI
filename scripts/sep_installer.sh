#!/usr/bin/env bash
# sep_installer.sh - Sequential Execution Pipeline Installation Manager
# Version: 8.5.1
#
# CHANGELOG:
# v8.5.1:
# - Added flock installation for Linux systems (util-linux package)
# - Added flock to optional dependencies check in doctor command
# - Removed references to deprecated install-deps.sh
#
# This script consolidates:
# - ensure-sequential.sh (setup verification)
# - test-bash-compatibility.sh (compatibility testing)
# - dependency management functionality
#
# SEP is uv-centric - requires uv for Python package management
#
# Usage:
#   sep_installer.sh install  - Install and configure sequential execution pipeline
#   sep_installer.sh doctor   - Check system health and configuration
#   sep_installer.sh uninstall - Remove configuration (not scripts)
#
set -euo pipefail

VERSION='8.5.1'
SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source common functions and definitions
source "${SCRIPT_DIR}/sep_common.sh"

# Initialize common variables (sets PROJECT_ROOT)
init_sep_common

# Colors are now defined in sep_common.sh

# Display help message
show_help() {
    cat << EOF
sep_installer.sh v8.5.1 - Sequential Execution Pipeline Installation Manager

USAGE:
    $SCRIPT_NAME install    Install and configure sequential pipeline
    $SCRIPT_NAME doctor     Check system health and configuration
    $SCRIPT_NAME uninstall  Remove configuration (keeps scripts)
    $SCRIPT_NAME --help     Show this help message
    $SCRIPT_NAME --version  Show version information

REQUIREMENTS:
    SEP is uv-centric and requires:
    - uv (Python package manager) - https://docs.astral.sh/uv/
    - Python project with .venv created by uv
    - Bash 3.2 or higher

COMMANDS:
    install
        - Checks for uv and .venv (required)
        - Creates ./scripts and ./logs directories
        - Installs system dependencies (jq, gawk, etc.)
        - Creates .env.development with default settings
        - Updates .gitignore with necessary exclusions
        - Makes all scripts executable
        - Creates convenience symlinks
        - Updates pyproject.toml if it exists

        NOTE: Does NOT install git hooks or test runners (user's choice)

    doctor
        - Checks bash version (3.2+ required)
        - Verifies all scripts are present and executable
        - Checks system dependencies
        - Validates environment variables
        - Checks for old/deprecated scripts
        - Verifies script versions
        - Detects direct sep.sh calls and suggests sep_queue.sh usage
        - Tests basic functionality

    uninstall
        - Removes .env.development
        - Removes convenience symlinks
        - Cleans up environment variables
        - Removes entries from .gitignore

        NOTE: Does NOT remove scripts or documentation

EXAMPLES:
    # Fresh installation
    $SCRIPT_NAME install

    # Check system health
    $SCRIPT_NAME doctor

    # Clean uninstall
    $SCRIPT_NAME uninstall

ENVIRONMENT:
    The install command creates .env.development with:
    - MEMORY_LIMIT_MB=2048
    - CHECK_INTERVAL=5
    - TIMEOUT=1800
    - PIPELINE_TIMEOUT=7200
    - VERBOSE=0

EOF
    exit 0
}

# Calculate file hash (cross-platform)
calculate_hash() {
    local file="$1"
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$file" | cut -d' ' -f1
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$file" | cut -d' ' -f1
    else
        echo "unknown"
    fi
}

# Expected script versions and hashes
declare -A EXPECTED_VERSIONS=(
    ["sep.sh"]="8.5.0"
    ["sep_queue.sh"]="8.5.0"
    ["sep_memory_monitor.sh"]="8.5.0"
    ["sep_monitor_queue.sh"]="8.5.0"
    ["sep_kill_orphans.sh"]="8.5.0"
    ["sep_installer.sh"]="8.5.0"
    ["sep_tool_atomifier.sh"]="8.5.0"
    ["sep_common.sh"]="8.5.0"
    ["print_version.sh"]="1.0.0"
)

# Expected script SHA256 hashes (update these after any script changes)
declare -A EXPECTED_HASHES=(
    ["sep.sh"]="4a75a1c1c1838ba563737cae5a7b5be1ace62d73675f8549634807d4dbc6a3f5"
    ["sep_queue.sh"]="902b9ac5c1d27fa89dfc22b3805f1f45112c02d8a28dd3f848c4f7e4f2734635"
    ["sep_memory_monitor.sh"]="834a9fa62ca66210de144848980f30e879b8d8b58b301b23b62b9757cf5bca02"
    ["sep_monitor_queue.sh"]="12d3ce55cb67b91cdc8aae1904fc856bf432b51be7a31ceb4b245abb9c3005a6"
    ["sep_kill_orphans.sh"]="a9a9ca83e6e1ad9d461c1a7339a69c2757e4f1d98b9f8019ff18448af58facb8"
    ["sep_installer.sh"]="SELF"  # Will be calculated at runtime
    ["sep_tool_atomifier.sh"]="65bf62fbb73052f9a990fb0393adfbea677475fbef431585a7a9f961e868e573"
    ["sep_common.sh"]="955876ff9cca73900e4c60a5ea92178eeb5288ce49b5da4929e9fa08df1481ea"
    ["print_version.sh"]="216c1143d98589d73327c091b3ae41becc8d12653aa055ad6e0b0f819621479a"
)

# Logging functions are now defined in sep_common.sh

# =============================================================
# SHARED FUNCTIONS
# =============================================================

detect_os() {
    local os_type="unknown"

    if [[ -f /etc/os-release ]]; then
        # Linux
        os_type="linux"
        if grep -qi ubuntu /etc/os-release; then
            os_type="ubuntu"
        elif grep -qi debian /etc/os-release; then
            os_type="debian"
        elif grep -qi fedora /etc/os-release; then
            os_type="fedora"
        elif grep -qi centos /etc/os-release; then
            os_type="centos"
        fi
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        os_type="macos"
    elif [[ "$OSTYPE" == "freebsd"* ]]; then
        os_type="bsd"
    fi

    echo "$os_type"
}

check_bash_version() {
    local major="${BASH_VERSION%%.*}"
    local minor="${BASH_VERSION#*.}"
    minor="${minor%%.*}"

    if [ "$major" -lt 3 ] || { [ "$major" -eq 3 ] && [ "$minor" -lt 2 ]; }; then
        return 1
    fi
    return 0
}

check_command() {
    local cmd=$1
    command -v "$cmd" >/dev/null 2>&1
}

# =============================================================
# INSTALL FUNCTIONS
# =============================================================

check_uv_environment() {
    log_info "Checking uv environment..."

    # Check if uv is installed
    if ! check_command uv; then
        log_error "uv not found!"
        echo
        echo "No uv managed project folder found. SEP requires uv to work."
        echo "Do you want:"
        echo "  1) Exit the install process and install uv and create the .venv with 'uv venv' yourself"
        echo "  2) Let me initialize the project folder with 'uv init' and create the .venv with 'uv venv' for you"
        echo
        read -p "Your choice? (1, 2 or enter to exit): " choice

        case "$choice" in
            1)
                echo
                echo "Please install uv from: https://docs.astral.sh/uv/"
                echo "Then run: uv venv"
                echo "After that, run this installer again."
                exit 0
                ;;
            2)
                echo
                log_info "Installing uv..."
                curl -LsSf https://astral.sh/uv/install.sh | sh

                # Source shell config to get uv in PATH
                if [ -f "$HOME/.bashrc" ]; then
                    source "$HOME/.bashrc"
                elif [ -f "$HOME/.zshrc" ]; then
                    source "$HOME/.zshrc"
                fi

                # Check if uv is now available
                if ! check_command uv; then
                    log_error "Failed to install uv. Please install manually."
                    exit 1
                fi

                log_success "uv installed successfully"

                # Initialize project if needed
                if [ ! -f "$PROJECT_ROOT/pyproject.toml" ]; then
                    log_info "Initializing uv project..."
                    cd "$PROJECT_ROOT"
                    uv init --name "$(basename "$PROJECT_ROOT")"
                    log_success "Project initialized"
                fi

                # Create venv
                log_info "Creating .venv..."
                cd "$PROJECT_ROOT"
                uv venv
                log_success ".venv created"
                ;;
            *)
                echo "Installation cancelled."
                exit 0
                ;;
        esac
    else
        log_success "uv is installed"
    fi

    # Check if .venv exists
    if [ ! -d "$PROJECT_ROOT/.venv" ]; then
        log_warn ".venv not found"
        echo
        echo "SEP requires a uv-managed virtual environment."
        echo "Do you want me to create it with 'uv venv'? (y/N)"
        read -p "> " create_venv

        if [[ "$create_venv" =~ ^[Yy]$ ]]; then
            cd "$PROJECT_ROOT"
            uv venv
            log_success ".venv created"
        else
            echo "Please run 'uv venv' and try again."
            exit 0
        fi
    else
        log_success ".venv exists"
    fi

    # Verify it's a uv-managed venv
    if [ -f "$PROJECT_ROOT/.venv/pyvenv.cfg" ]; then
        if grep -q "uv" "$PROJECT_ROOT/.venv/pyvenv.cfg" 2>/dev/null; then
            log_success ".venv is uv-managed"
        else
            log_warn ".venv exists but may not be uv-managed"
            log_info "Consider recreating with: rm -rf .venv && uv venv"
        fi
    fi
}

install_dependencies() {
    local os_type=$(detect_os)
    log_info "Detected OS: $os_type"

    # Essential tools we need
    local tools=(jq gawk curl git)
    local missing=()

    # Check what's missing
    for tool in "${tools[@]}"; do
        if ! check_command "$tool"; then
            missing+=("$tool")
        fi
    done

    # Special handling for flock
    if ! check_command "flock"; then
        case "$os_type" in
            ubuntu|debian|fedora|centos)
                # flock is in util-linux package on Linux
                missing+=("util-linux")
                ;;
            macos)
                # flock is not available on macOS, but we have a fallback
                log_info "flock not available on macOS - sep.sh will use fallback locking"
                ;;
        esac
    fi

    if [ ${#missing[@]} -eq 0 ]; then
        log_success "All essential dependencies installed"
        return 0
    fi

    log_info "Installing missing dependencies: ${missing[*]}"

    case "$os_type" in
        macos)
            if ! check_command brew; then
                log_error "Homebrew not found. Please install from https://brew.sh"
                return 1
            fi
            brew install "${missing[@]}"
            ;;
        ubuntu|debian)
            sudo apt-get update
            sudo apt-get install -y "${missing[@]}"
            ;;
        fedora|centos)
            sudo yum install -y "${missing[@]}"
            ;;
        *)
            log_error "Unsupported OS for automatic dependency installation"
            log_info "Please manually install: ${missing[*]}"
            return 1
            ;;
    esac

    # Install uv if not present
    if ! check_command uv; then
        log_info "Installing uv (Python package manager)..."
        curl -LsSf https://astral.sh/uv/install.sh | sh
    fi

    # Install pre-commit if not present
    if ! check_command pre-commit; then
        log_info "Installing pre-commit with uv support..."
        uv tool install pre-commit --with pre-commit-uv
    fi

    log_success "Dependencies installed successfully"
}

create_directories() {
    log_info "Creating required directories..."

    # Create scripts directory if needed
    if [ ! -d "$PROJECT_ROOT/scripts" ]; then
        mkdir -p "$PROJECT_ROOT/scripts"
        log_success "Created scripts directory"
    fi

    # Create logs directory
    if [ ! -d "$PROJECT_ROOT/logs" ]; then
        mkdir -p "$PROJECT_ROOT/logs"
        log_success "Created logs directory"
    fi

    # Create sequential locks directory
    if [ ! -d "$PROJECT_ROOT/.sequential-locks" ]; then
        mkdir -p "$PROJECT_ROOT/.sequential-locks"
        log_success "Created sequential locks directory"
    fi

    # Create sep.sh lock file
    if [ ! -f "$PROJECT_ROOT/.sep.log.lock" ]; then
        touch "$PROJECT_ROOT/.sep.log.lock"
        log_success "Created sep.sh log lock file"
    fi
}

create_env_file() {
    local env_file="$PROJECT_ROOT/.env.development"

    if [ -f "$env_file" ]; then
        log_warn ".env.development already exists, backing up..."
        cp "$env_file" "${env_file}.bak"
    fi

    log_info "Creating .env.development..."
    cat > "$env_file" << EOF
# Sequential Execution Pipeline Configuration
# Generated by sep_installer.sh

# Memory limits
MEMORY_LIMIT_MB=2048    # 2GB per process
CHECK_INTERVAL=5        # Check every 5 seconds

# Timeouts
TIMEOUT=86400           # 24 hours per command
PIPELINE_TIMEOUT=86400  # 24 hours for entire pipeline

# Debugging
VERBOSE=0               # Set to 1 for verbose output

# Lock directory configuration (relative paths)
SEQUENTIAL_LOCK_BASE_DIR="./.sequential-locks"  # Project-local locks

# sep.sh lock configuration (relative paths)
WAIT_ALL_LOG_LOCK="./.sep.log.lock"  # Lock file for sep.sh logging

# Python/pytest configuration
PYTEST_MAX_WORKERS=1    # Force sequential pytest
EOF

    log_success "Created .env.development"
}

update_gitignore() {
    local gitignore="$PROJECT_ROOT/.gitignore"

    log_info "Updating .gitignore..."

    # Create if doesn't exist
    touch "$gitignore"

    # Check if our section exists
    if ! grep -q "# Sequential Pipeline" "$gitignore" 2>/dev/null; then
        cat >> "$gitignore" << 'EOF'

# Sequential Execution Pipeline
logs/
*.log
.env.development
.env.local
.sequential-locks/
.sep.log.lock

# Private documentation
CLAUDE.md
SEQUENTIAL_PRECOMMIT_SETUP_v3.md
DOCS_DEV/

# Python
__pycache__/
*.py[cod]
.coverage
.pytest_cache/
.mypy_cache/
.ruff_cache/

# Virtual environments
.venv/
venv/
EOF
        log_success "Updated .gitignore"
    else
        log_info ".gitignore already configured"
    fi
}

make_scripts_executable() {
    log_info "Making scripts executable..."

    local scripts=(
        "sep.sh"
        "sep_queue.sh"
        "sep_memory_monitor.sh"
        "sep_monitor_queue.sh"
        "sep_kill_orphans.sh"
        "sep_installer.sh"
    )

    for script in "${scripts[@]}"; do
        if [ -f "$SCRIPT_DIR/$script" ]; then
            chmod +x "$SCRIPT_DIR/$script"
            log_success "$script is executable"
        else
            log_warn "$script not found in $SCRIPT_DIR"
        fi
    done
}

create_symlinks() {
    log_info "Creating convenience symlinks..."

    # Create 'sep' symlink in project root
    if [ ! -e "$PROJECT_ROOT/sep" ]; then
        ln -s "$SCRIPT_DIR/sep_queue.sh" "$PROJECT_ROOT/sep"
        log_success "Created 'sep' command in project root"
    fi

    # No backward compatibility symlinks needed
    cd "$PROJECT_ROOT"
}

update_pyproject_toml() {
    local pyproject="$PROJECT_ROOT/pyproject.toml"

    if [ ! -f "$pyproject" ]; then
        log_info "No pyproject.toml found, skipping..."
        return 0
    fi

    log_info "Checking pyproject.toml configuration..."

    # Check if pytest configuration exists
    if ! grep -q "\[tool.pytest.ini_options\]" "$pyproject" 2>/dev/null; then
        log_info "Adding pytest configuration to pyproject.toml..."
        cat >> "$pyproject" << 'EOF'

[tool.pytest.ini_options]
addopts = "-v --strict-markers --tb=short"
timeout = 300
# Force sequential execution
workers = 1
EOF
        log_success "Added pytest configuration"
    fi
}

# =============================================================
# DOCTOR FUNCTIONS
# =============================================================

doctor_check_bash() {
    echo -e "\n${CYAN}=== Bash Compatibility ===${NC}"

    echo -n "Bash version: "
    echo "$BASH_VERSION"

    if check_bash_version; then
        log_success "Bash 3.2+ compatible"

        # Test specific features
        echo -e "\n${BLUE}Testing bash features:${NC}"

        # Array handling
        local test_array=("one" "two" "three")
        if [ ${#test_array[@]} -eq 3 ]; then
            log_success "Array declaration works"
        else
            log_fail "Array declaration failed"
        fi

        # Indirect expansion
        local var_name="test_array[@]"
        local expanded=("${!var_name}")
        if [ ${#expanded[@]} -eq 3 ]; then
            log_success "Indirect array expansion works"
        else
            log_fail "Indirect array expansion failed"
        fi

        # Arithmetic
        local result=$((5 + 3))
        if [ $result -eq 8 ]; then
            log_success "Arithmetic expansion works"
        else
            log_fail "Arithmetic expansion failed"
        fi

    else
        log_fail "Bash version too old (need 3.2+)"
        return 1
    fi
}

doctor_check_scripts() {
    echo -e "\n${CYAN}=== Script Verification ===${NC}"

    local required_scripts=(
        "sep.sh"
        "sep_queue.sh"
        "sep_memory_monitor.sh"
        "sep_monitor_queue.sh"
        "sep_kill_orphans.sh"
        "sep_installer.sh"
        "sep_tool_atomifier.sh"
        "sep_common.sh"
        "print_version.sh"
    )

    local all_good=true

    for script in "${required_scripts[@]}"; do
        if [ -f "$SCRIPT_DIR/$script" ]; then
            if [ -x "$SCRIPT_DIR/$script" ]; then
                # Check version
                local version=$(grep -E "^VERSION=" "$SCRIPT_DIR/$script" 2>/dev/null | cut -d"'" -f2)
                local expected_version="${EXPECTED_VERSIONS[$script]}"

                if [ "$version" = "$expected_version" ]; then
                    log_success "$script v$version ✓"
                else
                    log_warn "$script v$version (expected v$expected_version)"
                    all_good=false
                fi

                # Calculate and verify hash for security
                local full_hash=$(calculate_hash "$SCRIPT_DIR/$script")
                local expected_hash="${EXPECTED_HASHES[$script]}"

                if [[ "$expected_hash" == "SELF" && "$script" == "sep_installer.sh" ]]; then
                    # Skip hash verification for installer itself
                    echo "     Hash: ${full_hash:0:12}... (self)"
                elif [[ "$full_hash" == "$expected_hash" ]]; then
                    echo "     Hash: ${full_hash:0:12}... ✓"
                elif [[ "$full_hash" == "unknown" ]]; then
                    echo "     Hash: Unable to calculate"
                else
                    echo "     Hash: ${full_hash:0:12}... ${RED}✗ MISMATCH${NC}"
                    echo "     Expected: ${expected_hash:0:12}..."
                    all_good=false
                fi
            else
                log_fail "$script not executable"
                all_good=false
            fi
        else
            log_fail "$script missing"
            all_good=false
        fi
    done

    # Check for deprecated scripts
    echo -e "\n${BLUE}Checking for deprecated scripts:${NC}"
    local deprecated=(
        "ensure-sequential.sh"
        "test-bash-compatibility.sh"
        "install-deps.sh"
        "sequential-executor-v1.sh"
        "sequential-executor-v2.sh"
        "sequential-executor-strict.sh"
        "git-safe.sh"
        "sequential_exec.sh"
        "sequential_queue.sh"
        "wait_all.sh"
        "sep_wait_all.sh"
        "memory_monitor.sh"
        "monitor-queue.sh"
        "kill-orphans.sh"
        "install_sequential.sh"
        "tool_atomifier.sh"
    )

    for script in "${deprecated[@]}"; do
        if [ -f "$SCRIPT_DIR/$script" ] && [ ! -L "$SCRIPT_DIR/$script" ]; then
            log_warn "Deprecated script found: $script"
        fi
    done

    return $( [ "$all_good" = true ] && echo 0 || echo 1 )
}

doctor_check_dependencies() {
    echo -e "\n${CYAN}=== System Dependencies ===${NC}"

    local deps=(
        "bash:Bash shell"
        "git:Version control"
        "jq:JSON processor"
        "awk:Text processing"
        "curl:HTTP client"
        "grep:Text search"
        "sed:Stream editor"
        "ps:Process status"
        "kill:Process control"
        "pgrep:Process grep"
    )

    local all_good=true

    for dep in "${deps[@]}"; do
        local cmd="${dep%%:*}"
        local desc="${dep#*:}"

        if check_command "$cmd"; then
            log_success "$cmd - $desc"
        else
            log_fail "$cmd - $desc (MISSING)"
            all_good=false
        fi
    done

    # Optional dependencies
    echo -e "\n${BLUE}Optional dependencies:${NC}"
    local optional=(
        "uv:Python package manager"
        "pre-commit:Git hooks framework"
        "rg:ripgrep (fast search)"
        "fd:Fast file finder"
        "flock:File locking utility (sep.sh uses fallback if missing)"
    )

    for dep in "${optional[@]}"; do
        local cmd="${dep%%:*}"
        local desc="${dep#*:}"

        if check_command "$cmd"; then
            log_success "$cmd - $desc"
        else
            log_warn "$cmd - $desc (not installed)"
        fi
    done

    return $( [ "$all_good" = true ] && echo 0 || echo 1 )
}

doctor_check_environment() {
    echo -e "\n${CYAN}=== Environment Configuration ===${NC}"

    # Check .env.development
    if [ -f "$PROJECT_ROOT/.env.development" ]; then
        log_success ".env.development exists"

        # Check key variables
        source "$PROJECT_ROOT/.env.development"

        echo -e "\n${BLUE}Environment variables:${NC}"
        echo "  MEMORY_LIMIT_MB: ${MEMORY_LIMIT_MB:-not set}"
        echo "  CHECK_INTERVAL: ${CHECK_INTERVAL:-not set}"
        echo "  TIMEOUT: ${TIMEOUT:-not set}"
        echo "  PIPELINE_TIMEOUT: ${PIPELINE_TIMEOUT:-not set}"
        echo "  VERBOSE: ${VERBOSE:-not set}"
        echo "  SEQUENTIAL_LOCK_BASE_DIR: ${SEQUENTIAL_LOCK_BASE_DIR:-not set}"
        echo "  WAIT_ALL_LOG_LOCK: ${WAIT_ALL_LOG_LOCK:-not set}"
    else
        log_fail ".env.development missing"
    fi

    # Check directories
    echo -e "\n${BLUE}Required directories:${NC}"
    if [ -d "$PROJECT_ROOT/scripts" ]; then
        log_success "scripts/ directory exists"
    else
        log_fail "scripts/ directory missing"
    fi

    if [ -d "$PROJECT_ROOT/logs" ]; then
        log_success "logs/ directory exists"
    else
        log_fail "logs/ directory missing"
    fi

    if [ -d "$PROJECT_ROOT/.sequential-locks" ]; then
        log_success ".sequential-locks/ directory exists"
    else
        log_fail ".sequential-locks/ directory missing"
    fi

    # Check lock files
    echo -e "\n${BLUE}Lock files:${NC}"
    if [ -f "$PROJECT_ROOT/.sep.log.lock" ]; then
        log_success ".sep.log.lock exists"
    else
        log_fail ".sep.log.lock missing"
    fi

    # Check symlinks
    echo -e "\n${BLUE}Convenience commands:${NC}"
    if [ -L "$PROJECT_ROOT/sep" ]; then
        log_success "'sep' command available"
    else
        log_fail "'sep' command not found"
    fi
}

doctor_check_direct_sep_calls() {
    echo -e "\n${CYAN}=== Direct sep.sh Usage Detection ===${NC}"

    local found_issues=0
    local total_direct_calls=0

    # Files to exclude from scanning (SEP's own scripts)
    local exclude_patterns=(
        "*/sep_*.sh"
        "*/sep.sh"
        "*/scripts/sep*"
    )

    # Function to check if a file should be excluded
    should_exclude() {
        local file="$1"
        for pattern in "${exclude_patterns[@]}"; do
            if [[ "$file" == $pattern ]]; then
                return 0
            fi
        done
        # Also exclude if it's in the SEP scripts directory
        if [[ "$file" == "$SCRIPT_DIR"/* ]]; then
            return 0
        fi
        return 1
    }

    # Function to scan a file for direct sep.sh calls
    scan_file_for_sep_calls() {
        local file="$1"
        local file_type="$2"
        local found_in_file=0

        # Skip if file doesn't exist or is not readable
        [[ ! -r "$file" ]] && return 0

        # Skip if should be excluded
        should_exclude "$file" && return 0

        # Different patterns to search for based on file type
        local patterns=(
            "sep\.sh"
            "\./sep\.sh"
            "scripts/sep\.sh"
            "\${.*}/sep\.sh"
            "sep\.sh\s+--"
        )

        local line_num=0
        while IFS= read -r line; do
            ((line_num++))
            for pattern in "${patterns[@]}"; do
                if echo "$line" | grep -qE "$pattern" 2>/dev/null; then
                    # Skip comments
                    if [[ "$file_type" == "shell" ]] && [[ "$line" =~ ^[[:space:]]*# ]]; then
                        continue
                    fi
                    if [[ "$file_type" == "yaml" ]] && [[ "$line" =~ ^[[:space:]]*# ]]; then
                        continue
                    fi

                    if [[ $found_in_file -eq 0 ]]; then
                        echo -e "\n${YELLOW}Found in $file:${NC}"
                        found_in_file=1
                        ((found_issues++))
                    fi
                    echo "  Line $line_num: $(echo "$line" | sed 's/^[[:space:]]*//' | head -c 80)"
                    ((total_direct_calls++))
                    break
                fi
            done
        done < "$file"

        return $found_in_file
    }

    # Scan shell scripts
    echo -e "\n${BLUE}Scanning shell scripts...${NC}"
    while IFS= read -r -d '' script; do
        scan_file_for_sep_calls "$script" "shell"
    done < <(find "$PROJECT_ROOT" -name "*.sh" -type f -print0 2>/dev/null)

    # Scan Makefiles
    echo -e "\n${BLUE}Scanning Makefiles...${NC}"
    for makefile in "$PROJECT_ROOT/Makefile" "$PROJECT_ROOT/makefile" "$PROJECT_ROOT/GNUmakefile"; do
        [[ -f "$makefile" ]] && scan_file_for_sep_calls "$makefile" "makefile"
    done

    # Scan GitHub workflows
    echo -e "\n${BLUE}Scanning GitHub workflows...${NC}"
    if [[ -d "$PROJECT_ROOT/.github/workflows" ]]; then
        while IFS= read -r -d '' workflow; do
            scan_file_for_sep_calls "$workflow" "yaml"
        done < <(find "$PROJECT_ROOT/.github/workflows" -name "*.yml" -o -name "*.yaml" -type f -print0 2>/dev/null)
    fi

    # Scan git hooks
    echo -e "\n${BLUE}Scanning git hooks...${NC}"
    if [[ -d "$PROJECT_ROOT/.git/hooks" ]]; then
        for hook in "$PROJECT_ROOT/.git/hooks"/*; do
            if [[ -f "$hook" && -x "$hook" && ! "$hook" =~ \.sample$ ]]; then
                scan_file_for_sep_calls "$hook" "shell"
            fi
        done
    fi

    # Scan package.json scripts
    echo -e "\n${BLUE}Scanning package.json scripts...${NC}"
    if [[ -f "$PROJECT_ROOT/package.json" ]]; then
        if command -v jq >/dev/null 2>&1; then
            local scripts=$(jq -r '.scripts | to_entries[] | "\(.key): \(.value)"' "$PROJECT_ROOT/package.json" 2>/dev/null || true)
            if [[ -n "$scripts" ]]; then
                local found_in_package=0
                while IFS= read -r script_line; do
                    if echo "$script_line" | grep -qE "sep\.sh|./sep\.sh|scripts/sep\.sh" 2>/dev/null; then
                        if [[ $found_in_package -eq 0 ]]; then
                            echo -e "\n${YELLOW}Found in package.json scripts:${NC}"
                            found_in_package=1
                            ((found_issues++))
                        fi
                        echo "  $script_line"
                        ((total_direct_calls++))
                    fi
                done <<< "$scripts"
            fi
        else
            log_warn "jq not installed - skipping package.json scan"
        fi
    fi

    # Scan pre-commit configuration
    echo -e "\n${BLUE}Scanning pre-commit configuration...${NC}"
    if [[ -f "$PROJECT_ROOT/.pre-commit-config.yaml" ]]; then
        scan_file_for_sep_calls "$PROJECT_ROOT/.pre-commit-config.yaml" "yaml"
    fi

    # Summary and recommendations
    echo -e "\n${CYAN}=== Direct sep.sh Call Summary ===${NC}"
    if [[ $found_issues -eq 0 ]]; then
        log_success "No direct sep.sh calls found"
    else
        log_warn "Found $total_direct_calls direct sep.sh calls in $found_issues files"

        echo -e "\n${CYAN}Recommendations:${NC}"
        echo "1. Replace direct sep.sh calls with sep_queue.sh for better control"
        echo "2. Use './sep' symlink instead of './scripts/sep_queue.sh' for convenience"
        echo "3. For series of commands, batch them with sep_queue.sh:"
        echo "   Example: sep_queue.sh -- ruff check && sep_queue.sh -- mypy && sep_queue.sh --queue-start"
        echo "4. For git hooks, consider using sep_queue.sh with --queue-start"
        echo "5. In CI/CD workflows, use sep_queue.sh for automatic atomification"

        # Check for patterns that suggest batch usage
        if [[ $total_direct_calls -gt 3 ]]; then
            echo -e "\n${YELLOW}Note:${NC} Multiple sep.sh calls detected. Consider using sep_queue.sh"
            echo "for better queue management and automatic command atomification."
        fi
    fi
}

doctor_test_functionality() {
    echo -e "\n${CYAN}=== Functionality Tests ===${NC}"

    # Test sep.sh
    if [ -x "$SCRIPT_DIR/sep.sh" ]; then
        if "$SCRIPT_DIR/sep.sh" -- echo "test" >/dev/null 2>&1; then
            log_success "sep.sh basic test passed"
        else
            log_fail "sep.sh basic test failed"
        fi
    fi

    # Test sep_queue.sh help
    if [ -x "$SCRIPT_DIR/sep_queue.sh" ]; then
        if "$SCRIPT_DIR/sep_queue.sh" --help >/dev/null 2>&1; then
            log_success "sep_queue.sh help works"
        else
            log_fail "sep_queue.sh help failed"
        fi
    fi

    # Check lock directories
    echo -e "\n${BLUE}Lock directories:${NC}"
    local project_hash=$(echo "$PROJECT_ROOT" | shasum | cut -d' ' -f1 | head -c 8)
    local lock_dir="/tmp/seq-exec-${project_hash}"

    if [ -d "$lock_dir" ]; then
        log_warn "Lock directory exists: $lock_dir"
        if [ -f "$lock_dir/queue.txt" ]; then
            local queue_size=$(wc -l < "$lock_dir/queue.txt" 2>/dev/null || echo 0)
            if [ "$queue_size" -gt 0 ]; then
                log_warn "Queue has $queue_size entries"
            fi
        fi
    else
        log_success "No stale locks found"
    fi
}

# =============================================================
# UNINSTALL FUNCTIONS
# =============================================================

uninstall_configuration() {
    log_info "Removing configuration files..."

    # Remove .env.development
    if [ -f "$PROJECT_ROOT/.env.development" ]; then
        rm -f "$PROJECT_ROOT/.env.development"
        log_success "Removed .env.development"
    fi

    # Remove symlinks
    if [ -L "$PROJECT_ROOT/sep" ]; then
        rm -f "$PROJECT_ROOT/sep"
        log_success "Removed 'sep' symlink"
    fi

    # Clean up .gitignore
    if [ -f "$PROJECT_ROOT/.gitignore" ]; then
        # Remove our section
        if grep -q "# Sequential Pipeline" "$PROJECT_ROOT/.gitignore"; then
            log_info "Cleaning .gitignore..."
            # Create temp file without our section
            awk '/# Sequential Pipeline/{flag=1} /^$/{if(flag) flag=0} !flag' "$PROJECT_ROOT/.gitignore" > "$PROJECT_ROOT/.gitignore.tmp"
            mv "$PROJECT_ROOT/.gitignore.tmp" "$PROJECT_ROOT/.gitignore"
            log_success "Cleaned .gitignore"
        fi
    fi

    # Remove backward compatibility symlinks
    cd "$SCRIPT_DIR"
    for link in sequential-executor.sh git-safe.sh make-sequential.sh; do
        if [ -L "$link" ]; then
            rm -f "$link"
            log_success "Removed $link symlink"
        fi
    done

    log_info "Configuration removed (scripts and documentation preserved)"
}

# =============================================================
# MAIN EXECUTION
# =============================================================

main() {
    case "${1:-}" in
        install)
            echo -e "${CYAN}=== Sequential Pipeline Installation ===${NC}"
            echo "Installing to: $PROJECT_ROOT"
            echo

            # Check uv environment first (SEP is uv-centric)
            check_uv_environment || exit 1

            # Run installation steps
            install_dependencies || exit 1
            create_directories
            create_env_file
            update_gitignore
            make_scripts_executable
            create_symlinks
            update_pyproject_toml

            echo
            echo -e "${GREEN}Installation complete!${NC}"
            echo
            echo "Next steps:"
            echo "1. Review .env.development and adjust settings"
            echo "2. Run '$SCRIPT_NAME doctor' to verify installation"
            echo "3. Set up git hooks if desired (see documentation)"
            echo
            echo "Quick start:"
            echo "  ./sep -- git commit -m 'feat: update'"
            echo "  ./sep -- make test"
            echo "  ./sep -- pytest"
            ;;

        doctor)
            echo -e "${CYAN}=== Sequential Pipeline Health Check ===${NC}"
            echo "Checking installation at: $PROJECT_ROOT"

            # Run all checks
            doctor_check_bash
            doctor_check_scripts
            doctor_check_dependencies
            doctor_check_environment
            doctor_check_direct_sep_calls
            doctor_test_functionality

            echo
            echo -e "${CYAN}=== Summary ===${NC}"
            echo "Run '$SCRIPT_NAME install' to fix any issues"
            ;;

        uninstall)
            echo -e "${CYAN}=== Sequential Pipeline Uninstall ===${NC}"
            echo "Removing configuration from: $PROJECT_ROOT"
            echo

            read -p "This will remove configuration files. Continue? (y/N) " -n 1 -r
            echo

            if [[ $REPLY =~ ^[Yy]$ ]]; then
                uninstall_configuration
                echo
                echo -e "${GREEN}Uninstall complete!${NC}"
                echo "Scripts and documentation have been preserved in $SCRIPT_DIR"
            else
                echo "Uninstall cancelled"
            fi
            ;;

        --help|-h|help)
            show_help
            ;;

        --version)
            echo "sep_installer.sh v$VERSION"
            exit 0
            ;;

        *)
            echo "Error: Unknown command '${1:-}'"
            echo "Usage: $SCRIPT_NAME {install|doctor|uninstall|--help}"
            exit 1
            ;;
    esac
}

# Check for minimum bash version first
if ! check_bash_version; then
    log_error "This script requires bash 3.2 or higher"
    log_error "Current version: $BASH_VERSION"
    exit 1
fi

# Run main function
main "$@"
