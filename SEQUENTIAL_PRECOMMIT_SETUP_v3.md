# Sequential Pipeline Setup Guide v3

A bulletproof solution for preventing process explosions, memory exhaustion, and system lockups during development operations.

## 🎯 What This Solves

- **Process Explosions**: Prevents 70+ concurrent processes from overwhelming your system
- **Memory Exhaustion**: Real-time monitoring kills processes exceeding limits (default 2GB)
- **Git Corruption**: Serializes git operations to prevent index conflicts
- **Pre-commit Deadlocks**: Detects and prevents circular dependencies
- **Parent Process Protection**: wait_all.sh v3.2 never kills processes that spawned it
- **Exit Code Propagation**: Correctly propagates exit codes through all execution layers
- **Blind Debugging**: Real-time logs track every process, memory usage, and execution time

## 🏗️ Architecture

```
User Command
    ↓
wait_all.sh --    OR    sequential-executor.sh
    ↓                           ↓
Actual Command            wait_all.sh --
(with cleanup)                 ↓
                          Actual Command
                          (with cleanup + queue)
```

### Key Components:
- **wait_all.sh**: Atomic execution with complete subprocess cleanup
- **sequential-executor.sh**: Sequential locking with queue management
- **memory_monitor.sh**: Real-time memory tracking and enforcement
- **Logging**: Every operation logged with timestamps and memory usage

## 📋 Prerequisites

### Required Software
```bash
# Check bash version
bash --version
# wait_all.sh v3.2 works with bash 3.2+ (macOS system bash compatible)
# sequential-executor.sh requires bash 4.0+

# macOS users: Install modern bash for sequential-executor.sh
brew install bash

# Install uv (fast Python package manager)
curl -LsSf https://astral.sh/uv/install.sh | sh

# Install pre-commit with uv support
uv tool install pre-commit --with pre-commit-uv

# Install essential tools
brew install jq gawk pnpm gh trufflehog yamllint actionlint act docker

# Install Python tools with uv
uv tool install ruff mypy pytest pytest-cov commitizen
uv tool install pytest-asyncio pytest-mock hypothesis mkdocs
uv tool install deptry sqlfluff nbqa isort pyupgrade

# Install Go tools
go install github.com/google/yamlfmt/cmd/yamlfmt@latest
```

## 🚀 Quick Setup

Copy and run these commands in your project root:

```bash
# 1. Create directories
mkdir -p scripts logs .github/workflows DOCS_DEV

# 2. Download scripts from repository
cd scripts
# Download all scripts listed in Step 2 below
curl -O https://raw.githubusercontent.com/your-repo/main/scripts/wait_all.sh
curl -O https://raw.githubusercontent.com/your-repo/main/scripts/sequential-executor.sh
# ... download all other scripts

# 3. Make scripts executable
chmod +x *.sh

# 4. Update .gitignore
cat >> .gitignore << 'EOF'

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
htmlcov/
.mypy_cache/
.ruff_cache/

# Virtual environments
venv/
.venv/
EOF

# 5. Run setup verification
cd ..
./scripts/ensure-sequential.sh

# 6. Install pre-commit hooks
pre-commit install
pre-commit install --hook-type pre-push

# 7. Create environment configuration
cat > .env.development << 'EOF'
# Memory limits
MEMORY_LIMIT_MB=2048    # 2GB per process
CHECK_INTERVAL=5        # Check every 5 seconds

# Timeouts
TIMEOUT=1800            # 30 minutes default
PIPELINE_TIMEOUT=7200   # 2 hours for entire pipeline

# CI/CD
CI=${CI:-false}
GITHUB_ACTIONS=${GITHUB_ACTIONS:-false}
EOF

# 8. Test the setup
./scripts/wait_all.sh -- echo "✅ Sequential pipeline ready!"
```

## 📝 Step 1: Create Directories

```bash
mkdir -p scripts logs
cd scripts
```

## 📦 Step 2: Essential Scripts

The sequential pipeline requires these scripts in your `./scripts` directory:

### 2.1 `wait_all.sh` - Atomic Process Manager (v3.2)

This is the core building block that ensures complete process cleanup with parent process protection.

**Features:**
- Parent process protection (never kills processes that spawned it)
- Complete subprocess tracking and cleanup
- Memory monitoring and limits
- Timeout support
- JSON output mode
- Retry functionality
- Compatible with bash 3.2+

