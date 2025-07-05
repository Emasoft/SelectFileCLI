#!/bin/bash
# -*- coding: utf-8 -*-
#
# Copyright (c) 2024-2025 Emasoft
# Licensed under the MIT License.
# See the LICENSE file in the project root for full license text.
#

# Get current version from pyproject.toml
get_current_version() {
    grep '^version = ' pyproject.toml | sed 's/version = "\(.*\)"/\1/'
}

# Main
main() {

    local current_version=$(get_current_version)

    echo -e "${BLUE}Current version: ${current_version}${NC}"



}
main "$@"
