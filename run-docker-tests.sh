#!/bin/bash
# -*- coding: utf-8 -*-
#
# Copyright (c) 2024-2025 Emasoft
# Licensed under the MIT License.
# See the LICENSE file in the project root for full license text.
#

# HERE IS THE CHANGELOG FOR THIS VERSION OF THE FILE:
# - Created run-docker-tests.sh script
# - Supports multiple test profiles
# - Includes cleanup functionality
# - Color-coded output for results
#

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default profile
PROFILE=${1:-test}

# Function to print colored output
print_status() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# Function to cleanup Docker resources
cleanup_docker() {
    print_status "$YELLOW" "Cleaning up Docker resources..."

    # Stop and remove containers
    docker-compose --profile "$PROFILE" down -v 2>/dev/null || true
    docker-compose -f docker-compose.ci.yml down -v 2>/dev/null || true

    # Remove dangling images
    docker image prune -f

    # Clean build cache (optional, commented out by default)
    # docker builder prune -f

    print_status "$GREEN" "Docker cleanup completed!"
}

# Trap to ensure cleanup on exit
trap cleanup_docker EXIT

# Main execution
main() {
    print_status "$BLUE" "=== SelectFileCLI Docker Testing ==="
    print_status "$BLUE" "Profile: $PROFILE"
    echo

    case "$PROFILE" in
        test)
            print_status "$YELLOW" "Running tests in Docker..."
            ./scripts/sequential_queue.sh --timeout 7200 -- docker-compose --profile test up --build --abort-on-container-exit
            ;;

        lint)
            print_status "$YELLOW" "Running linters in Docker..."
            ./scripts/sequential_queue.sh --timeout 7200 -- docker-compose --profile lint up --build --abort-on-container-exit
            ;;

        build)
            print_status "$YELLOW" "Building package in Docker..."
            ./scripts/sequential_queue.sh --timeout 3600 -- docker-compose --profile build up --build --abort-on-container-exit
            ;;

        prod)
            print_status "$YELLOW" "Testing production image..."
            ./scripts/sequential_queue.sh --timeout 3600 -- docker-compose --profile prod up --build --abort-on-container-exit
            ;;

        dev)
            print_status "$YELLOW" "Starting development shell..."
            ./scripts/sequential_queue.sh --timeout 86400 -- docker-compose --profile dev run --rm dev
            ;;

        ci)
            print_status "$YELLOW" "Running CI tests..."
            ./scripts/sequential_queue.sh --timeout 7200 -- docker-compose -f docker-compose.ci.yml up --build test-ci lint-ci build-ci --abort-on-container-exit
            ;;

        all)
            print_status "$YELLOW" "Running all tests..."
            for p in test lint build prod; do
                print_status "$BLUE" "Running profile: $p"
                ./scripts/sequential_queue.sh --timeout 7200 -- docker-compose --profile "$p" up --build --abort-on-container-exit
            done
            ;;

        clean)
            # Just run cleanup
            exit 0
            ;;

        *)
            print_status "$RED" "Unknown profile: $PROFILE"
            echo "Usage: $0 [test|lint|build|prod|dev|ci|all|clean]"
            exit 1
            ;;
    esac

    print_status "$GREEN" "✅ Docker tests completed successfully!"
}

# Run main function
main