**Download:** [wait_all.sh](./scripts/wait_all.sh)

### 2.2 `sequential-executor.sh` - Queue Manager

Ensures only one high-level command runs at a time, preventing resource conflicts.

**Features:**
- Queue-based execution
- Lock management
- Deadlock detection
- Pipeline timeout support
- Orphan process cleanup
- Detailed logging

**Download:** [sequential-executor.sh](./scripts/sequential-executor.sh)

### 2.3 `memory_monitor.sh` - Memory Guardian

Real-time memory monitoring with automatic process termination when limits are exceeded.

**Features:**
- Per-process RSS tracking
- System-wide memory monitoring
- Configurable limits
- High memory warnings
- Process tree visualization
- Automatic cleanup

**Download:** [memory_monitor.sh](./scripts/memory_monitor.sh)

### 2.4 `git-safe.sh` - Git Operations Wrapper

Wraps git commands to ensure sequential execution and prevent corruption.

**Features:**
- Sequential git operations
- Index lock prevention
- Automatic cleanup
- Full git command support

**Download:** [git-safe.sh](./scripts/git-safe.sh)

### 2.5 `make-sequential.sh` - Make Command Wrapper

Ensures make commands run sequentially to prevent parallel execution issues.

**Features:**
- Wraps make commands
- Forces sequential execution
- Preserves all make features
- Timeout support

**Download:** [make-sequential.sh](./scripts/make-sequential.sh)

### 2.6 `monitor-queue.sh` - Visual Queue Monitor

Real-time visual monitoring of the execution queue.

**Features:**
- Live queue status
- Process information
- Lock status
- Wait times
- Color-coded output

**Download:** [monitor-queue.sh](./scripts/monitor-queue.sh)

### 2.7 `kill-orphans.sh` - Emergency Cleanup

Emergency cleanup tool for orphaned processes and stale locks.

**Features:**
- Finds orphaned processes
- Cleans stale locks
- Safe termination
- Queue cleanup

**Download:** [kill-orphans.sh](./scripts/kill-orphans.sh)

### 2.8 `pre-commit-safe.sh` - Pre-commit Hook Wrapper

Wrapper for pre-commit to ensure safe execution without deadlocks.

**Features:**
- Deadlock prevention
- Sequential hook execution
- Timeout support
- Error handling

**Download:** [pre-commit-safe.sh](./scripts/pre-commit-safe.sh)

### 2.9 `atomic-hook.sh` - Atomic Pre-commit Helper

Helper script for atomic execution of individual pre-commit hooks.

**Features:**
- File-by-file processing
- Atomic operations
- Error propagation
- Timeout support

**Download:** [atomic-hook.sh](./scripts/atomic-hook.sh)

### 2.10 `example-atomic-pipeline.sh` - Pipeline Example

Example of an atomic CI/CD pipeline using the sequential tools.

**Features:**
- Complete pipeline example
- Best practices demonstration
- Error handling
- Logging integration

**Download:** [example-atomic-pipeline.sh](./scripts/example-atomic-pipeline.sh)

### 2.11 `ensure-sequential.sh` - Setup Verification

Verifies the sequential pipeline is correctly installed and configured.

**Features:**
- Installation verification
- Dependency checking
- Configuration validation
- Quick diagnostics

**Download:** [ensure-sequential.sh](./scripts/ensure-sequential.sh)

## 🔍 Step 3: Real-time Monitoring & Debugging

### Understanding the Logs

The sequential pipeline creates detailed logs in `./logs/` for every operation:

1. **wait_all.sh logs**: `wait_all_<timestamp>.log`
   - Complete command output (stdout/stderr)
   - Exit codes
   - Memory usage per process
   - Execution timeline

2. **sequential-executor logs**: `sequential_executor_strict_<timestamp>_<pid>.log`
   - Queue status
   - Lock acquisition/release
   - Wait times
   - Pipeline timeout status

3. **memory_monitor logs**: `memory_monitor_<timestamp>_<pid>.log`
   - Real-time memory tracking
   - Process tree snapshots
   - Memory limit violations
   - Process termination events

### Real-time Monitoring Commands

