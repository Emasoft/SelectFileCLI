#!/bin/bash
# -*- coding: utf-8 -*-
#
# Copyright (c) 2024-2025 Emasoft
# Licensed under the MIT License.
# See the LICENSE file in the project root for full license text.
#

# HERE IS THE CHANGELOG FOR THIS VERSION OF THE FILE:
# - Created bump-version.sh script
# - Supports major, minor, and patch version bumps
# - Updates pyproject.toml automatically
# - Shows current and new versions
#

set -euo pipefail

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

# Get current version from pyproject.toml
get_current_version() {
    grep '^version = ' pyproject.toml | sed 's/version = "\(.*\)"/\1/'
}

# Parse version components
parse_version() {
    local version=$1
    IFS='.' read -r major minor patch <<< "$version"
    echo "$major $minor $patch"
}

# Show usage
usage() {
    echo "Usage: $0 [major|minor|patch]"
    echo ""
    echo "Examples:"
    echo "  $0 patch  # 0.3.0 -> 0.3.1"
    echo "  $0 minor  # 0.3.0 -> 0.4.0"
    echo "  $0 major  # 0.3.0 -> 1.0.0"
    exit 1
}

# Main
main() {
    if [ $# -ne 1 ]; then
        usage
    fi

    local bump_type=$1
    local current_version=$(get_current_version)

    echo -e "${BLUE}Current version: ${current_version}${NC}"

    # Parse current version
    read -r major minor patch <<< $(parse_version "$current_version")

    # Calculate new version
    case "$bump_type" in
        major)
            major=$((major + 1))
            minor=0
            patch=0
            ;;
        minor)
            minor=$((minor + 1))
            patch=0
            ;;
        patch)
            patch=$((patch + 1))
            ;;
        *)
            echo -e "${RED}Error: Invalid bump type '$bump_type'${NC}"
            usage
            ;;
    esac

    local new_version="${major}.${minor}.${patch}"
    echo -e "${GREEN}New version: ${new_version}${NC}"

    # Update pyproject.toml
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        sed -i '' "s/^version = \".*\"/version = \"${new_version}\"/" pyproject.toml
    else
        # Linux
        sed -i "s/^version = \".*\"/version = \"${new_version}\"/" pyproject.toml
    fi

    echo -e "${GREEN}✅ Version updated in pyproject.toml${NC}"
    echo ""
    echo -e "${YELLOW}Next steps:${NC}"
    echo "1. Review changes: git diff pyproject.toml"
    echo "2. Commit: git add pyproject.toml && git commit -m \"chore: bump version to ${new_version}\""
    echo "3. Tag: git tag v${new_version}"
    echo "4. Push: git push && git push --tags"
}

main "$@"
