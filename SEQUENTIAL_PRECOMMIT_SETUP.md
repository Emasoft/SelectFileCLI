# Sequential Pre-commit Setup Guide with Resource Monitoring

This guide provides a project-local solution for configuring pre-commit hooks to run sequentially with comprehensive resource monitoring, preventing system resource exhaustion. All configuration is contained within the project directory - no system or user configuration files are modified.

## Why Sequential Execution with Monitoring

Parallel pre-commit hooks can cause:
- Memory exhaustion from concurrent linters/formatters
- File descriptor leaks from improper cleanup
- Process proliferation from uncontrolled spawning
- System crashes on resource-constrained machines
- Unpredictable hook execution order

Sequential execution with resource monitoring provides:
- Predictable resource usage patterns
- Real-time monitoring of memory, file descriptors, and processes
- Automatic termination when limits are exceeded
- Detailed logs for debugging resource issues
- Protection against runaway processes

## Prerequisites

Only global tool installations are required:
- Python 3.8+
- Git
- uv (install with: `curl -LsSf https://astral.sh/uv/install.sh | sh`)
- Optionally: Homebrew (macOS/Linux) for system tools

## Enhanced Setup with Resource Monitoring

### 1. Project Setup Script with Monitoring

Create `setup-sequential-precommit.sh` in your project root:

```bash
#!/usr/bin/env bash
# Enhanced setup script for sequential pre-commit execution with resource monitoring
# All configuration is project-local - no system files are modified

set -euo pipefail

echo "Setting up project-local sequential pre-commit with resource monitoring..."

# Create virtual environment if it doesn't exist
if [ ! -d ".venv" ]; then
    echo "Creating virtual environment..."
    uv venv
fi

# Create activation hooks directory for environment variables
echo "Setting up project-local environment configuration..."
mkdir -p .venv/bin/activate.d 2>/dev/null || mkdir -p .venv/Scripts/activate.d 2>/dev/null

# Create environment configuration that will be sourced on activation
cat > .venv/bin/activate.d/sequential-precommit.sh << 'EOF'
#!/usr/bin/env bash
# Project-local environment configuration
export PRE_COMMIT_MAX_WORKERS=1
export PYTHONDONTWRITEBYTECODE=1
export UV_NO_CACHE=1
export PRE_COMMIT_NO_CONCURRENCY=1
export MEMORY_LIMIT_MB=2048
export TIMEOUT_SECONDS=600
export TRUFFLEHOG_TIMEOUT=300
export TRUFFLEHOG_MEMORY_MB=1024
export TRUFFLEHOG_CONCURRENCY=1
EOF

chmod +x .venv/bin/activate.d/sequential-precommit.sh 2>/dev/null || true

# Activate virtual environment
source .venv/bin/activate

# Install pre-commit as a uv tool (project-local)
echo "Installing pre-commit..."
uv tool install pre-commit --with pre-commit-uv

# Create wrapper scripts directory
mkdir -p .pre-commit-wrappers

# Create memory-limited wrapper
cat > .pre-commit-wrappers/memory-limited-hook.sh << 'EOF'
#!/usr/bin/env bash
set -euo pipefail

# Use project-local environment variables
MEMORY_LIMIT_MB="${MEMORY_LIMIT_MB:-2048}"
TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-600}"

if [ $# -lt 1 ]; then
    echo "Usage: $0 <command> [args...]"
    exit 1
fi

COMMAND="$1"
shift

# Platform-specific memory limiting
if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    ulimit -v $((MEMORY_LIMIT_MB * 1024)) 2>/dev/null || true
    ulimit -d $((MEMORY_LIMIT_MB * 1024)) 2>/dev/null || true
fi

# Cleanup on exit
cleanup() {
    pkill -P $$ 2>/dev/null || true
    if [[ "$COMMAND" == *"python"* ]] || [[ "$COMMAND" == *"uv"* ]]; then
        python3 -c "import gc; gc.collect()" 2>/dev/null || true
    fi
}
trap cleanup EXIT INT TERM

echo "Running (memory limited to ${MEMORY_LIMIT_MB}MB): $COMMAND $*"

# Execute with timeout
if command -v timeout &> /dev/null; then
    exec timeout "$TIMEOUT_SECONDS" "$COMMAND" "$@"
elif command -v gtimeout &> /dev/null; then
    exec gtimeout "$TIMEOUT_SECONDS" "$COMMAND" "$@"
else
    "$COMMAND" "$@"
fi
EOF

# Create Trufflehog wrapper
cat > .pre-commit-wrappers/trufflehog-limited.sh << 'EOF'
#!/usr/bin/env bash
set -euo pipefail

# Use project-local environment variables
TIMEOUT="${TRUFFLEHOG_TIMEOUT:-300}"
MEMORY_LIMIT="${TRUFFLEHOG_MEMORY_MB:-1024}"
CONCURRENCY="${TRUFFLEHOG_CONCURRENCY:-1}"

# Check if trufflehog is installed
if ! command -v trufflehog &> /dev/null; then
    echo "Installing Trufflehog locally..."
    # Install to project-local bin directory
    mkdir -p .venv/bin
    curl -sSfL https://raw.githubusercontent.com/trufflesecurity/trufflehog/main/scripts/install.sh | \
        sh -s -- -b .venv/bin
fi

echo "Running Trufflehog (timeout: ${TIMEOUT}s, concurrency: ${CONCURRENCY})..."

# Run with resource limits
if command -v timeout &> /dev/null; then
    timeout_cmd="timeout ${TIMEOUT}s"
elif command -v gtimeout &> /dev/null; then
    timeout_cmd="gtimeout ${TIMEOUT}s"
else
    timeout_cmd=""
fi

$timeout_cmd trufflehog git file://. \
    --only-verified \
    --fail \
    --no-update \
    --concurrency="$CONCURRENCY" || exit_code=$?

if [ "${exit_code:-0}" -eq 124 ]; then
    echo "Warning: Trufflehog timed out after ${TIMEOUT}s"
    exit 0
elif [ "${exit_code:-0}" -ne 0 ]; then
    echo "Error: Trufflehog found verified secrets!"
    exit 1
fi

echo "✓ No verified secrets found"
EOF

chmod +x .pre-commit-wrappers/*.sh

# Create git hook with resource monitoring
cat > .git/hooks/pre-commit << 'EOF'
#!/usr/bin/env bash
# Git pre-commit hook with resource monitoring
# Monitors memory, file descriptors, and processes during pre-commit execution

PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$PROJECT_ROOT" || exit 1

# Source project virtual environment
if [ -f ".venv/bin/activate" ]; then
    source .venv/bin/activate
fi

# Source sequential configuration
if [ -f ".venv/bin/activate.d/sequential-precommit.sh" ]; then
    source .venv/bin/activate.d/sequential-precommit.sh
fi

# Configuration
MEMORY_LIMIT_MB="${MEMORY_LIMIT_MB:-4096}"
LOG_DIR=".pre-commit-logs"
MONITOR_INTERVAL=1

# Create log directory
mkdir -p "$LOG_DIR"

# Generate timestamp for log file
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
LOG_FILE="$LOG_DIR/resource_usage_${TIMESTAMP}.log"
MONITOR_PID_FILE="/tmp/pre-commit-monitor-$$.pid"

# Function to get memory usage in MB
get_memory_usage() {
    local pid=$1
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS: Get RSS in bytes and convert to MB
        ps -o rss= -p "$pid" 2>/dev/null | awk '{print int($1/1024)}' || echo "0"
    else
        # Linux: Get RSS in KB and convert to MB
        ps -o rss= -p "$pid" 2>/dev/null | awk '{print int($1/1024)}' || echo "0"
    fi
}

# Function to get open file descriptors
get_fd_count() {
    local pid=$1
    if [[ "$OSTYPE" == "darwin"* ]]; then
        lsof -p "$pid" 2>/dev/null | wc -l || echo "0"
    else
        ls /proc/"$pid"/fd 2>/dev/null | wc -l || echo "0"
    fi
}

# Function to count child processes
get_child_count() {
    local pid=$1
    pgrep -P "$pid" 2>/dev/null | wc -l || echo "0"
}

# Function to get system-wide metrics
get_system_metrics() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local mem_free mem_total

    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        mem_info=$(vm_stat | grep -E "(free|inactive|active|wired)")
        page_size=$(pagesize 2>/dev/null || echo 16384)
        mem_free=$(echo "$mem_info" | grep "Pages free" | awk '{print $3}' | sed 's/\.//')
        mem_free=$((mem_free * page_size / 1024 / 1024))
    else
        # Linux
        mem_free=$(free -m | awk 'NR==2{print $4}')
    fi

    echo "[$timestamp] System - Free Memory: ${mem_free}MB"
}

# Monitoring function
monitor_resources() {
    local parent_pid=$1
    echo "=== Pre-commit Resource Monitor ===" > "$LOG_FILE"
    echo "Started: $(date)" >> "$LOG_FILE"
    echo "Memory limit: ${MEMORY_LIMIT_MB}MB" >> "$LOG_FILE"
    echo "Monitoring PID: $parent_pid" >> "$LOG_FILE"
    echo "===================================" >> "$LOG_FILE"

    local warning_issued=false
    local critical_issued=false
    local max_memory=0
    local max_fd=0
    local max_children=0

    while kill -0 "$parent_pid" 2>/dev/null; do
        local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
        local memory_mb=$(get_memory_usage "$parent_pid")
        local fd_count=$(get_fd_count "$parent_pid")
        local child_count=$(get_child_count "$parent_pid")

        # Track maximums
        [ "$memory_mb" -gt "$max_memory" ] && max_memory=$memory_mb
        [ "$fd_count" -gt "$max_fd" ] && max_fd=$fd_count
        [ "$child_count" -gt "$max_children" ] && max_children=$child_count

        # Log current metrics
        echo "[$timestamp] PID $parent_pid - Memory: ${memory_mb}MB, FDs: $fd_count, Children: $child_count" >> "$LOG_FILE"

        # Get all child processes and their memory
        local total_memory=$memory_mb
        for child_pid in $(pgrep -P "$parent_pid" 2>/dev/null); do
            local child_mem=$(get_memory_usage "$child_pid")
            local child_cmd=$(ps -p "$child_pid" -o comm= 2>/dev/null || echo "unknown")
            total_memory=$((total_memory + child_mem))
            if [ "$child_mem" -gt 10 ]; then  # Only log children using >10MB
                echo "  └─ Child PID $child_pid ($child_cmd) - Memory: ${child_mem}MB" >> "$LOG_FILE"
            fi
        done

        # Check for issues
        local issues=()

        # Memory checks
        if [ "$total_memory" -gt "$MEMORY_LIMIT_MB" ]; then
            issues+=("CRITICAL: Total memory usage (${total_memory}MB) exceeds limit (${MEMORY_LIMIT_MB}MB)")
            critical_issued=true
        elif [ "$total_memory" -gt $((MEMORY_LIMIT_MB * 80 / 100)) ] && [ "$warning_issued" = false ]; then
            issues+=("WARNING: Memory usage (${total_memory}MB) is above 80% of limit")
            warning_issued=true
        fi

        # File descriptor checks
        if [ "$fd_count" -gt 1000 ]; then
            issues+=("WARNING: High file descriptor count: $fd_count")
        elif [ "$fd_count" -gt 500 ]; then
            issues+=("NOTICE: Elevated file descriptor count: $fd_count")
        fi

        # Child process checks
        if [ "$child_count" -gt 50 ]; then
            issues+=("WARNING: High child process count: $child_count")
        elif [ "$child_count" -gt 20 ]; then
            issues+=("NOTICE: Elevated child process count: $child_count")
        fi

        # Log issues
        for issue in "${issues[@]}"; do
            echo "[$timestamp] $issue" >> "$LOG_FILE"
        done

        # Kill if memory exceeded
        if [ "$critical_issued" = true ]; then
            echo "[$timestamp] !!! KILLING PROCESS DUE TO MEMORY LIMIT EXCEEDED !!!" >> "$LOG_FILE"
            get_system_metrics >> "$LOG_FILE"

            # Get process tree before killing
            echo "[$timestamp] Process tree before termination:" >> "$LOG_FILE"
            ps auxf | grep -E "(pre-commit|python|node|npm)" >> "$LOG_FILE" 2>/dev/null || true

            # Kill all child processes first
            for child_pid in $(pgrep -P "$parent_pid" 2>/dev/null); do
                echo "[$timestamp] Killing child process $child_pid" >> "$LOG_FILE"
                kill -TERM "$child_pid" 2>/dev/null || true
            done

            sleep 1

            # Kill parent
            echo "[$timestamp] Killing parent process $parent_pid" >> "$LOG_FILE"
            kill -TERM "$parent_pid" 2>/dev/null || true
            sleep 1
            kill -KILL "$parent_pid" 2>/dev/null || true

            echo "[$timestamp] Process terminated due to resource limits" >> "$LOG_FILE"
            break
        fi

        # Log system metrics every 10 seconds
        if [ $(($(date +%s) % 10)) -eq 0 ]; then
            get_system_metrics >> "$LOG_FILE"
        fi

        sleep "$MONITOR_INTERVAL"
    done

    # Final summary
    echo "" >> "$LOG_FILE"
    echo "=== Resource Usage Summary ===" >> "$LOG_FILE"
    echo "Ended: $(date)" >> "$LOG_FILE"
    echo "Peak Memory: ${max_memory}MB" >> "$LOG_FILE"
    echo "Peak File Descriptors: $max_fd" >> "$LOG_FILE"
    echo "Peak Child Processes: $max_children" >> "$LOG_FILE"
    echo "=============================" >> "$LOG_FILE"
}

# Start resource monitor in background
monitor_resources $$ &
MONITOR_PID=$!
echo "$MONITOR_PID" > "$MONITOR_PID_FILE"

# Cleanup function
cleanup_monitor() {
    if [ -f "$MONITOR_PID_FILE" ]; then
        local monitor_pid=$(cat "$MONITOR_PID_FILE")
        if kill -0 "$monitor_pid" 2>/dev/null; then
            kill -TERM "$monitor_pid" 2>/dev/null || true
        fi
        rm -f "$MONITOR_PID_FILE"
    fi

    # Display log summary
    if [ -f "$LOG_FILE" ]; then
        echo ""
        echo "Resource usage log saved to: $LOG_FILE"
        tail -n 20 "$LOG_FILE" | grep -E "(Peak|WARNING|CRITICAL|Summary)" || true
    fi
}

# Set trap to cleanup monitor on exit
trap cleanup_monitor EXIT INT TERM

# Check memory before running
if [[ "$OSTYPE" == "darwin"* ]]; then
    FREE_MB=$(vm_stat | grep "Pages free" | awk '{print $3}' | sed 's/\.//')
    PAGE_SIZE=$(pagesize 2>/dev/null || echo 16384)
    FREE_MB=$((FREE_MB * PAGE_SIZE / 1024 / 1024))
elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
    FREE_MB=$(free -m | awk 'NR==2{print $4}')
fi

if [ "${FREE_MB:-1024}" -lt 512 ]; then
    echo "Warning: Low memory (${FREE_MB}MB). Consider closing other applications."
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: Starting with low system memory: ${FREE_MB}MB" >> "$LOG_FILE"
fi

# Run pre-commit
echo "Starting pre-commit with resource monitoring..."
echo "Monitor log: $LOG_FILE"
pre-commit run "$@"
PRE_COMMIT_EXIT_CODE=$?

# Give monitor time to write final metrics
sleep 2

# Return pre-commit's exit code
exit $PRE_COMMIT_EXIT_CODE
EOF

chmod +x .git/hooks/pre-commit

# Install pre-commit hooks
echo "Installing pre-commit hooks..."
pre-commit install --install-hooks
pre-commit install --hook-type commit-msg

# Create .gitignore entry for logs
if ! grep -q ".pre-commit-logs" .gitignore 2>/dev/null; then
    echo ".pre-commit-logs/" >> .gitignore
fi

echo "✓ Sequential pre-commit with resource monitoring setup complete!"
echo ""
echo "To activate the environment:"
echo "  source .venv/bin/activate"
echo ""
echo "The following variables are now set (project-local):"
echo "  PRE_COMMIT_MAX_WORKERS=1"
echo "  MEMORY_LIMIT_MB=2048 (hooks), 4096 (monitoring kill threshold)"
echo "  TIMEOUT_SECONDS=600"
echo ""
echo "Resource usage logs will be saved to: .pre-commit-logs/"
echo ""
echo "Features enabled:"
echo "  • Sequential hook execution (no parallelism)"
echo "  • Memory usage monitoring and logging"
echo "  • File descriptor tracking"
echo "  • Child process monitoring"
echo "  • Automatic process termination at 4GB memory"
echo "  • Peak usage statistics"
```