```bash
# Watch all logs in real-time
tail -f logs/*.log

# Monitor specific operation
tail -f logs/wait_all_*.log | grep -E "CMD|EXIT|memory"

# Watch memory usage
tail -f logs/memory_monitor_*.log | grep -E "WARNING|ERROR|Total memory"

# See queue status
./scripts/monitor-queue.sh

# Check current execution
ps aux | grep -E "wait_all|sequential-executor|memory_monitor"
```

### Debugging Common Issues

```bash
# Find failed commands
grep "EXIT: [^0]" logs/wait_all_*.log

# Find memory violations
grep "MEMORY LIMIT EXCEEDED" logs/memory_monitor_*.log

# Find timeout events
grep "TIMEOUT" logs/*.log

# Find deadlocks
grep -E "died unexpectedly|sequential chain broken" logs/sequential_executor_*.log

# Analyze long-running processes
grep "Still waiting" logs/sequential_executor_*.log
```

### Log Analysis Examples

```bash
# Get execution times for all pytest runs
grep -h "CMD.*pytest" logs/wait_all_*.log | \
  while read line; do
    file=$(echo "$line" | grep -oE "logs/[^:]+")
    echo -n "$line => "
    grep "TRY.*@ " "$file" | tail -1
  done

# Memory usage summary
for f in logs/memory_monitor_*.log; do
    echo "=== $f ==="
    grep "Total memory:" "$f" | tail -5
done

# Queue wait times
grep "Queue position:" logs/sequential_executor_*.log | \
  awk '{print $NF " - Wait: " $(NF-3) "s"}'
```

## ⚙️ Step 4: Configuration

### Environment Variables (.env.development)

```bash
# Memory limits
MEMORY_LIMIT_MB=2048    # 2GB per process
CHECK_INTERVAL=5        # Check every 5 seconds

# Timeouts
TIMEOUT=1800            # 30 minutes per command
PIPELINE_TIMEOUT=7200   # 2 hours for entire pipeline

# Debugging
VERBOSE=1               # Enable verbose output
```

### Pre-commit Configuration (.pre-commit-config.yaml)

```yaml
default_language_version:
  python: python3.11

repos:
  - repo: https://github.com/pre-commit/pre-commit-hooks
    rev: v5.0.0
    hooks:
      - id: trailing-whitespace
      - id: end-of-file-fixer
      - id: check-yaml
      - id: check-added-large-files
        args: ['--maxkb=10240']

  - repo: local
    hooks:
      # Atomic formatting - each file individually
      - id: ruff-format-atomic
        name: Format Python (atomic)
        entry: bash -c 'for f in "$@"; do ./scripts/wait_all.sh --timeout 60 -- ruff format "$f" || exit 1; done' --
        language: system
        types: [python]
        require_serial: true
        pass_filenames: true

      # Atomic linting - each file individually
      - id: ruff-check-atomic
        name: Lint Python (atomic)
        entry: bash -c 'for f in "$@"; do ./scripts/wait_all.sh --timeout 60 -- ruff check --fix "$f" || exit 1; done' --
        language: system
        types: [python]
        require_serial: true
        pass_filenames: true

      # Tests can run as batch with timeout
      - id: pytest-fast
        name: Run fast tests
        entry: ./scripts/wait_all.sh --timeout 300 -- pytest -m "not slow" -v
        language: system
        pass_filenames: false
        always_run: true
```

### Makefile Configuration

```makefile
# Atomic execution wrapper
WAIT_ALL := ./scripts/wait_all.sh

# Python source files
PY_FILES := $(shell find src tests -name "*.py" -type f)

# Format each file atomically
format:
	@for f in $(PY_FILES); do \
		echo "Formatting: $$f"; \
		$(WAIT_ALL) --timeout 30 -- ruff format "$$f" || exit 1; \
	done

# Lint each file atomically
lint:
	@for f in $(PY_FILES); do \
		echo "Checking: $$f"; \
		$(WAIT_ALL) --timeout 60 -- ruff check --fix "$$f" || exit 1; \
	done

# Test with timeout
test:
	$(WAIT_ALL) --timeout 1800 -- pytest -v

# Sequential targets
.PHONY: all
all: format lint test
```

### pytest Configuration (pytest.ini)

