# Sequential Pipeline Setup Guide v3

A comprehensive solution for preventing process explosions, memory exhaustion, and system lockups during development operations.

## 🎯 Core Benefits

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
│              Sequential Executor                            │
│  • Queue management                                         │
│  • Lock enforcement                                         │
│  • Pipeline timeout                                         │
└────────────────────┬───────────────────────────────────────┘
                     ▼
┌─────────────────────────────────────────────────────────────┐
│                 wait_all.sh                                 │
│  • Process group isolation                                  │
│  • Complete cleanup                                         │
│  • Memory tracking                                          │
│  • Exit code propagation                                    │
└────────────────────┬───────────────────────────────────────┘
                     ▼
┌─────────────────────────────────────────────────────────────┐
│              Actual Command                                 │
│  • Runs in isolated process group                           │
│  • Monitored by memory_monitor.sh                          │
│  • All descendants tracked                                  │
└─────────────────────────────────────────────────────────────┘
```

## 📋 Prerequisites

```bash
# Minimum requirements
bash --version  # 3.2+ required (works with macOS default bash)

# Install essential tools
# macOS
brew install jq gawk pnpm gh ripgrep fd coreutils

# Linux (Debian/Ubuntu)
sudo apt-get update && sudo apt-get install -y jq gawk curl git

# Install uv (fast Python package manager)
curl -LsSf https://astral.sh/uv/install.sh | sh

# Install pre-commit with uv support
uv tool install pre-commit --with pre-commit-uv

# Install Python development tools
uv tool install ruff mypy pytest pytest-cov deptry commitizen
uv tool install yamllint actionlint sqlfluff isort pyupgrade
```

## 🚀 Quick Setup

```bash
# 1. Create required directories
mkdir -p scripts logs .github/workflows DOCS_DEV

# 2. Download all scripts (see Step 2 for complete list)
cd scripts
# Download scripts from repository or copy from scripts/ directory
chmod +x *.sh

# 3. Run the automated installer
./scripts/install_sequential.sh install

# 4. Verify installation
./scripts/install_sequential.sh doctor

# 5. Install pre-commit hooks
cd ..
pre-commit install
pre-commit install --hook-type pre-push