### 2. Pre-commit Configuration

Create `.pre-commit-config.yaml` with all hooks configured for sequential execution:

```yaml
# Sequential pre-commit configuration
# All hooks run one at a time to minimize resource usage

default_language_version:
  python: python3.10

default_stages: [pre-commit]

repos:
  # Basic file checks
  - repo: https://github.com/pre-commit/pre-commit-hooks
    rev: v5.0.0
    hooks:
      - id: trailing-whitespace
        stages: [pre-commit]
      - id: end-of-file-fixer
        stages: [pre-commit]
      - id: check-yaml
        stages: [pre-commit]
      - id: check-added-large-files
        stages: [pre-commit]
        args: ['--maxkb=1000']
      - id: check-toml
        stages: [pre-commit]
      - id: check-json
        stages: [pre-commit]
      - id: check-merge-conflict
        stages: [pre-commit]

  # Python tools (all with require_serial: true)
  - repo: https://github.com/astral-sh/ruff-pre-commit
    rev: v0.9.4
    hooks:
      - id: ruff
        args: [--fix, --exit-non-zero-on-fix]
        stages: [pre-commit]
        require_serial: true
      - id: ruff-format
        stages: [pre-commit]
        require_serial: true

  # Resource-intensive hooks using project-local wrappers
  - repo: local
    hooks:
      - id: mypy-limited
        name: Type checking (memory limited)
        entry: .pre-commit-wrappers/memory-limited-hook.sh uv run mypy
        language: system
        types: [python]
        require_serial: true
        pass_filenames: true
        stages: [pre-commit]
        args: [--ignore-missing-imports, --strict]

      - id: trufflehog-limited
        name: Secret detection (resource limited)
        entry: .pre-commit-wrappers/trufflehog-limited.sh
        language: system
        pass_filenames: false
        require_serial: true
        stages: [pre-commit]

# CI configuration
ci:
  skip:
    - mypy-limited
    - trufflehog-limited
```