```ini
[pytest]
# Force sequential execution
addopts =
    -v
    --strict-markers
    --tb=short
    --disable-warnings
    -p no:xdist

# No parallel execution
testpaths = tests
python_files = test_*.py
python_classes = Test*
python_functions = test_*

# Timeout per test
timeout = 300
```

## 📊 Step 5: Usage Patterns

### Basic Command Execution

```bash
# Atomic execution (allows parallel, ensures cleanup)
./scripts/wait_all.sh -- python script.py
./scripts/wait_all.sh -- pytest tests/test_file.py
./scripts/wait_all.sh -- ruff format src/

# Sequential execution (one at a time, with queue)
./scripts/sequential-executor.sh make test
./scripts/sequential-executor.sh git commit -m "message"
```

### With Environment Variables

```bash
# Custom memory limit
MEMORY_LIMIT_MB=512 ./scripts/wait_all.sh -- python memory_intensive.py

# Custom timeout
TIMEOUT=60 ./scripts/wait_all.sh -- pytest tests/slow_test.py

# Verbose output
./scripts/wait_all.sh --verbose -- npm install
```

### Debugging Failed Executions

```bash
# 1. Check the logs
ls -lt logs/ | head -10

# 2. Find the relevant log
grep -l "my_script.py" logs/wait_all_*.log

# 3. Analyze the failure
cat logs/wait_all_20240105T120000Z.log

# 4. Check memory usage
grep "Peak memory" logs/wait_all_20240105T120000Z.log

# 5. Monitor in real-time
tail -f logs/wait_all_*.log | grep -E "CMD|EXIT|TIMEOUT|memory"
```

## 🛠️ Step 6: Troubleshooting

### Common Issues and Solutions

#### Process Explosion Despite Setup
```bash
# Check for direct command usage
ps aux | grep -E "pytest|ruff|mypy" | grep -v wait_all

# Solution: Always use wait_all.sh or sequential-executor.sh
alias pytest='./scripts/wait_all.sh -- pytest'
alias ruff='./scripts/wait_all.sh -- ruff'
```

#### Memory Limit Exceeded
```bash
# Check current limits
grep MEMORY_LIMIT .env.development

# Increase temporarily
MEMORY_LIMIT_MB=4096 ./scripts/wait_all.sh -- python script.py

# Find memory hogs
grep "High memory" logs/memory_monitor_*.log
```

#### Deadlocks
```bash
# Check for circular dependencies
./scripts/monitor-queue.sh

# Emergency cleanup
./scripts/kill-orphans.sh

# Reset all locks
rm -rf /tmp/seq-exec-*
rm -rf /tmp/make-lock-*
rm -rf /tmp/git-safe-*
```

#### Pipeline Timeouts
```bash
# Check pipeline status
cat /tmp/seq-exec-*/pipeline_timeout.txt

# Increase pipeline timeout
PIPELINE_TIMEOUT=14400 make test  # 4 hours
```

## ✅ Step 7: Verification

Run the verification script to ensure everything is set up correctly:

```bash
./scripts/ensure-sequential.sh
```

This will check:
- All scripts are present and executable
- Required tools are installed
- Configuration files exist
- Directories are created
- Basic functionality works

## 🤖 AI Agent Coordination Rules

### Subagent Coordination and Resource Management

When using AI subagents, follow these strict rules to prevent conflicts:

1. **Sequential Execution Only**:
   - Never spawn multiple subagents that perform similar operations
   - Wait for one subagent to complete before starting another
   - One subagent per task type at any given time

2. **Exclusive Resource Access**:
   - Git operations: Only one subagent can perform git commands
   - File modifications: Only one subagent can modify files at a time
   - Testing: Only one subagent can run tests at a time
   - Linting/Formatting: Must be done sequentially, never in parallel

3. **Task Specialization**:
   - Each subagent must have a unique, specific task
   - Never duplicate work across subagents
   - Examples of proper subagent usage:
     - Subagent 1: Search for patterns in codebase (read-only)
     - Subagent 2: Run tests (after Subagent 1 completes)
     - Subagent 3: Format code (after Subagent 2 completes)

4. **Resource Locking Order**:
   - Always follow this order to prevent deadlocks:
     1. File reading operations
     2. Code analysis operations
     3. File writing operations
     4. Linting/formatting operations
     5. Testing operations
     6. Git operations
     7. GitHub/remote operations

## 🛠️ Tool Configurations