# 6. Test core functionality
./scripts/wait_all.sh --help
./scripts/sequential_queue.sh --help
```

## 📦 Essential Scripts

All scripts are version 3.0.0 with comprehensive `--help` options.

### Core Scripts (Version 3.0.0)

#### 1. `wait_all.sh` - Atomic Process Manager
**Purpose**: Core building block for atomic command execution with complete cleanup.

**Key Features**:
- Process group isolation
- Complete descendant tracking
- Memory usage monitoring
- Timeout and retry support
- JSON output mode
- Automatic runner detection (uv, pnpm)
- Parent process protection
- Bash 3.2+ compatible

**Usage**:
```bash
./scripts/wait_all.sh --help  # Full documentation
./scripts/wait_all.sh -- command args
./scripts/wait_all.sh --timeout 300 --retry 3 -- pytest
./scripts/wait_all.sh --json -- python script.py
```

#### 2. `sequential_queue.sh` - Universal Queue Manager
**Purpose**: Ensures only ONE process runs at a time with auto-detection for git and make commands.

**Key Features**:
- Indefinite waiting (no timeout on lock acquisition)
- Queue-based execution order
- Pipeline timeout for entire chain
- Detailed logging and status
- Atomic command enforcement
- Requires wait_all.sh (no fallback)

**Usage**:
```bash
./scripts/sequential_queue.sh --help
./scripts/sequential_queue.sh -- git commit -m "feat: update"
./scripts/sequential_queue.sh -- make test
./scripts/sequential_queue.sh -- pytest tests/test_one.py
./seq -- ruff format src/main.py  # Convenience symlink
```

#### 3. `memory_monitor.sh` - Memory Guardian
**Purpose**: Real-time memory monitoring with automatic process termination.

**Key Features**:
- Per-process RSS tracking
- Process tree monitoring
- Configurable limits and intervals
- Automatic cleanup on violation
- Cross-platform memory detection

**Usage**:
```bash
./scripts/memory_monitor.sh --help
./scripts/memory_monitor.sh --pid $$ --limit 4096 --interval 5
```

### Setup and Utility Scripts

#### 4. `install_sequential.sh` - Installation Manager
**Purpose**: Automated installation, health check, and uninstall.

**Key Features**:
- Three modes: install, doctor, uninstall
- Cross-platform dependency installation
- Environment configuration
- Health checks and verification

**Usage**:
```bash
./scripts/install_sequential.sh --help
./scripts/install_sequential.sh install    # Complete installation
./scripts/install_sequential.sh doctor     # Health check
./scripts/install_sequential.sh uninstall  # Remove configuration
```

#### 5. `monitor-queue.sh` - Queue Monitor
**Purpose**: Real-time visual monitoring of execution queue.

**Features**:
- Live queue status
- Process information
- Wait times
- Color-coded output

#### 6. `kill-orphans.sh` - Emergency Cleanup
**Purpose**: Clean up orphaned processes and stale locks.

**Features**:
- Find orphaned processes
- Clean stale locks
- Safe termination
- Queue cleanup

## 📂 Script Structure

```
scripts/
├── wait_all.sh                  # Core: Atomic execution
├── sequential_queue.sh          # Core: Universal queue (auto-detects git/make)
├── memory_monitor.sh            # Core: Memory monitoring
├── install_sequential.sh        # Setup: Install/Doctor/Uninstall
├── monitor-queue.sh             # Tool: Real-time monitoring
└── kill-orphans.sh              # Tool: Emergency cleanup
```

**Note**: The following scripts are created as symlinks for backward compatibility:
- `sequential-executor.sh` → `sequential_queue.sh`
- `git-safe.sh` → `sequential_queue.sh`
- `make-sequential.sh` → `sequential_queue.sh`

## 🔧 Configuration Files

### Pre-commit Configuration (.pre-commit-config.yaml)

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
      - id: check-toml
      - id: check-json
      - id: check-merge-conflict

  # Python tools - using uv
  - repo: https://github.com/astral-sh/uv-pre-commit
    rev: 0.5.1
    hooks:
      - id: uv-lock

  # Atomic execution hooks
  - repo: local
    hooks:
      - id: format-python-atomic
        name: Format Python (atomic)
        entry: bash -c 'for f in "$@"; do ./scripts/wait_all.sh --timeout 60 -- ruff format "$f" || exit 1; done' --
        language: system
        types: [python]
        require_serial: true
        pass_filenames: true

      - id: lint-python-atomic
        name: Lint Python (atomic)
        entry: bash -c 'for f in "$@"; do ./scripts/wait_all.sh --timeout 60 -- ruff check --fix "$f" || exit 1; done' --
        language: system
        types: [python]
        require_serial: true
        pass_filenames: true

      - id: deptry-check
        name: Check dependencies with deptry
        entry: ./scripts/wait_all.sh --timeout 300 -- deptry .
        language: system
        pass_filenames: false
        always_run: true

      - id: type-check-safe
        name: Type checking (safe)
        entry: ./scripts/wait_all.sh --timeout 300 -- mypy --strict
        language: system
        types: [python]
        pass_filenames: true

      - id: secret-detection-safe
        name: Secret detection (safe)
        entry: ./scripts/wait_all.sh --timeout 60 -- trufflehog git file://. --only-verified --fail --no-update --exclude-paths=snapshot_report.html
        language: system
        pass_filenames: false

      - id: format-yaml-safe
        name: Format YAML files
        entry: bash -c 'yamlfmt -path .github/workflows'
        language: system
        pass_filenames: false

      - id: lint-yaml-safe
        name: Lint YAML files
        entry: ./scripts/wait_all.sh --timeout 30 -- yamllint
        language: system
        types: [yaml]
        pass_filenames: true

      - id: lint-actions-safe
        name: Lint GitHub Actions workflows
        entry: ./scripts/wait_all.sh --timeout 30 -- actionlint
        language: system
        pass_filenames: false
```

