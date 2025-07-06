#!/usr/bin/env bash
# install-deps.sh - Automatic dependency installer for scripts
#
# This script provides functions to automatically install missing
# dependencies on Linux, macOS, and BSD systems
#
set -euo pipefail

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