### Python Tools (pyproject.toml)

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
authors = [
    {name = "Your Name", email = "your.email@example.com"}
]
dependencies = [
    # Add your dependencies here
]

[project.optional-dependencies]
dev = [
    "pytest>=7.4.0",
    "pytest-cov>=4.1.0",
    "ruff>=0.1.0",
    "mypy>=1.7.0",
    "pytest-asyncio>=0.21.0",
    "pytest-mock>=3.12.0",
    "hypothesis>=6.98.0",
    "pytest-sugar>=0.9.7",
    "colorama>=0.4.6",
    "syrupy>=4.6.0",
    "watchdog>=3.0.0",
    "pytest-watcher>=0.4.1",
    "pluggy>=1.4.0",
    "pygments>=2.17.0",
    "coverage[toml]>=7.4.0",
]
docs = [
    "mkdocs>=1.5.3",
    "mkdocs-material>=9.5.0",
]

[project.scripts]
my-cli = "mypackage.cli:main"

[tool.ruff]
line-length = 320
target-version = "py310"

[tool.ruff.lint]
select = ["E", "F", "W", "I", "N", "UP"]
ignore = ["E203", "E402", "E501", "E266", "W505", "F841"]

[tool.mypy]
strict = true
show_error_context = true
pretty = true
show_error_codes = true
follow_imports = "normal"

[tool.pytest.ini_options]
addopts = "-v --strict-markers --tb=short"
testpaths = ["tests"]
python_files = "test_*.py"
timeout = 300

[tool.coverage.run]
branch = true
source = ["src"]
omit = ["*/tests/*", "*/test_*.py"]

[tool.isort]
profile = "black"
line_length = 320

[tool.black]
line-length = 320
target-version = ['py310']

[tool.commitizen]
name = "cz_conventional_commits"
version = "0.1.0"
tag_format = "v$version"
version_files = [
    "pyproject.toml:version",
    "src/__init__.py:__version__"
]

[tool.deptry]
extend_exclude = ["tests", "docs", "build", "dist"]
ignore_notebooks = true
```

### YAML Linting Configuration (.yamllint)

```yaml
---
extends: default

rules:
  line-length:
    max: 320
    level: warning
  indentation:
    spaces: 2
  document-start: disable
  truthy:
    allowed-values: ['true', 'false', 'on', 'off', 'yes', 'no']
```

### ESLint Configuration (.eslintrc.json)

```json
{
  "env": {
    "browser": true,
    "es2021": true,
    "node": true
  },
  "extends": [
    "eslint:recommended",
    "prettier"
  ],
  "parserOptions": {
    "ecmaVersion": "latest",
    "sourceType": "module"
  },
  "rules": {
    "no-unused-vars": "warn",
    "no-console": "off"
  }
}
```

### Prettier Configuration (.prettierrc)

```json
{
  "printWidth": 120,
  "tabWidth": 2,
  "useTabs": false,
  "semi": true,
  "singleQuote": true,
  "trailingComma": "es5",
  "bracketSpacing": true,
  "arrowParens": "avoid"
}
```

### yamlfmt Configuration (.yamlfmt)

```yaml
formatter:
  indent: 2
  retain_line_breaks: true
  indentless_arrays: true
  scan_folded_as_literal: true
  trim_trailing_whitespace: true
  eof_newline: true
gitignore_excludes: true
```

### SQLFluff Configuration (.sqlfluff)

```ini
[sqlfluff]
dialect = postgres
templater = jinja
max_line_length = 120
indent_unit = space
indent_size = 2