### Python Project Configuration (pyproject.toml)

```toml
[build-system]
requires = ["hatchling"]
build-backend = "hatchling.build"

[project]
name = "your-project"
version = "0.1.0"
description = "Your project description"
readme = "README.md"
requires-python = ">=3.10"
license = {text = "MIT"}

[project.optional-dependencies]
dev = [
    "pytest>=7.4.0",
    "pytest-cov>=4.1.0",
    "pytest-asyncio>=0.21.0",
    "pytest-mock>=3.12.0",
    "pytest-timeout>=2.2.0",
    "ruff>=0.1.0",
    "mypy>=1.7.0",
    "deptry>=0.12.0",
]

[tool.ruff]
line-length = 120
target-version = "py310"

[tool.ruff.lint]
select = ["E", "F", "W", "I", "N", "UP"]
ignore = ["E203", "E501"]

[tool.mypy]
strict = true
show_error_context = true
pretty = true

[tool.pytest.ini_options]
addopts = "-v --strict-markers --tb=short"
timeout = 300

[tool.coverage.run]
branch = true
source = ["src"]

[tool.deptry]
extend_exclude = ["tests", "docs", "scripts"]
```

### Makefile Integration

```makefile
# Use sequential execution wrappers
WAIT_ALL := ./scripts/wait_all.sh
SEQ_EXEC := ./scripts/sequential_queue.sh --
MAKE_SEQ := ./scripts/sequential_queue.sh -- make

.PHONY: format lint test build clean

# Atomic operations
format:
	@echo "Formatting code..."
	@find src tests -name "*.py" -type f | while read f; do \
		$(WAIT_ALL) --timeout 30 -- ruff format "$$f" || exit 1; \
	done

lint:
	@echo "Linting code..."
	@$(SEQ_EXEC) ruff check --fix src/ tests/
	@$(SEQ_EXEC) mypy --strict src/

test:
	@echo "Running tests..."
	@$(SEQ_EXEC) pytest -v --cov

build:
	@echo "Building package..."
	@$(WAIT_ALL) --timeout 300 -- uv build

# Use make-sequential for recursive makes
all:
	@$(MAKE_SEQ) clean
	@$(MAKE_SEQ) format
	@$(MAKE_SEQ) lint
	@$(MAKE_SEQ) test
	@$(MAKE_SEQ) build
```

## 🛠️ Usage Patterns

### Basic Commands

```bash
# Atomic execution (parallel safe, cleanup guaranteed)
./scripts/wait_all.sh -- python script.py
./scripts/wait_all.sh --timeout 300 -- pytest tests/
./scripts/wait_all.sh --json -- npm install

# Sequential execution (one at a time, queue managed)
./scripts/sequential_queue.sh -- ruff format src/main.py
./scripts/sequential_queue.sh -- pytest tests/test_one.py

# Git operations (auto-detected)
./scripts/sequential_queue.sh -- git commit -m "feat: add feature"
./scripts/sequential_queue.sh -- git push origin main

# Make operations (auto-detected)
./scripts/sequential_queue.sh -- make test
./seq -- make all  # Using convenience symlink
```

### Advanced Usage

```bash
# Custom memory limits
MEMORY_LIMIT_MB=512 ./scripts/wait_all.sh -- python memory_test.py

# Pipeline with timeout
PIPELINE_TIMEOUT=3600 ./scripts/sequential_queue.sh -- make all

# Verbose debugging
./scripts/wait_all.sh --verbose -- pytest -v

# JSON output for parsing
./scripts/wait_all.sh --json -- python script.py | jq .exit_code

# Retry on failure
./scripts/wait_all.sh --retry 3 --timeout 60 -- flaky_test.sh
```

## 📊 Monitoring and Debugging

### Real-time Monitoring