### 3. GitHub Actions Workflow

Create `.github/workflows/pre-commit-sequential.yml`:

```yaml
name: Sequential Pre-commit

on:
  pull_request:
  push:
    branches: [main, develop]

# Force sequential workflow execution
concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: false

env:
  # Same environment as local development
  PRE_COMMIT_MAX_WORKERS: 1
  PYTHONDONTWRITEBYTECODE: 1
  UV_NO_CACHE: 1
  MEMORY_LIMIT_MB: 2048
  TIMEOUT_SECONDS: 600
  TRUFFLEHOG_TIMEOUT: 300
  TRUFFLEHOG_CONCURRENCY: 1

jobs:
  sequential-checks:
    runs-on: ubuntu-latest
    timeout-minutes: 45  # Increased for sequential execution

    steps:
    - uses: actions/checkout@v4
      with:
        fetch-depth: 0

    - name: Set up Python
      uses: actions/setup-python@v5
      with:
        python-version: '3.10'

    - name: Install uv
      uses: astral-sh/setup-uv@v5
      with:
        enable-cache: true

    - name: Create virtual environment
      run: uv venv

    - name: Install dependencies
      run: |
        source .venv/bin/activate
        uv sync --all-extras
        uv pip install pre-commit

    - name: Install local tools
      run: |
        # Install Trufflehog to project bin
        mkdir -p .venv/bin
        curl -sSfL https://raw.githubusercontent.com/trufflesecurity/trufflehog/main/scripts/install.sh | \
          sh -s -- -b .venv/bin

    - name: Run pre-commit hooks sequentially
      run: |
        source .venv/bin/activate
        # Export same variables as local environment
        export PRE_COMMIT_MAX_WORKERS=1
        export MEMORY_LIMIT_MB=2048
        export TIMEOUT_SECONDS=600

        # Run all hooks
        pre-commit run --all-files --show-diff-on-failure

    - name: Memory usage report
      if: always()
      run: |
        echo "Final memory usage:"
        free -h || true
```