[sqlfluff:rules]
tab_space_size = 4
max_line_length = 120
indent_unit = space
allow_scalar = True
single_table_references = consistent
unquoted_identifiers_policy = all
```

### Complete Pre-commit Configuration (.pre-commit-config.yaml)

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

  # Python formatting and linting
  - repo: https://github.com/astral-sh/ruff-pre-commit
    rev: v0.8.0
    hooks:
      - id: ruff-format
      - id: ruff
        args: [--fix]

  # Python type checking
  - repo: https://github.com/pre-commit/mirrors-mypy
    rev: v1.11.0
    hooks:
      - id: mypy
        additional_dependencies: [types-all]

  # Python dependencies
  - repo: https://github.com/fpgmaas/deptry
    rev: 0.12.0
    hooks:
      - id: deptry

  # YAML linting
  - repo: https://github.com/adrienverge/yamllint
    rev: v1.35.1
    hooks:
      - id: yamllint
        args: [-c=.yamllint]

  # GitHub Actions linting
  - repo: https://github.com/rhysd/actionlint
    rev: v1.6.26
    hooks:
      - id: actionlint

  # Shell script linting
  - repo: https://github.com/shellcheck-py/shellcheck-py
    rev: v0.10.0.1
    hooks:
      - id: shellcheck
        args: [--severity=warning]

  # JSON linting
  - repo: https://github.com/python-jsonschema/check-jsonschema
    rev: 0.28.0
    hooks:
      - id: check-github-workflows
      - id: check-github-actions

  # Python code quality
  - repo: https://github.com/pycqa/isort
    rev: 5.13.2
    hooks:
      - id: isort
        args: [--profile=black, --line-length=320]

  - repo: https://github.com/asottile/pyupgrade
    rev: v3.15.0
    hooks:
      - id: pyupgrade
        args: [--py310-plus]

  - repo: https://github.com/PyCQA/docformatter
    rev: v1.7.5
    hooks:
      - id: docformatter
        args: [--in-place, --wrap-summaries=320, --wrap-descriptions=320]

  # Notebook formatting
  - repo: https://github.com/nbQA-dev/nbQA
    rev: 1.8.5
    hooks:
      - id: nbqa-ruff
        args: [--fix]
      - id: nbqa-mypy
      - id: nbqa-isort
        args: [--profile=black]

  # SQL linting
  - repo: https://github.com/sqlfluff/sqlfluff
    rev: 3.0.7
    hooks:
      - id: sqlfluff-fix
        args: [--dialect=postgres]

  # JavaScript/TypeScript formatting
  - repo: https://github.com/pre-commit/mirrors-prettier
    rev: v3.1.0
    hooks:
      - id: prettier
        types_or: [css, javascript, jsx, json, markdown, typescript, tsx, yaml]
        exclude: '^(dist/|build/)'

  - repo: https://github.com/pre-commit/mirrors-eslint
    rev: v8.56.0
    hooks:
      - id: eslint
        types: [javascript, jsx, typescript, tsx]
        additional_dependencies:
          - eslint@8.56.0
          - eslint-config-prettier@9.1.0

  # Commit message linting
  - repo: https://github.com/commitizen-tools/commitizen
    rev: v3.27.0
    hooks:
      - id: commitizen
        stages: [commit-msg]

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

      - id: type-check-safe
        name: Type checking (safe)
        entry: ./scripts/wait_all.sh --timeout 300 -- mypy --strict
        language: system
        types: [python]
        pass_filenames: true

      - id: secret-detection-safe
        name: Secret detection (safe)
        entry: ./scripts/wait_all.sh --timeout 60 -- trufflehog git file://. --only-verified --fail
        language: system
        pass_filenames: false

      - id: format-yaml-safe
        name: Format YAML files (safe)
        entry: ./scripts/wait_all.sh --timeout 30 -- yamlfmt
        language: system
        types: [yaml]
        pass_filenames: true

      - id: test-fast-safe
        name: Run fast tests (safe)
        entry: ./scripts/sequential-executor.sh pytest -m "not slow" -v
        language: system
        pass_filenames: false
        always_run: true
```

### GitHub Actions Workflows

#### CI/CD Pipeline (.github/workflows/ci.yml)