```bash
# Watch all logs
tail -f logs/*.log

# Monitor specific operations
tail -f logs/wait_all_*.log | grep -E "EXIT|TIMEOUT|memory"

# Queue status
watch -n 1 ./scripts/monitor-queue.sh

# Process tree
ps aux | grep -E "wait_all|sequential_queue|memory_monitor"
```

### Log Analysis

```bash
# Find failed commands
grep "EXIT: [^0]" logs/wait_all_*.log

# Memory violations
grep "exceeded.*limit" logs/memory_monitor_*.log

# Long-running processes
grep "elapsed" logs/sequential_queue_*.log | awk '{print $NF}' | sort -n

# Queue wait times
grep "Queue position" logs/sequential_queue_*.log
```

### Troubleshooting

```bash
# Emergency cleanup
./scripts/kill-orphans.sh

# Reset all locks
rm -rf /tmp/seq-exec-*
rm -rf /tmp/make-lock-*
rm -rf /tmp/git-safe-*

# Check for process leaks
ps aux | grep -v grep | grep -E "ruff|pytest|mypy|npm"

# Verify setup
./scripts/install_sequential.sh doctor
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

## 🐳 Docker Integration

### Multi-stage Dockerfile

```dockerfile
# syntax=docker/dockerfile:1
FROM python:3.10-slim as base

