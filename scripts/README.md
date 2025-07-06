# Universal Scripts for uv-managed Python Projects

This directory contains universal bash scripts that can be used in any uv-managed Python project for sequential execution and process management.

## Scripts Overview

### Core Scripts

1. **wait_all.sh** (v3.1)
   - Executes commands and waits for all descendants to complete
   - Features: timeout, retries, JSON output, memory tracking, auto-runner selection
   - Bash 3.2+ compatible (works on macOS default bash)

2. **sequential-executor.sh**
   - Ensures only ONE process runs at a time with indefinite waiting
   - Queue-based execution with pipeline timeout
   - Integrates with wait_all.sh for atomic execution
   - Bash 3.2+ compatible

3. **make-sequential.sh**
   - Wrapper for make commands to ensure sequential execution
   - Prevents multiple make commands from spawning multiple executors
   - Global lock per project

4. **git-safe.sh**
   - Safe git wrapper preventing concurrent git operations
   - Handles pre-commit hooks and prevents deadlocks
   - Detects and cleans up stale locks

5. **memory_monitor.sh**
   - Monitors and kills processes exceeding memory limits
   - Prevents system lockup from runaway processes
   - Portable implementation (works on Linux/macOS/BSD)

### Utility Scripts

6. **install-deps.sh**
   - Automatic dependency installer for Linux/macOS/BSD
   - Detects OS and uses appropriate package manager
   - Maps generic commands to OS-specific packages

7. **test-bash-compatibility.sh**
   - Tests bash 3.2 compatibility features
   - Verifies all scripts work with macOS default bash

## Compatibility

All scripts are designed to be:
- **Bash 3.2+ compatible** (works with macOS default bash)
- **Cross-platform** (Linux, macOS, BSD)
- **Project-agnostic** (no hardcoded paths or project-specific code)
- **Self-contained** (minimal external dependencies)

## Key Fixes Applied

1. **Bash 3.2 Compatibility**
   - Replaced bash 4.0 features with 3.2-compatible alternatives
   - Used indirect expansion instead of namerefs
   - Safer eval usage where absolutely necessary

2. **Cross-platform Portability**
   - Replaced `tac` command with portable awk function
   - Added OS detection for platform-specific commands
   - Unified ps command syntax for Linux/macOS/BSD

3. **Safety Improvements**
   - Added parameter checks before accessing arguments
   - Fixed variable scoping issues
   - Improved error handling and cleanup

4. **Universal Design**
   - Removed all project-specific code
   - Made scripts work with any uv-managed Python project
   - Added automatic dependency installation

## Usage Examples

### Sequential Execution
```bash
# Run pytest sequentially
./sequential-executor.sh pytest tests/test_one.py

# Run make with sequential guarantee
./make-sequential.sh test

# Safe git operations
./git-safe.sh commit -m "Update"
```

### Process Management
```bash
# Run with timeout and retries
./wait_all.sh --timeout 300 --retry 3 -- pytest

# Monitor memory usage
./memory_monitor.sh --pid $$ --limit 4096
```

### Testing
```bash
# Test bash compatibility
./test-bash-compatibility.sh

# Install missing dependencies
./install-deps.sh
```

## Installation

1. Copy all scripts to your project's scripts directory
2. Make them executable: `chmod +x *.sh`
3. Optionally run `./install-deps.sh` to install any missing utilities

## Integration with pre-commit

These scripts integrate seamlessly with the sequential pre-commit setup described in SEQUENTIAL_PRECOMMIT_SETUP_v3.md for preventing hook explosions and ensuring atomic execution.
