# Sequential Execution Pipeline Setup Guide v8.6.0

A comprehensive solution for preventing process explosions, memory exhaustion, and system lockups during development operations.

**UV-centric for Python projects** - All paths are relative to your project root directory. SEP requires uv (https://docs.astral.sh/uv/) as the primary Python package manager.

## 🎯 Core Benefits

- **UV-Centric Design**: Built around uv for modern Python dependency management
- **Runner Enforcement**: Automatically adds proper runners (uv, pipx, pnpm, go, npx) to commands

- **Process Control**: Prevents concurrent process explosions with queue-based execution
- **Memory Safety**: Real-time monitoring and enforcement of memory limits
- **Atomic Operations**: Complete subprocess tracking and cleanup guaranteed
- **Git Safety**: Serialized git operations prevent corruption and conflicts
- **Universal Scripts**: All scripts work across Linux, macOS, and BSD systems
- **Detailed Logging**: Every operation tracked with timestamps, memory usage, and exit codes

## 🏗️ Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    User Command                             │
└────────────────────┬───────────────────────────────────────┘
                     ▼
┌─────────────────────────────────────────────────────────────┐
│            sep_queue.sh (Queue Manager) v8.6.0             │
│  • Queue management & run tracking                          │
│  • Lock enforcement with .sequential-locks                  │
│  • Automatic command atomification                          │
│  • GitHub-style run/job tracking                           │
│  • Runner enforcement (uv, pipx, pnpm, go, npx)            │
│  • Second-tier tool support (opt-in)                       │
└────────────────────┬───────────────────────────────────────┘
                     ▼
┌─────────────────────────────────────────────────────────────┐
│            sep.sh (Atomic Execution Unit) v8.6.0           │
│  • Process group isolation                                  │
│  • Complete cleanup with lock file support                  │
│  • Real-time logging with atomic writes                    │
│  • Memory tracking & exit code propagation                  │
│  • Fallback locking for macOS compatibility                │
└────────────────────┬───────────────────────────────────────┘
                     ▼
┌─────────────────────────────────────────────────────────────┐
│              Actual Command                                 │
│  • Runs in isolated process group                           │
│  • Monitored by sep_memory_monitor.sh                      │
│  • All descendants tracked                                  │
└─────────────────────────────────────────────────────────────┘
```

## 📋 Quick Install

```bash
# 1. Clone or download scripts to your project
mkdir -p scripts
cd scripts
# Copy all *.sh files from the sequential pipeline repository
chmod +x *.sh
cd ..

# 2. Run the automated installer
./scripts/sep_installer.sh install

# 3. Verify installation
./scripts/sep_installer.sh doctor

# 4. Install pre-commit hooks
pre-commit install
pre-commit install --hook-type pre-push
```

## 📦 Essential Scripts

### Core Execution Scripts (All v8.6.0)

#### 1. `sep_queue.sh` - Queue Manager
**Purpose**: Manages execution queue with GitHub-style run tracking.

**Key Features**:
- Queue-based execution (one command at a time)
- Automatic command atomification (breaks down commands to file-level)
- Run tracking with unique IDs (like GitHub runs)
- Lock directory: `.sequential-locks/`
- Detailed logging with job tracking
- **v8.5.0**: Runner enforcement (automatically adds uv run, pipx run, etc.)
- **v8.5.0**: --dont_enforce_runners flag to disable runner enforcement
- **v8.5.0**: --only_verified flag to skip unrecognized commands
- **v8.5.0**: --enable-second-tier flag for less-trusted tools
- **v8.5.1**: Fixed race condition preventing multiple concurrent instances
- **v8.6.0**: Version consistency across all SEP scripts

**Usage**:
```bash
# Add commands to queue
./seq -- git commit -m "feat: update"
./seq -- pytest tests/
./seq -- ruff format src/

# Queue management
./scripts/sep_queue.sh --queue-start    # Start processing
./scripts/sep_queue.sh --queue-status   # Check status
./scripts/sep_queue.sh --queue-stop     # Stop processing

# View runs (GitHub-style)
./scripts/sep_queue.sh run list          # List all runs
./scripts/sep_queue.sh run view RUN_ID   # View specific run
./scripts/sep_queue.sh run watch RUN_ID  # Watch run in real-time

# New v8.5.0 options
./seq --dont_enforce_runners -- python script.py  # Don't auto-add runners
./seq --only_verified -- ruff check              # Skip unrecognized tools
./seq --enable-second-tier -- bandit src/        # Enable second-tier tools
```

#### 2. `sep.sh` - Atomic Process Manager
**Purpose**: Executes individual commands with complete cleanup (like GitHub jobs).

**Key Features**:
- Process group isolation
- Lock file for atomic logging: `.sep.log.lock`
- Real-time logging with flock support
- Complete descendant tracking
- Memory monitoring per process
- `--version` option for version checking
- **v8.5.0**: Fallback locking for macOS when flock unavailable
- **v8.6.0**: Version consistency across all SEP scripts

**Usage**:
```bash
# Direct execution (usually called by sep_queue.sh)
./scripts/sep.sh -- python script.py
./scripts/sep.sh --timeout 300 --retry 3 -- pytest
./scripts/sep.sh --json -- npm install
./scripts/sep.sh --version  # Show version
```

#### 3. `sep_memory_monitor.sh` - Memory Guardian
**Purpose**: Monitors and enforces memory limits.

**Features**:
- Real-time memory monitoring
- Process group tracking
- Automatic termination of memory-exceeding processes
- **v8.6.0**: Version consistency across all SEP scripts

**Usage**:
```bash
# Usually invoked automatically by sep.sh
./scripts/sep_memory_monitor.sh --pid $$ --limit 2048 --interval 5
./scripts/sep_memory_monitor.sh --version  # Show version
```

### Setup and Utility Scripts

#### 4. `sep_installer.sh` - Installation Manager
**Purpose**: Automated setup, configuration, and health checks.

**Features**:
- Creates all required directories and lock files
- Generates `.env.development` with proper configuration
- Updates `.gitignore` appropriately
- Health check mode with version verification
- Calculates script hashes for integrity checking
- **v8.5.0**: UV-centric installation - checks for uv and .venv
- **v8.5.0**: Offers to install uv and initialize project if missing
- **v8.5.0**: Doctor detects direct sep.sh calls and suggests sep_queue.sh
- **v8.5.1**: Installs flock on Linux systems where available
- **v8.6.0**: Version consistency across all SEP scripts

**Usage**:
```bash
./scripts/sep_installer.sh install    # Full setup
./scripts/sep_installer.sh doctor     # Health check
./scripts/sep_installer.sh uninstall  # Remove config
./scripts/sep_installer.sh --version  # Show version
```

#### 5. `sep_tool_atomifier.sh` - Command Atomizer
**Purpose**: Breaks down tool commands to file-level operations.

**Features**:
- Intelligent pytest test atomization (individual test functions)
- File-by-file processing for linters
- Snapshot test detection for pytest via `sep_detect_snapshot_tests.py`
- Tool-specific configurations
- **v8.6.0**: Sources sep_common.sh for consistency
- **v8.6.0**: Version consistency across all SEP scripts

**Test Function Atomization**:
- **pytest**: Always atomized to individual test functions
  - Detects `::` syntax and avoids double-atomization
  - Handles `-k` pattern matching by disabling atomization
  - Intelligent snapshot test detection via `sep_detect_snapshot_tests.py`
- **unittest**: Atomized to test methods when `--enable-second-tier` is used (otherwise no atomization)
- **Other test runners** (nose2, ward, behave): No atomization (safety: no implementation)

#### 6. `sep_monitor_queue.sh` - Queue Monitor
**Purpose**: Real-time visual monitoring of execution queue.

**Features**:
- Live queue status updates
- Process and memory information
- Orphan process detection
- Interactive controls (Q to clear queue, K to kill all)
- `--version` option for version checking
- **v8.6.0**: Version consistency across all SEP scripts

#### 7. `sep_kill_orphans.sh` - Emergency Cleanup
**Purpose**: Clean up orphaned processes and stale locks.

**Features**:
- Finds processes with parent PID = 1
- Safe cleanup with --dry-run option
- Removes stale lock files
- `--version` option for version checking
- **v8.6.0**: Version consistency across all SEP scripts

#### 8. `sep_common.sh` - Shared Functions
**Purpose**: Common functions and definitions used by all SEP scripts.

**Features**:
- Color definitions
- Project root detection
- Lock hash generation
- Shared utility functions
- **v8.6.0**: Version consistency across all SEP scripts

#### 9. `sep_tool_config.sh` - Tool Configuration
**Purpose**: Comprehensive tool configuration for atomification.

**Features**:
- Tool to runner mappings
- File extension configurations
- Ignore patterns for tools
- Second-tier tool definitions
- **v8.6.0**: Added VERSION variable and sep_common.sh sourcing
- **v8.6.0**: Version consistency across all SEP scripts

#### 10. `sep_detect_snapshot_tests.py` - Snapshot Test Detector
**Purpose**: Detects which test functions use snapshot testing.

**Features**:
- AST-based analysis of Python test files
- Identifies tests using snap_compare, snapshot, etc.
- Returns JSON with snapshot test names
- Enables intelligent --snapshot-update application
- **v8.6.0**: Part of SEP toolkit for pytest atomization

## 🗂️ Directory Structure

After installation (all paths relative to project root):
```
./
├── scripts/
│   ├── sep_queue.sh                 # Queue manager
│   ├── sep.sh                      # Atomic executor
│   ├── sep_memory_monitor.sh        # Memory monitor
│   ├── sep_installer.sh             # Installer
│   ├── sep_tool_atomifier.sh        # Command atomizer
│   ├── sep_tool_config.sh           # Tool configuration
│   ├── sep_monitor_queue.sh         # Queue monitor
│   ├── sep_kill_orphans.sh          # Emergency cleanup
│   ├── sep_common.sh                # Shared functions
│   └── sep_detect_snapshot_tests.py # Snapshot test detector
├── logs/                            # All execution logs
│   ├── sep_queue_*.log              # Queue logs
│   ├── sep_*.log                    # Job logs
│   └── runs/                        # Run tracking
├── .sequential-locks/               # Lock directory
├── .sep.log.lock                   # Log write lock
├── .env.development                 # Configuration
└── sep -> scripts/sep_queue.sh      # Convenience symlink
```

## ⚙️ Configuration

### Environment Variables (.env.development)

Generated by installer with these defaults (paths relative to project root):
```bash
# Memory limits
MEMORY_LIMIT_MB=2048              # 2GB per process
CHECK_INTERVAL=5                  # Check every 5 seconds

# Timeouts
TIMEOUT=86400                     # 24 hours per command
PIPELINE_TIMEOUT=86400            # 24 hours for entire pipeline

# Debugging
VERBOSE=0                         # Set to 1 for verbose output

# Lock directory configuration (relative to project root)
SEQUENTIAL_LOCK_BASE_DIR="./.sequential-locks"

# sep.sh lock configuration (relative to project root)
WAIT_ALL_LOG_LOCK="./.sep.log.lock"

# Python/pytest configuration
PYTEST_MAX_WORKERS=1              # Force sequential pytest
```

## 📊 Log Viewing (GitHub-Style Syntax)

The sequential pipeline uses GitHub-compatible syntax for viewing execution history:

### Run Management (like `gh run`)
```bash
# List all runs
./scripts/sep_queue.sh run list
./scripts/sep_queue.sh run list --limit 10

# View specific run details
./scripts/sep_queue.sh run view 20250107_051316_abc123

# Watch run in real-time
./scripts/sep_queue.sh run watch 20250107_051316_abc123

# View failed runs only
./scripts/sep_queue.sh run list --status failed
```

### Direct Log Access
```bash
# Queue logs (like workflow logs)
cat ./logs/sep_queue_*.log

# Job logs (like job logs)
cat ./logs/sep_*.log

# Memory monitoring logs
cat ./logs/sep_memory_monitor_*.log

# Latest logs
ls -lt ./logs/ | head -20
```

### Log Correspondence

| GitHub Concept | Sequential Pipeline | Log Location |
|----------------|-------------------|--------------|
| Workflow Run | Queue Session | `./logs/sep_queue_<timestamp>_<pid>.log` |
| Job | sep.sh execution | `./logs/sep_job_<timestamp>_<id>.log` |
| Step | Individual command | Within sep.sh log |
| Run ID | Queue Run ID | `./logs/runs/<timestamp>_<id>/` |

## 🔧 Pre-commit Configuration

### Basic Setup (.pre-commit-config.yaml)

```yaml
default_language_version:
  python: python3.10

repos:
  # Standard hooks
  - repo: https://github.com/pre-commit/pre-commit-hooks
    rev: v5.0.0
    hooks:
      - id: trailing-whitespace
      - id: end-of-file-fixer
      - id: check-yaml
      - id: check-added-large-files
        args: ['--maxkb=10240']

  # Python formatting and linting - atomized
  - repo: local
    hooks:
      - id: ruff-format-atomic
        name: Format Python (atomic)
        entry: ./scripts/sep_queue.sh -- ruff format
        language: system
        types: [python]
        require_serial: true
        pass_filenames: true

      - id: ruff-check-atomic
        name: Lint Python (atomic)
        entry: ./scripts/sep_queue.sh -- ruff check --fix
        language: system
        types: [python]
        require_serial: true
        pass_filenames: true

  # Full project checks
  - repo: local
    hooks:
      - id: pytest-atomic
        name: Run tests (atomic)
        entry: ./scripts/sep_queue.sh --timeout 7200 -- pytest
        language: system
        pass_filenames: false
        stages: [pre-push]

      - id: mypy-atomic
        name: Type check (atomic)
        entry: ./scripts/sep_queue.sh -- mypy --strict
        language: system
        types: [python]
        pass_filenames: true
```

### Advanced Pre-commit with All Tools

```yaml
# ... standard hooks ...

  # Atomic execution hooks
  - repo: local
    hooks:
      # Python tools
      - id: format-python-atomic
        name: Format Python (atomic)
        entry: ./scripts/sep_queue.sh -- ruff format
        language: system
        types: [python]
        require_serial: true

      - id: lint-python-atomic
        name: Lint Python (atomic)
        entry: ./scripts/sep_queue.sh -- ruff check --fix
        language: system
        types: [python]
        require_serial: true

      - id: type-check-atomic
        name: Type checking (atomic)
        entry: ./scripts/sep_queue.sh -- mypy --strict
        language: system
        types: [python]
        pass_filenames: true

      # Project-wide checks
      - id: deptry-check
        name: Check dependencies
        entry: ./scripts/sep_queue.sh -- deptry .
        language: system
        pass_filenames: false
        always_run: true

      - id: pytest-full
        name: Run all tests
        entry: ./scripts/sep_queue.sh --timeout 7200 -- pytest --cov
        language: system
        pass_filenames: false
        stages: [pre-push]

      # Security
      - id: trufflehog-scan
        name: Secret detection
        entry: ./scripts/sep_queue.sh -- trufflehog git file://. --only-verified --fail
        language: system
        pass_filenames: false

      # YAML/GitHub Actions
      - id: format-yaml
        name: Format YAML
        entry: yamlfmt -path .github/workflows
        language: system
        pass_filenames: false

      - id: lint-actions
        name: Lint GitHub Actions
        entry: ./scripts/sep_queue.sh -- actionlint
        language: system
        pass_filenames: false
```

## 🔧 Runner Enforcement (v8.5.0+)

SEP now enforces proper runners for tools to ensure consistent execution:

### Supported Runners
- **uv**: Primary Python package manager (uv run, uv tool run)
- **pipx**: Python application installer
- **pnpm**: Node.js package manager
- **go**: Go language runner
- **npx**: Node.js package executor

### Runner Examples
```bash
# Automatically adds runners (default behavior)
./sep -- ruff check src/        # → uv run ruff check src/
./sep -- mypy --strict          # → uv run mypy --strict
./sep -- prettier --write       # → npx prettier --write

# Disable runner enforcement
./sep --dont_enforce_runners -- python script.py

# Skip unrecognized commands
./sep --only_verified -- custom-tool  # Will skip if not recognized
```

### Second-Tier Tools (opt-in)

⚠️ **CRITICAL SAFETY WARNING**: Second-tier tools are disabled by default for security reasons. They require explicit `--enable-second-tier` flag. Without this flag, NO atomization occurs for ANY second-tier tool.

Enable less-trusted but commonly used tools with `--enable-second-tier`:

**Python Security**: bandit, gitleaks, safety, pip-audit
**Python Quality**: vulture, radon, xenon, prospector, pylama, pydocstyle, darglint
**Python Testing**: unittest, nose2, tox, ward, behave
**Type Checkers**: pyre, pyright, pytype
**Other Tools**: invoke, nox, locust

```bash
# Enable second-tier tools
./sep --enable-second-tier -- bandit src/
./sep --enable-second-tier -- gitleaks detect

# unittest with test-method atomization (v8.6.0+)
./sep --enable-second-tier -- python -m unittest tests/test_example.py
# This will atomize to individual test methods:
# - python -m unittest tests.test_example.TestClass.test_method1
# - python -m unittest tests.test_example.TestClass.test_method2
# etc.
```

### Unsupported Runners
SEP does **not** support these package managers (by design):
- poetry run
- conda run
- pipenv run

If these are detected, SEP will pass the command through without atomification.

## 🚀 Usage Examples

### Basic Commands
```bash
# Simple execution
./sep -- echo "Hello World"

# Python development
./sep -- ruff format src/
./sep -- ruff check --fix src/
./sep -- mypy --strict src/
./sep -- pytest tests/

# Git operations (auto-detected, always safe)
./sep -- git add .
./sep -- git commit -m "feat: add feature"
./sep -- git push origin main

# Make operations (auto-detected)
./sep -- make test
./sep -- make build
```

### Queue Management
```bash
# Start the queue processor
./scripts/sep_queue.sh --queue-start

# Check queue status
./scripts/sep_queue.sh --queue-status

# Pause processing
./scripts/sep_queue.sh --queue-pause

# Resume processing
./scripts/sep_queue.sh --queue-resume

# Stop and clear queue
./scripts/sep_queue.sh --queue-stop
```

### Advanced Options
```bash
# Custom timeout
./sep --timeout 3600 -- pytest tests/integration/

# Custom memory limit
./sep --memory-limit 4096 -- python memory_intensive.py

# Verbose output
./sep --verbose -- make all

# No atomification (run as single command)
./sep --no-atomify -- pytest tests/
```

## 📊 Monitoring and Debugging

### Real-time Monitoring
```bash
# Watch queue status
./scripts/sep_monitor_queue.sh

# Follow all logs
tail -f ./logs/*.log

# Watch specific operation types
tail -f ./logs/sep_*.log | grep -E "EXIT|TIMEOUT|MEM"

# Process tree monitoring
watch -n 1 'ps aux | grep -E "sep\.sh|sep_queue"'
```

### Log Analysis
```bash
# Find failed commands
grep "EXIT.*rc=[^0]" ./logs/sep_*.log
grep "exit_code.*[^0]" ./logs/sep_*.log

# Memory violations
grep -i "memory.*exceed\|limit.*exceed" ./logs/*.log

# Long-running processes
grep "elapsed" ./logs/sep_queue_*.log | sort -k2 -n

# Queue wait times
grep "position" ./logs/sep_queue_*.log
```

### Emergency Procedures
```bash
# Kill all related processes
./scripts/sep_kill_orphans.sh

# Clear all locks
rm -rf .sequential-locks/*

# Reset queue
./scripts/sep_queue.sh --queue-stop
rm -f .sequential-locks/queue.txt

# Full reset
./scripts/sep_installer.sh uninstall
./scripts/sep_installer.sh install
```

## 🤖 AI Subagent Coordination Rules

When using AI subagents with this pipeline, follow these rules to prevent conflicts:

### 1. Sequential Execution Only
- Never spawn multiple subagents performing similar operations
- Wait for one subagent to complete before starting another
- One subagent per task type at any given time

### 2. Exclusive Resource Access
- **Git operations**: Only one subagent can perform git commands
- **File modifications**: Only one subagent can modify files at a time
- **Testing**: Only one subagent can run tests at a time
- **Linting/Formatting**: Must be done sequentially, never in parallel

### 3. Resource Locking Order
Always follow this order to prevent deadlocks:
1. File reading operations
2. Code analysis operations
3. File writing operations
4. Linting/formatting operations
5. Testing operations
6. Git operations
7. GitHub/remote operations

### 4. Task Specialization
Each subagent must have a unique, specific task:
- ✅ Subagent 1: Search patterns (read-only)
- ✅ Subagent 2: Run tests (after search completes)
- ✅ Subagent 3: Format code (after tests complete)
- ❌ Multiple subagents running tests simultaneously
- ❌ Multiple subagents modifying files simultaneously

## 🎯 Makefile Integration

```makefile
# Use sequential execution
SEP := ./sep --

.PHONY: all format lint test build clean

all: clean format lint test build

format:
	$(SEP) ruff format src/ tests/

lint:
	$(SEP) ruff check --fix src/ tests/
	$(SEP) mypy --strict src/

test:
	$(SEP) pytest -v --cov

build:
	$(SEP) uv build

clean:
	rm -rf dist/ build/ *.egg-info
	find . -type d -name __pycache__ -exec rm -rf {} +
```

## 📋 Verification Checklist

After installation, verify everything works:

```bash
# 1. Check installation
./scripts/sep_installer.sh doctor

# 2. Verify all script versions
for script in ./scripts/sep*.sh; do
    $script --version 2>/dev/null || echo "$script: no version"
done

# 3. Test basic execution
./sep -- echo "✅ Sequential queue works"

# 4. Check log creation
ls -la ./logs/

# 5. Verify lock files
ls -la ./.sequential-locks/
ls -la ./.sep.log.lock

# 6. Test queue operations
./sep -- echo "Test 1"
./sep -- echo "Test 2"
./scripts/sep_queue.sh --queue-start
./scripts/sep_queue.sh --queue-status

# 7. Check run tracking
./scripts/sep_queue.sh run list

# 8. Version consistency check
./scripts/sep_installer.sh doctor | grep "v8.6.0"
```

## 🐛 Troubleshooting

### Common Issues

**Queue not processing**:
```bash
# Check if processor is running
./scripts/sep_queue.sh --queue-status

# Start processor
./scripts/sep_queue.sh --queue-start
```

**Stale locks**:
```bash
# Clear locks safely
./scripts/sep_kill_orphans.sh

# Manual cleanup
rm -f .sequential-locks/queue.lock
```

**Memory errors**:
```bash
# Increase limit
MEMORY_LIMIT_MB=4096 ./sep -- python heavy_script.py

# Or edit .env.development
echo "MEMORY_LIMIT_MB=4096" >> .env.development
```

**Permission errors**:
```bash
# Fix script permissions
chmod +x scripts/*.sh

# Fix lock directory
chmod 755 .sequential-locks/
```

**macOS flock unavailable**:
- SEP automatically uses fallback locking on macOS
- No action required

## 📈 What's New in v8.6.0

### Version Consistency
- All SEP scripts now consistently report version 8.6.0
- Fixed version mismatches in help text
- Unified changelog format across all scripts

### Enhanced Integration
- `sep_tool_atomifier.sh` now sources `sep_common.sh`
- `sep_tool_config.sh` now includes VERSION variable and sources `sep_common.sh`
- Better script interdependency management

### unittest Support (Second-Tier)
- Added test-method level atomization for unittest
- Only enabled with `--enable-second-tier` flag
- Intelligently parses TestCase classes and test methods
- Supports both file paths and module names

### Critical Safety Improvements
- **ALL second-tier tools** now require `--enable-second-tier` flag for ANY atomization
- Added safety check to prevent accidental atomization of untrusted tools
- pytest now properly detects `::` syntax to avoid double-atomization
- Changed nose2, ward, behave to no-atomize (no implementation = no risk)
- All tools respect their ignore files (.gitignore, tool-specific configs)
- Safety principle: When in doubt, don't atomize

### Consolidated Features from v8.5.x
- Runner enforcement for uv-centric workflow
- Atomic locking to prevent race conditions
- macOS compatibility with fallback locking
- flock installation support on Linux

## 🎯 Summary

This sequential pipeline provides a complete solution for safe, controlled command execution with:

- **Queue Management**: Commands execute one at a time in order
- **Atomic Execution**: Complete cleanup guaranteed for every command
- **Memory Safety**: Real-time monitoring prevents system overload
- **GitHub-Style Logging**: Familiar syntax for viewing runs and jobs
- **Lock-Based Coordination**: Prevents race conditions and conflicts
- **Universal Compatibility**: Works on all POSIX systems with bash 3.2+
- **Version Consistency**: All scripts maintain synchronized versioning

The system prevents common development issues like process explosions, memory exhaustion, and git corruption while maintaining full visibility through comprehensive logging.

## 📋 Complete Tool Support Reference

### First-Tier Tools (Trusted & Recommended)

These tools are fully supported and atomized by default. They have been thoroughly tested and are safe for parallel execution when atomized.

| Tool | Category | Runner | Ignore Files | Extensions | Multi-File | Atomization | Notes |
|------|----------|---------|--------------|------------|------------|-------------|-------|
| **ruff** | Linter/Formatter | uv run | .ruffignore, .gitignore | *.py *.pyi | ✅ Yes | 📁 file | Fast Python linter & formatter |
| **mypy** | Type Checker | uv run | .mypy.ini, mypy.ini, pyproject.toml, .gitignore | *.py *.pyi | ❌ No | 📁 file | Static type checker |
| **pytest** | Test Runner | uv run | .pytest.ini, pytest.ini, pyproject.toml, tox.ini, setup.cfg | *.py *.pyi | ❌ No | 🧪 test-function | Atomizes to individual test functions |
| **coverage** | Coverage Tool | uv run | .coveragerc, pyproject.toml, setup.cfg | *.py *.pyi | ❌ No | 📂 directory | Code coverage measurement |
| **black** | Formatter | uv run | .black, pyproject.toml, .gitignore | *.py *.pyi | ✅ Yes | 📁 file | Python code formatter |
| **isort** | Import Sorter | uv run | .isort.cfg, pyproject.toml, setup.cfg, tox.ini, .gitignore | *.py *.pyi | ✅ Yes | 📁 file | Import statement sorter |
| **docformatter** | Docstring Formatter | uv run | .docformatterrc, pyproject.toml, setup.cfg | *.py *.pyi | ✅ Yes | 📁 file | Formats docstrings |
| **nbqa** | Notebook Linter | uv run | pyproject.toml, .gitignore | *.py *.pyi | ✅ Yes | 📁 file | Run tools on Jupyter notebooks |
| **pyupgrade** | Code Upgrader | uv run | pyproject.toml, .gitignore | *.py *.pyi | ✅ Yes | 📁 file | Upgrades Python syntax |
| **deptry** | Dependency Checker | uv run | pyproject.toml, .gitignore | *.py *.pyi | ❌ No | 📂 directory | Checks for unused dependencies |
| **eslint** | JS Linter | npx | .eslintignore, .gitignore | *.js *.jsx *.ts *.tsx *.mjs *.cjs *.vue | ✅ Yes | 📁 file | JavaScript/TypeScript linter |
| **prettier** | JS Formatter | npx | .prettierignore, .gitignore | *.js *.jsx *.ts *.tsx *.mjs *.cjs *.vue | ✅ Yes | 📁 file | Code formatter |
| **shellcheck** | Shell Linter | (none) | .shellcheckrc | *.sh *.bash *.zsh *.ksh | ✅ Yes | 📁 file | Shell script linter |
| **yamllint** | YAML Linter | (none) | .yamllint, .yamllint.yaml, .yamllint.yml | *.yml *.yaml | ✅ Yes | 📁 file | YAML file linter |
| **yamlfmt** | YAML Formatter | (none) | .yamlfmt, .gitignore | *.yml *.yaml | ❌ No | 📁 file | YAML file formatter |
| **jsonlint** | JSON Linter | npx | (none) | *.json *.jsonl *.geojson | ✅ Yes | 📁 file | JSON file linter |
| **actionlint** | GitHub Actions Linter | (none) | .gitignore | .github/workflows/*.yml .github/workflows/*.yaml | ❌ No | 📁 file | GitHub Actions workflow linter |
| **sqlfluff** | SQL Linter | (none) | .sqlfluff, .sqlfluffignore | *.sql *.ddl *.dml | ✅ Yes | 📁 file | SQL linter and formatter |
| **pre-commit** | Git Hook Manager | pipx run | .pre-commit-config.yaml | * | ❌ No | 🚫 no-atomize | Manages its own execution |
| **trufflehog** | Secret Scanner | (none) | trufflehog.yaml, .gitignore | * | ❌ No | 🚫 no-atomize | Scans whole repository |
| **commitizen** | Commit Tool | uv run | pyproject.toml, .cz.toml, .cz.json, .cz.yaml | * | ❌ No | 🚫 no-atomize | Standardizes commits |
| **mkdocs** | Documentation | uv run | mkdocs.yml, .gitignore | *.md *.markdown *.rst | ❌ No | 🚫 no-atomize | Documentation generator |
| **gh** | GitHub CLI | (none) | (none) | * | ❌ No | 🚫 no-atomize | GitHub operations |
| **act** | GitHub Actions Runner | (none) | (none) | *.yml *.yaml | ❌ No | 🚫 no-atomize | Run workflows locally |
| **bfg** | Repo Cleaner | (none) | (none) | * | ❌ No | 🚫 no-atomize | Repository history cleaner |
| **jq** | JSON Processor | (none) | (none) | *.json *.jsonl *.geojson | ❌ No | 📁 file | Command-line JSON processor |

### Second-Tier Tools (Discouraged - Use with --enable-second-tier)

These tools are less tested or have higher risk profiles. They require explicit opt-in with the `--enable-second-tier` flag.

| Tool | Category | Runner | Ignore Files | Extensions | Multi-File | Atomization | Implementation |
|------|----------|---------|--------------|------------|------------|-------------|----------------|
| **unittest** | Test Runner | uv run | pyproject.toml, setup.cfg, .gitignore | *.py *.pyi | ❌ No | 🧪 test-function | ✅ Implemented |
| **nose2** | Test Runner | uv run | nose2.cfg, pyproject.toml, .gitignore | *.py *.pyi | ❌ No | 🚫 no-atomize | ❌ No implementation |
| **tox** | Test Automation | uv run | tox.ini, pyproject.toml, .gitignore | *.py *.pyi | ❌ No | 🚫 no-atomize | Task runner |
| **gitleaks** | Secret Scanner | (none) | .gitleaks.toml, .gitignore | * | ❌ No | 🚫 no-atomize | Whole project scanner |
| **bandit** | Security Linter | uv run | .bandit, pyproject.toml, .gitignore | *.py *.pyi | ✅ Yes | 📁 file | Security issue scanner |
| **safety** | Dependency Scanner | uv run | pyproject.toml, .gitignore | *.py *.pyi | ❌ No | 🚫 no-atomize | Vulnerability scanner |
| **pip-audit** | Dependency Auditor | uv run | pyproject.toml, .gitignore | *.py *.pyi | ❌ No | 🚫 no-atomize | Package vulnerability scanner |
| **vulture** | Dead Code Finder | uv run | pyproject.toml, .gitignore | *.py *.pyi | ✅ Yes | 📁 file | Finds unused code |
| **radon** | Complexity Analyzer | uv run | pyproject.toml, .gitignore | *.py *.pyi | ✅ Yes | 📁 file | Code complexity metrics |
| **xenon** | Complexity Monitor | uv run | pyproject.toml, .gitignore | *.py *.pyi | ✅ Yes | 📁 file | Monitors code complexity |
| **prospector** | Code Analyzer | uv run | .prospector.yaml, pyproject.toml, .gitignore | *.py *.pyi | ❌ No | 📁 file | Aggregates multiple tools |
| **pylama** | Code Auditor | uv run | pylama.ini, pyproject.toml, .gitignore | *.py *.pyi | ✅ Yes | 📁 file | Code audit tool |
| **pydocstyle** | Docstring Checker | uv run | .pydocstyle, pyproject.toml, .gitignore | *.py *.pyi | ✅ Yes | 📁 file | Docstring conventions |
| **darglint** | Docstring Linter | uv run | .darglint, pyproject.toml, .gitignore | *.py *.pyi | ✅ Yes | 📁 file | Documentation linter |
| **pyre** | Type Checker | uv run | .pyre_configuration, pyproject.toml, .gitignore | *.py *.pyi | ❌ No | 📁 file | Facebook's type checker |
| **pyright** | Type Checker | npx | pyrightconfig.json, pyproject.toml, .gitignore | *.py *.pyi *.js *.ts | ❌ No | 📁 file | Microsoft's type checker |
| **pytype** | Type Checker | uv run | .pytype.cfg, pyproject.toml, .gitignore | *.py *.pyi | ❌ No | 📁 file | Google's type checker |
| **invoke** | Task Runner | uv run | invoke.yaml, tasks.py, .gitignore | *.py *.pyi | ❌ No | 🚫 no-atomize | Task execution framework |
| **nox** | Test Automation | uv run | noxfile.py, .gitignore | *.py *.pyi | ❌ No | 🚫 no-atomize | Testing automation |
| **ward** | Test Runner | uv run | pyproject.toml, .gitignore | *.py *.pyi | ❌ No | 🚫 no-atomize | ❌ No implementation |
| **behave** | BDD Runner | uv run | .behaverc, behave.ini, .gitignore | *.py *.pyi | ❌ No | 🚫 no-atomize | ❌ No implementation |
| **locust** | Load Testing | uv run | locust.conf, pyproject.toml, .gitignore | *.py *.pyi | ❌ No | 📁 file | Performance testing |

### Unsupported Runners (Not Compatible with SEP)

These package managers and runners are explicitly not supported by SEP. Commands using these will be passed through without atomization or runner enforcement.

| Runner | Type | Why Unsupported | Alternative |
|--------|------|-----------------|-------------|
| **poetry** | Python Package Manager | Different dependency resolution model | Use **uv** |
| **conda** | Environment Manager | Complex environment activation | Use **uv** with venv |
| **mamba** | Conda Alternative | Same as conda | Use **uv** with venv |
| **pipenv** | Python Environment | Different workflow model | Use **uv** |
| **pdm** | Python Package Manager | Different dependency model | Use **uv** |
| **pip-run** | Ephemeral Dependencies | Temporary environments | Use **uv run** |

### Legend

**Atomization Types:**
- 📁 **file**: Atomizes to individual file operations
- 🧪 **test-function**: Atomizes to individual test functions (pytest, unittest)
- 📂 **directory**: Works on directories
- 🚫 **no-atomize**: Cannot be atomized (works on whole project or manages own execution)

**Multi-File Support:**
- ✅ **Yes**: Tool can process multiple files in one command
- ❌ **No**: Tool processes one file at a time

**Notes:**
1. First-tier tools are enabled by default and thoroughly tested
2. Second-tier tools require `--enable-second-tier` flag for safety
3. Tools marked "no-atomize" either manage their own execution or require whole-project context
4. Unsupported runners will cause SEP to pass commands through without processing