```yaml
name: CI/CD Pipeline v3

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
          restore-keys: |
            uv-${{ runner.os }}-${{ hashFiles('uv.lock') }}
            uv-${{ runner.os }}

      - name: Install dependencies
        run: |
          uv sync --all-extras --dev

      - name: Run sequential tests
        run: |
          ./scripts/sequential-executor.sh uv run pytest -v --cov

      - name: Upload coverage
        uses: codecov/codecov-action@v4
        with:
          token: ${{ secrets.CODECOV_TOKEN }}

  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: astral-sh/setup-uv@v5
      - uses: actions/setup-python@v5
        with:
          python-version: '3.10'

      - name: Run linters
        run: |
          uv sync --all-extras --dev
          ./scripts/sequential-executor.sh uv run ruff check .
          ./scripts/sequential-executor.sh uv run mypy --strict src/

  build:
    needs: [test, lint]
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: astral-sh/setup-uv@v5
      - uses: actions/setup-python@v5
        with:
          python-version: '3.10'

      - name: Build package
        run: |
          ./scripts/wait_all.sh --timeout 300 -- uv build

      - name: Upload artifacts
        uses: actions/upload-artifact@v4
        with:
          name: dist
          path: dist/

  release:
    if: startsWith(github.ref, 'refs/tags/v')
    needs: build
    runs-on: ubuntu-latest
    permissions:
      contents: write
      id-token: write

    steps:
      - uses: actions/checkout@v4
      - uses: actions/download-artifact@v4
        with:
          name: dist
          path: dist/

      - name: Create GitHub Release
        env:
          GH_TOKEN: ${{ github.token }}
        run: |
          gh release create ${{ github.ref_name }} \
            --title "Release ${{ github.ref_name }}" \
            --generate-notes \
            dist/*

      - name: Publish to PyPI
        uses: pypa/gh-action-pypi-publish@release/v1
        with:
          skip-existing: true
```

#### Docker Build (.github/workflows/docker.yml)

```yaml
name: Docker Build and Test

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  docker:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3

      - name: Build test image
        run: |
          docker build --target test -t test-image .

      - name: Run tests in Docker
        run: |
          docker run --rm test-image ./scripts/wait_all.sh -- pytest -v

      - name: Build production image
        run: |
          docker build --target production -t app:latest .
```

### Docker Configuration

#### Dockerfile

```dockerfile
# syntax=docker/dockerfile:1
FROM python:3.10-slim as base

# Install system dependencies
RUN apt-get update && apt-get install -y \
    bash \
    curl \
    git \
    && rm -rf /var/lib/apt/lists/*

# Install uv
COPY --from=ghcr.io/astral-sh/uv:latest /uv /usr/local/bin/uv

# Create app directory
WORKDIR /app

# Copy scripts
COPY scripts/ ./scripts/
RUN chmod +x scripts/*.sh

# Copy project files
COPY pyproject.toml uv.lock README.md ./
COPY src/ ./src/

# Install dependencies
RUN uv sync --frozen --no-dev

# Test stage
FROM base as test
RUN uv sync --frozen --all-extras
COPY tests/ ./tests/
COPY pytest.ini ./
CMD ["./scripts/wait_all.sh", "--", "pytest", "-v"]

# Production stage
FROM base as production
ENV PYTHONUNBUFFERED=1
CMD ["./scripts/wait_all.sh", "--", "python", "-m", "myapp"]
```

#### docker-compose.yml

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
    command: ./scripts/wait_all.sh -- python -m myapp

  test:
    build:
      context: .
      target: test
    volumes:
      - ./logs:/app/logs
    command: ./scripts/sequential-executor.sh pytest -v
```

### Local Testing with act

```bash
# Install act
brew install act

# Configure act for uv
cat > .actrc << 'EOF'
-P ubuntu-latest=ghcr.io/catthehacker/ubuntu:act-latest
-P ubuntu-22.04=ghcr.io/catthehacker/ubuntu:act-22.04
-P ubuntu-20.04=ghcr.io/catthehacker/ubuntu:act-20.04
--container-architecture linux/amd64
EOF

# Test GitHub Actions locally
act -P ubuntu-latest=ghcr.io/catthehacker/ubuntu:act-latest

# Test specific workflow
act -W .github/workflows/ci.yml

# Test with secrets
act -s GITHUB_TOKEN="$(gh auth token)"

# Test specific job
act -j test

# Test with specific event
act pull_request

# Dry run
act -n

# With custom event payload
act -e event.json

# List all workflows
act -l
```

### Package Management with uv

```bash
# Initialize project
uv init --lib  # For library
uv init --app  # For application

# Development workflow
uv sync --all-extras           # Install all dependencies
uv add "package>=1.0"          # Add dependency
uv remove package              # Remove dependency
uv lock --upgrade              # Update all dependencies

# Build and publish
./scripts/wait_all.sh -- uv build
./scripts/wait_all.sh -- uv publish --token $PYPI_TOKEN

# Install from git
uv pip install git+https://github.com/user/repo.git@main