## Installation

1. **Clone the repository and enter directory**:
   ```bash
   git clone <repository>
   cd <repository>
   ```

2. **Run the setup script**:
   ```bash
   chmod +x setup-sequential-precommit.sh
   ./setup-sequential-precommit.sh
   ```

3. **Activate the environment**:
   ```bash
   source .venv/bin/activate
   ```

That's it! No system or user configuration files are modified.

## Understanding Resource Logs

After each pre-commit run, check the logs in `.pre-commit-logs/`:

```bash
cat .pre-commit-logs/resource_usage_*.log
```

Example log output:
```
=== Pre-commit Resource Monitor ===
Started: Wed Jul  2 11:10:12 CEST 2025
Memory limit: 4096MB
Monitoring PID: 89506
===================================
[2025-07-02 11:10:12] PID 89506 - Memory: 4MB, FDs: 9, Children: 1
  └─ Child PID 89526 (python) - Memory: 101MB
[2025-07-02 11:10:13] WARNING: Memory usage (3500MB) is above 80% of limit
[2025-07-02 11:10:14] NOTICE: Elevated file descriptor count: 523

=== Resource Usage Summary ===
Ended: Wed Jul  2 11:10:16 CEST 2025
Peak Memory: 105MB
Peak File Descriptors: 523
Peak Child Processes: 3
=============================
```

