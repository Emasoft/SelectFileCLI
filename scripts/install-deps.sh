#!/usr/bin/env bash
# install-deps.sh - Automatic dependency installer for scripts
# Version: 3.0.0
#
# This script provides functions to automatically install missing
# dependencies on Linux, macOS, and BSD systems
#
set -euo pipefail

VERSION='3.0.0'

# Display help message
show_help() {
    cat << 'EOF'
install-deps.sh v3.0.0 - Cross-platform dependency installer

USAGE:
    install-deps.sh [COMMAND] [DEPS...]
    install-deps.sh --help

COMMANDS:
    check DEPS...     Check if dependencies are installed
    install DEPS...   Install missing dependencies
    ensure-coreutils  Ensure GNU coreutils are available
    detect-os         Show detected operating system

    If no command is given, 'install' is assumed.

EXAMPLES:
    # Install multiple dependencies
    install-deps.sh jq ripgrep fd

    # Check if tools are installed
    install-deps.sh check git make gcc

    # Ensure GNU coreutils on macOS/BSD
    install-deps.sh ensure-coreutils

    # Detect operating system
    install-deps.sh detect-os

SUPPORTED SYSTEMS:
    - macOS (via Homebrew)
    - Debian/Ubuntu (via apt)
    - Red Hat/CentOS (via yum)
    - Alpine Linux (via apk)
    - Arch Linux (via pacman)
    - FreeBSD/OpenBSD (via pkg)

PACKAGE MAPPINGS:
    Some commands map to different package names:
    - tac → coreutils (on macOS/BSD)
    - rg → ripgrep
    - fd → fd-find (on Debian)

FUNCTIONS EXPORTED:
    When sourced, exports these functions:
    - detect_os()
    - command_exists()
    - install_package()
    - get_package_name()
    - install_missing_deps()
    - ensure_coreutils()

EOF
    exit 0
}

# Check if script is being sourced or executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Script is being executed directly
    if [[ $# -eq 0 ]] || [[ "$1" == "--help" ]] || [[ "$1" == "-h" ]]; then
        show_help
    fi
fi

# Detect OS type
detect_os() {
    case "$(uname -s)" in
        Darwin)
            echo "macos"
            ;;
        Linux)
            if [ -f /etc/debian_version ]; then
                echo "debian"
            elif [ -f /etc/redhat-release ]; then
                echo "redhat"
            elif [ -f /etc/alpine-release ]; then
                echo "alpine"
            elif [ -f /etc/arch-release ]; then
                echo "arch"
            else
                echo "linux-unknown"
            fi
            ;;
        *BSD)
            echo "bsd"
            ;;
        *)
            echo "unknown"
            ;;
    esac
}

# Check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Install a package based on OS
install_package() {
    local package=$1
    local os_type=$(detect_os)

    echo "Installing $package on $os_type..."

    case "$os_type" in
        macos)
            if ! command_exists brew; then
                echo "ERROR: Homebrew not installed. Please install from https://brew.sh" >&2
                return 1
            fi
            brew install "$package"
            ;;
        debian)
            sudo apt-get update && sudo apt-get install -y "$package"
            ;;
        redhat)
            sudo yum install -y "$package"
            ;;
        alpine)
            sudo apk add --no-cache "$package"
            ;;
        arch)
            sudo pacman -S --noconfirm "$package"
            ;;
        bsd)
            sudo pkg install -y "$package"
            ;;
        *)
            echo "ERROR: Unsupported OS for automatic installation" >&2
            return 1
            ;;
    esac
}

# Map generic command names to OS-specific package names
get_package_name() {
    local cmd=$1
    local os_type=$(detect_os)

    # Special mappings for different OS package names
    case "$cmd:$os_type" in
        # GNU coreutils on macOS/BSD
        tac:macos|tac:bsd)
            echo "coreutils"
            ;;
        # ripgrep has different names
        rg:*)
            echo "ripgrep"
            ;;
        # fd-find
        fd:debian)
            echo "fd-find"
            ;;
        fd:*)
            echo "fd"
            ;;
        # Default: use command name as package name
        *)
            echo "$cmd"
            ;;
    esac
}

# Install missing dependencies
install_missing_deps() {
    local deps=("$@")
    local missing=()
    local dep

    # Check which dependencies are missing
    for dep in "${deps[@]}"; do
        if ! command_exists "$dep"; then
            missing+=("$dep")
        fi
    done

    if [ ${#missing[@]} -eq 0 ]; then
        return 0
    fi

    echo "Missing dependencies: ${missing[*]}"
    echo "Attempting automatic installation..."

    local failed=()
    for dep in "${missing[@]}"; do
        local package=$(get_package_name "$dep")
        if ! install_package "$package"; then
            failed+=("$dep")
        fi
    done

    if [ ${#failed[@]} -gt 0 ]; then
        echo "ERROR: Failed to install: ${failed[*]}" >&2
        echo "Please install these manually" >&2
        return 1
    fi

    echo "All dependencies installed successfully"
    return 0
}

# Ensure coreutils commands are available on macOS/BSD
ensure_coreutils() {
    local os_type=$(detect_os)

    case "$os_type" in
        macos|bsd)
            # Check if GNU coreutils is installed
            if command_exists gtac; then
                # Create aliases for GNU versions
                alias tac='gtac'
                alias seq='gseq'
                alias readlink='greadlink'
                alias realpath='grealpath'
            elif ! command_exists tac; then
                echo "Installing GNU coreutils for compatibility..."
                install_package "coreutils"
                # After installation, set up aliases
                if command_exists gtac; then
                    alias tac='gtac'
                    alias seq='gseq'
                    alias readlink='greadlink'
                    alias realpath='grealpath'
                fi
            fi
            ;;
    esac
}

# Export functions for use by other scripts
export -f detect_os
export -f command_exists
export -f install_package
export -f get_package_name
export -f install_missing_deps
export -f ensure_coreutils

# Main execution when run as script
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Parse command line
    case "${1:-install}" in
        check)
            shift
            missing=()
            for dep in "$@"; do
                if ! command_exists "$dep"; then
                    missing+=("$dep")
                fi
            done
            if [ ${#missing[@]} -eq 0 ]; then
                echo "All dependencies are installed"
                exit 0
            else
                echo "Missing: ${missing[*]}"
                exit 1
            fi
            ;;
        install)
            shift
            install_missing_deps "$@"
            ;;
        ensure-coreutils)
            ensure_coreutils
            ;;
        detect-os)
            echo "Detected OS: $(detect_os)"
            ;;
        *)
            echo "Unknown command: $1"
            echo "Run '$0 --help' for usage"
            exit 1
            ;;
    esac
fi