# Export requirements
uv pip compile pyproject.toml -o requirements.txt
uv pip compile pyproject.toml --extra dev -o requirements-dev.txt

# Create virtual environment
uv venv
source .venv/bin/activate  # Linux/macOS
.venv\Scripts\activate     # Windows

# Install in development mode
uv pip install -e .

# Run with uv
uv run python script.py
uv run pytest
```

### GitHub CLI Integration

```bash
# Setup
gh auth login

# Repository management
gh repo create my-project --public
gh repo clone user/repo

# Pull requests
./scripts/git-safe.sh checkout -b feature/new-feature
./scripts/sequential-executor.sh make format
./scripts/sequential-executor.sh make test
./scripts/git-safe.sh add -A
./scripts/git-safe.sh commit -m "feat: add new feature"
./scripts/git-safe.sh push -u origin feature/new-feature
gh pr create --title "Add new feature" --body "Description"

# Review workflow
gh pr list
gh pr view 123
gh pr review 123 --approve
gh pr merge 123 --squash --delete-branch

# Releases
gh release create v1.0.0 --generate-notes
gh release upload v1.0.0 dist/*

# Workflow management
gh run list
gh run view
gh run download
gh run watch

# Issues
gh issue create --title "Bug report" --body "Description"
gh issue list --label bug
gh issue close 42
```

## 🏁 Summary

You now have a bulletproof sequential pipeline that:
- ✅ Prevents process explosions
- ✅ Monitors and limits memory usage
- ✅ Provides detailed real-time logging
- ✅ Prevents git corruption
- ✅ Handles pre-commit hooks safely
- ✅ Offers visual queue monitoring
- ✅ **v3.2**: Never kills parent processes (git hooks safe)
- ✅ **v3.2**: Correctly propagates exit codes
- ✅ **v3.2**: Tracks all descendant processes recursively
- ✅ Supports Docker containerization
- ✅ Integrates with GitHub Actions
- ✅ Works with act for local CI testing
- ✅ Full uv package management support

Use `wait_all.sh --` for atomic operations and `sequential-executor.sh` when you need strict sequential execution with queue management.

## 📚 Quick Reference

```bash
# Atomic execution (parallel allowed, cleanup guaranteed)
./scripts/wait_all.sh -- <command>

# Sequential execution (one at a time)
./scripts/sequential-executor.sh <command>

# Monitor queue
./scripts/monitor-queue.sh

# View logs
tail -f logs/*.log

# Emergency cleanup
./scripts/kill-orphans.sh

# Package management
uv sync                        # Install dependencies
uv add "package>=1.0"          # Add dependency
uv build                       # Build package
uv publish                     # Publish to PyPI

# Git operations
./scripts/git-safe.sh commit -m "message"
./scripts/git-safe.sh push origin main

# GitHub CLI
gh pr create
gh pr merge
gh release create

# Docker
docker build -t app .
docker run --rm app ./scripts/wait_all.sh -- pytest

# Local CI testing
act -W .github/workflows/ci.yml
act -j test

# Make commands (already sequential)
make test
make lint
make format
make build
make release
```

## 🔒 Security Notes

1. **TruffleHog v3**: Configured for secret detection
   - Runs on every commit via pre-commit
   - Use `--only-verified` to reduce false positives
   - Add to GitHub Actions for CI/CD protection

2. **Environment Variables**: Never commit `.env` files
   - Use `.env.development` for local settings
   - Use GitHub Secrets for CI/CD
   - Use Docker secrets for production

3. **Process Isolation**: Each command runs in its own process group
   - Complete cleanup guaranteed
   - No orphaned processes
   - Memory limits enforced

4. **Dependency Security**:
   ```bash
   # Check for vulnerabilities
   uv pip audit

   # Update all dependencies
   uv lock --upgrade

   # Pin dependencies for production
   uv lock --frozen
   ```

## 📝 Additional Resources

- **Script Documentation**: Each script in `./scripts/` contains detailed usage instructions
- **Troubleshooting Guide**: See logs in `./logs/` for debugging information
- **Performance Tuning**: Adjust `MEMORY_LIMIT_MB` and `TIMEOUT` in `.env.development`
- **Contributing**: Follow the sequential pipeline when contributing to prevent conflicts

This completes the Sequential Pipeline Protocol v3. All operations are now safe, monitored, and logged.
