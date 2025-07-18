#!/usr/bin/env bash
# -*- coding: utf-8 -*-
#
# Copyright (c) 2024-2025 Emasoft
# Licensed under the MIT License.
# See the LICENSE file in the project root for full license text.
#
# print_version.sh - Print project version from pyproject.toml
# Version: 1.0.0

set -euo pipefail

VERSION='1.0.0'

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source common functions and definitions
source "${SCRIPT_DIR}/sep_common.sh"

# Colors are now defined in sep_common.sh

# Get current version from pyproject.toml
get_current_version() {
    grep '^version = ' pyproject.toml | sed 's/version = "\(.*\)"/\1/'
}

# Main
main() {

    local current_version
    current_version=$(get_current_version)

    if [[ -n "$current_version" ]]; then
        echo -e "${BLUE}Current version: ${GREEN}${current_version}${NC}"
    else
        echo -e "${RED}Error: Could not determine version from pyproject.toml${NC}" >&2
        exit 1
    fi
}
# Handle command line arguments
case "${1:-}" in
    --help|-h)
        echo "print_version.sh v$VERSION - Print project version"
        echo "Usage: $0 [--help|--version]"
        exit 0
        ;;
    --version)
        echo "print_version.sh v$VERSION"
        exit 0
        ;;
esac

main "$@"
