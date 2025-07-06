#!/usr/bin/env bash
# install_sequential.sh - Sequential Pipeline Installation Manager
# Version: 3.0.0
#
# This script consolidates:
# - ensure-sequential.sh (setup verification)
# - test-bash-compatibility.sh (compatibility testing)
# - install-deps.sh (dependency management)
#
# Usage:
#   install_sequential.sh install  - Install and configure sequential pipeline
#   install_sequential.sh doctor   - Check system health and configuration
#   install_sequential.sh uninstall - Remove configuration (not scripts)
#
set -euo pipefail

VERSION='3.0.0'
SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Try to find project root
if git rev-parse --show-toplevel >/dev/null 2>&1; then
    PROJECT_ROOT="$(git rev-parse --show-toplevel)"
else
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
fi

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Display help message
show_help() {
    cat << EOF
install_sequential.sh v3.0.0 - Sequential Pipeline Installation Manager

USAGE:
    $SCRIPT_NAME install    Install and configure sequential pipeline
    $SCRIPT_NAME doctor     Check system health and configuration
    $SCRIPT_NAME uninstall  Remove configuration (keeps scripts)
    $SCRIPT_NAME --help     Show this help message

COMMANDS:
    install
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

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

log_success() {
    echo -e "${GREEN}✓${NC} $*"
}

log_fail() {
    echo -e "${RED}✗${NC} $*"
}

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
}

create_env_file() {
    local env_file="$PROJECT_ROOT/.env.development"

    if [ -f "$env_file" ]; then
        log_warn ".env.development already exists, backing up..."
        cp "$env_file" "${env_file}.bak"
    fi

    log_info "Creating .env.development..."
    cat > "$env_file" << 'EOF'
# Sequential Pipeline Configuration
# Generated by install_sequential.sh

# Memory limits
MEMORY_LIMIT_MB=2048    # 2GB per process
CHECK_INTERVAL=5        # Check every 5 seconds

# Timeouts
TIMEOUT=1800            # 30 minutes per command
PIPELINE_TIMEOUT=7200   # 2 hours for entire pipeline

# Debugging
VERBOSE=0               # Set to 1 for verbose output

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

# Sequential Pipeline
logs/
*.log
.env.development
.env.local

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
        "wait_all.sh"
        "sequential_queue.sh"
        "memory_monitor.sh"
        "monitor-queue.sh"
        "kill-orphans.sh"
        "install_sequential.sh"
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

    # Create 'seq' symlink in project root
    if [ ! -e "$PROJECT_ROOT/seq" ]; then
        ln -s "$SCRIPT_DIR/sequential_queue.sh" "$PROJECT_ROOT/seq"
        log_success "Created 'seq' command in project root"
    fi

    # Ensure backward compatibility symlinks exist
    cd "$SCRIPT_DIR"

    # sequential-executor.sh → sequential_queue.sh
    if [ ! -L "sequential-executor.sh" ]; then
        ln -sf sequential_queue.sh sequential-executor.sh
        log_success "Created sequential-executor.sh symlink"
    fi

    # git-safe.sh → sequential_queue.sh
    if [ ! -L "git-safe.sh" ]; then
        ln -sf sequential_queue.sh git-safe.sh
        log_success "Created git-safe.sh symlink"
    fi

    # make-sequential.sh → sequential_queue.sh
    if [ ! -L "make-sequential.sh" ]; then
        ln -sf sequential_queue.sh make-sequential.sh
        log_success "Created make-sequential.sh symlink"
    fi

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
        "wait_all.sh"
        "sequential_queue.sh"
        "memory_monitor.sh"
        "monitor-queue.sh"
        "kill-orphans.sh"
        "install_sequential.sh"
    )

    local all_good=true

    for script in "${required_scripts[@]}"; do
        if [ -f "$SCRIPT_DIR/$script" ]; then
            if [ -x "$SCRIPT_DIR/$script" ]; then
                # Check version
                local version=$(grep -E "^VERSION=" "$SCRIPT_DIR/$script" 2>/dev/null | cut -d"'" -f2)
                if [ "$version" = "3.0.0" ]; then
                    log_success "$script v$version ✓"
                else
                    log_warn "$script v$version (expected v3.0.0)"
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

    # Check symlinks
    echo -e "\n${BLUE}Convenience commands:${NC}"
    if [ -L "$PROJECT_ROOT/seq" ]; then
        log_success "'seq' command available"
    else
        log_fail "'seq' command not found"
    fi
}

doctor_test_functionality() {
    echo -e "\n${CYAN}=== Functionality Tests ===${NC}"

    # Test wait_all.sh
    if [ -x "$SCRIPT_DIR/wait_all.sh" ]; then
        if "$SCRIPT_DIR/wait_all.sh" -- echo "test" >/dev/null 2>&1; then
            log_success "wait_all.sh basic test passed"
        else
            log_fail "wait_all.sh basic test failed"
        fi
    fi

    # Test sequential_queue.sh help
    if [ -x "$SCRIPT_DIR/sequential_queue.sh" ]; then
        if "$SCRIPT_DIR/sequential_queue.sh" --help >/dev/null 2>&1; then
            log_success "sequential_queue.sh help works"
        else
            log_fail "sequential_queue.sh help failed"
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
    if [ -L "$PROJECT_ROOT/seq" ]; then
        rm -f "$PROJECT_ROOT/seq"
        log_success "Removed 'seq' symlink"
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
            echo "  ./seq -- git commit -m 'feat: update'"
            echo "  ./seq -- make test"
            echo "  ./seq -- pytest"
            ;;

        doctor)
            echo -e "${CYAN}=== Sequential Pipeline Health Check ===${NC}"
            echo "Checking installation at: $PROJECT_ROOT"

            # Run all checks
            doctor_check_bash
            doctor_check_scripts
            doctor_check_dependencies
            doctor_check_environment
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