# Install system dependencies
RUN apt-get update && apt-get install -y \
    bash curl git make \
    && rm -rf /var/lib/apt/lists/*

# Install uv
COPY --from=ghcr.io/astral-sh/uv:latest /uv /usr/local/bin/uv

WORKDIR /app

# Copy scripts first
COPY scripts/ ./scripts/
RUN chmod +x scripts/*.sh

# Copy project files
COPY pyproject.toml uv.lock README.md ./
COPY src/ ./src/

# Create logs directory
RUN mkdir -p logs

# Development stage
FROM base as development
RUN uv sync --frozen --all-extras
COPY tests/ ./tests/
CMD ["./scripts/wait_all.sh", "--", "pytest", "-v"]

# Production stage
FROM base as production
RUN uv sync --frozen --no-dev
ENV PYTHONUNBUFFERED=1
CMD ["./scripts/wait_all.sh", "--", "python", "-m", "myapp"]
```

### Docker Compose

```yaml
version: '3.8'

services:
  app:
    build:
      context: .
      target: production
    environment:
      - MEMORY_LIMIT_MB=2048
      - TIMEOUT=1800
    volumes:
      - ./logs:/app/logs

  test:
    build:
      context: .
      target: development
    environment:
      - MEMORY_LIMIT_MB=4096
      - PIPELINE_TIMEOUT=3600
    volumes:
      - ./logs:/app/logs
    command: ./scripts/sequential-executor.sh pytest -v --cov
```

## 📦 GitHub Actions Integration

### CI/CD Workflow

```yaml
name: CI/CD Pipeline

on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main]

env:
  UV_CACHE_DIR: /tmp/.uv-cache

jobs:
  test:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        python-version: ['3.10', '3.11', '3.12']

    steps:
      - uses: actions/checkout@v4

      - name: Install uv
        uses: astral-sh/setup-uv@v5

      - name: Set up Python
        uses: actions/setup-python@v5
        with:
          python-version: ${{ matrix.python-version }}

      - name: Cache uv
        uses: actions/cache@v4
        with:
          path: /tmp/.uv-cache
          key: uv-${{ runner.os }}-${{ hashFiles('uv.lock') }}

      - name: Install dependencies
        run: uv sync --frozen --all-extras

      - name: Run tests
        run: ./scripts/sequential_queue.sh -- uv run pytest -v --cov

      - name: Upload coverage
        uses: codecov/codecov-action@v4
        with:
          token: ${{ secrets.CODECOV_TOKEN }}

  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: astral-sh/setup-uv@v5

      - name: Install dependencies
        run: uv sync --frozen --all-extras

      - name: Run linters
        run: |
          ./scripts/sequential_queue.sh -- uv run ruff check .
          ./scripts/sequential_queue.sh -- uv run mypy --strict src/

  build:
    needs: [test, lint]
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: astral-sh/setup-uv@v5

      - name: Build package
        run: ./scripts/wait_all.sh --timeout 300 -- uv build

      - name: Upload artifacts
        uses: actions/upload-artifact@v4
        with:
          name: dist
          path: dist/
```

## 🧪 Local CI Testing with act

```bash
# Install act
brew install act

# Test workflows locally
act -P ubuntu-latest=ghcr.io/catthehacker/ubuntu:act-latest

# Test specific job
act -j test

# With secrets
act -s GITHUB_TOKEN="$(gh auth token)"

# Dry run
act -n
```

## 🚀 uv Package Management

```bash
# Project initialization
uv init --lib        # For library
uv init --app        # For application

# Dependency management
uv add "requests>=2.31"      # Add dependency
uv add --dev pytest          # Add dev dependency
uv remove requests           # Remove dependency
uv sync                      # Install all dependencies
uv lock --upgrade            # Update all dependencies

# Building and publishing
./scripts/wait_all.sh -- uv build
./scripts/wait_all.sh -- uv publish

# Development workflow
uv venv                      # Create virtual environment
source .venv/bin/activate    # Activate it
uv pip install -e .          # Editable install
```

## 🔒 Security Configuration

### TruffleHog v3 Setup

```yaml
# In .pre-commit-config.yaml
- repo: https://github.com/trufflesecurity/trufflehog
  rev: v3.63.5
  hooks:
    - id: trufflehog
      name: TruffleHog v3
      entry: trufflehog git file://. --only-verified --fail --no-update
      language: golang
      pass_filenames: false
```

### Environment Security

```bash
# Never commit these files
echo ".env" >> .gitignore
echo ".env.*" >> .gitignore
echo "!.env.example" >> .gitignore

# Use GitHub secrets for CI/CD
gh secret set PYPI_TOKEN
gh secret set CODECOV_TOKEN
```

## 📋 Quick Reference

```bash
# Help for any script
./scripts/<script-name>.sh --help

# Atomic execution
./scripts/wait_all.sh -- command

# Sequential execution
./scripts/sequential_queue.sh -- command
./seq -- command  # Using convenience symlink

# Git operations (auto-detected)
./scripts/sequential_queue.sh -- git commit -m "message"

# Make operations (auto-detected)
./scripts/sequential_queue.sh -- make target

# Monitor system
./scripts/monitor-queue.sh           # Queue status
tail -f logs/*.log                   # Real-time logs
./scripts/kill-orphans.sh            # Emergency cleanup

# Package management
uv sync                              # Install dependencies
uv build                             # Build package
uv publish                           # Publish to PyPI

# Testing
act -j test                          # Test CI locally
docker-compose run test              # Test in Docker
```

## ✅ Verification Checklist

Run through this checklist to ensure proper setup:

```bash
# 1. Verify scripts are executable
ls -la scripts/*.sh | grep -v "^-rwx"

# 2. Test bash compatibility
./scripts/test-bash-compatibility.sh

# 3. Verify core functionality
./scripts/wait_all.sh -- echo "✅ wait_all.sh works"
./scripts/sequential_queue.sh -- echo "✅ sequential_queue.sh works"

# 4. Check help documentation
for script in scripts/*.sh; do
    echo "=== $script ==="
    $script --help | head -5
done

# 5. Run full verification
./scripts/install_sequential.sh doctor
```

## 🎯 Summary

This sequential pipeline provides:

- **Complete process control** with queue management and atomic execution
- **Memory safety** through real-time monitoring and enforcement
- **Universal compatibility** across all POSIX systems with bash 3.2+
- **Comprehensive logging** for debugging and monitoring
- **Git operation safety** preventing corruption and conflicts
- **CI/CD integration** with GitHub Actions and Docker support
- **Developer friendly** with detailed --help for every script

All scripts work together to create a bulletproof development environment that prevents system overload while maintaining productivity.