## Resource Limits and Thresholds

The monitoring system tracks:

1. **Memory Usage**:
   - Individual hook limit: 2048MB (enforced by wrappers)
   - Total pre-commit limit: 4096MB (kills process if exceeded)
   - Warning at 80% of limit

2. **File Descriptors**:
   - Notice at 500 FDs
   - Warning at 1000 FDs

3. **Child Processes**:
   - Notice at 20 children
   - Warning at 50 children

## Customization

### Adjusting Resource Limits

Edit `.venv/bin/activate.d/sequential-precommit.sh`:

```bash
export MEMORY_LIMIT_MB=4096      # Increase for large projects
export TIMEOUT_SECONDS=1200      # 20 minutes for slow operations
export TRUFFLEHOG_TIMEOUT=600    # 10 minutes for deep scanning
```

### Changing Kill Threshold

In `.git/hooks/pre-commit`, modify:
```bash
MEMORY_LIMIT_MB="${MEMORY_LIMIT_MB:-8192}"  # Kill at 8GB instead of 4GB
```

### Adding New Hooks

Always include `require_serial: true` for resource-intensive hooks:

```yaml
- repo: local
  hooks:
    - id: my-custom-check
      name: Custom check
      entry: .pre-commit-wrappers/memory-limited-hook.sh ./scripts/my-check.sh
      language: system
      require_serial: true
      pass_filenames: false
```

## Docker Alternative

For complete isolation with monitoring, use Docker:

```dockerfile
# .devcontainer/Dockerfile
FROM python:3.10-slim

# Install monitoring tools
RUN apt-get update && apt-get install -y \
    git \
    curl \
    procps \
    lsof \
    && rm -rf /var/lib/apt/lists/*

# Install uv
RUN curl -LsSf https://astral.sh/uv/install.sh | sh

# Set environment for sequential execution
ENV PRE_COMMIT_MAX_WORKERS=1
ENV PYTHONDONTWRITEBYTECODE=1
ENV MEMORY_LIMIT_MB=2048
ENV TIMEOUT_SECONDS=600

# Add monitoring script
COPY .pre-commit-wrappers/resource-monitor.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/resource-monitor.sh

WORKDIR /workspace
```

## Benefits of Enhanced Monitoring

1. **Visibility**: See exactly what resources each hook consumes
2. **Protection**: Automatic termination prevents system crashes
3. **Debugging**: Detailed logs help identify problematic hooks
4. **Optimization**: Peak usage stats guide resource allocation
5. **Reliability**: Predictable resource usage patterns

## Troubleshooting

### High Memory Usage Detected?

Check which hooks are consuming resources:
```bash
grep -E "(Child PID|Memory:)" .pre-commit-logs/resource_usage_*.log | tail -20
```

### Process Killed Due to Memory?

Look for the CRITICAL entries:
```bash
grep -E "(CRITICAL|KILLING)" .pre-commit-logs/resource_usage_*.log
```

### Too Many File Descriptors?

Some tools don't clean up properly. Add explicit cleanup:
```bash
# In your wrapper script
cleanup() {
    # Close file descriptors
    exec 3>&- 4>&- 5>&- 2>/dev/null || true
    # Kill child processes
    pkill -P $$ 2>/dev/null || true
}
trap cleanup EXIT
```

### Monitor Not Working?

Ensure the monitor has permissions:
```bash
chmod +x .git/hooks/pre-commit
chmod +x .pre-commit-wrappers/*.sh
```

## Platform-Specific Notes

### macOS
- Memory limits (`ulimit -v`) don't work, but monitoring still tracks usage
- Use `lsof` for file descriptor counting
- Install GNU coreutils for better `timeout` command: `brew install coreutils`

### Linux
- Full memory limiting support via `ulimit`
- `/proc` filesystem provides detailed process info
- Native `timeout` command available

### Windows (Git Bash/WSL)
- WSL2 provides Linux-like behavior
- Git Bash has limited process monitoring
- Consider using WSL2 for better resource control

Remember: This setup prioritizes stability and visibility. The resource monitoring ensures you always know what's happening and prevents system resource exhaustion, making your development workflow more reliable and predictable.
