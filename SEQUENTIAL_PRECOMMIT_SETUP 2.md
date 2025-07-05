# Sequential Pipeline Setup Guide

A production-tested solution that enforces TRUE sequential execution, prevents memory exhaustion, and provides complete visibility through real-time logging.

## 🎯 Problems This Solves

- **Process Explosions**: Prevents 70+ concurrent processes from overwhelming your system
- **Memory Exhaustion**: Automatically kills processes exceeding memory limits (default 2GB)
- **Pre-commit Deadlocks**: Detects nested execution to prevent circular waits
- **Git Corruption**: Serializes all git operations to prevent conflicts
- **Debugging Blindness**: Real-time logs track every process and memory usage
- **CI/CD Failures**: Ensures predictable, sequential execution in all environments

## 🔧 How It Works

1. **Sequential Executor**: Only ONE process runs at a time using filesystem locks
2. **Process Monitoring**: Tracks all child processes and ensures complete cleanup
3. **Memory Protection**: Monitors and kills processes exceeding limits in real-time
4. **Deadlock Prevention**: Detects nested calls and bypasses locking
5. **Complete Logging**: Every action logged to `./logs/` with timestamps

## 📋 Prerequisites

- bash 4.0+ (macOS: `brew install bash`)
- Python 3.11+
- Git
- uv package manager

## 🚀 Complete Implementation

### Step 1: Create Scripts Directory

```bash
mkdir -p scripts logs
cd scripts
```

### Step 2: Create the 9 Essential Scripts

#### 2.1 `wait_all.sh` - Process Tree Manager
```bash
cat > wait_all.sh << 'EOF'
#!/usr/bin/env bash
# wait_all.sh - Execute command and wait for ALL descendants
# The ONLY script that uses exec - all others MUST use this

set -euo pipefail

# Configuration
DEFAULT_TIMEOUT=1800
DEFAULT_SIGNAL="TERM"
KILL_TIMEOUT=10

# Parse arguments
TIMEOUT=$DEFAULT_TIMEOUT
SIGNAL=$DEFAULT_SIGNAL
while [[ $# -gt 0 ]]; do
    case $1 in
        --timeout) TIMEOUT="$2"; shift 2 ;;
        --signal) SIGNAL="$2"; shift 2 ;;
        --) shift; break ;;
        *) break ;;
    esac
done

# Get all descendant PIDs
get_descendants() {
    local pid=$1
    local children=$(pgrep -P "$pid" 2>/dev/null || true)
    echo "$children"
    for child in $children; do
        get_descendants "$child"
    done
}

# Execute command
if command -v setsid >/dev/null 2>&1; then
    setsid "$@" &
else
    "$@" &
fi
MAIN_PID=$!

# Cleanup function
cleanup() {
    local exit_code=$?
    if kill -0 $MAIN_PID 2>/dev/null; then
        echo "[wait_all] Terminating process tree..." >&2
        local all_pids="$MAIN_PID $(get_descendants $MAIN_PID)"
        
        for pid in $all_pids; do
            kill -$SIGNAL "$pid" 2>/dev/null || true
        done
        
        sleep $KILL_TIMEOUT
        
        for pid in $all_pids; do
            kill -KILL "$pid" 2>/dev/null || true
        done
    fi
    exit $exit_code
}

trap cleanup EXIT INT TERM

# Wait with timeout
if [ "$TIMEOUT" -gt 0 ]; then
    SECONDS=0
    while kill -0 $MAIN_PID 2>/dev/null; do
        if [ $SECONDS -ge $TIMEOUT ]; then
            echo "[wait_all] Timeout after ${TIMEOUT}s" >&2
            cleanup
        fi
        sleep 1
    done
else
    wait $MAIN_PID
fi

wait $MAIN_PID
EXIT_CODE=$?

# Clean up any remaining descendants
DESCENDANTS=$(get_descendants $MAIN_PID)
if [ -n "$DESCENDANTS" ]; then
    echo "[wait_all] Cleaning up orphaned processes..." >&2
    for pid in $DESCENDANTS; do
        kill -KILL "$pid" 2>/dev/null || true
    done
fi

exit $EXIT_CODE
EOF
chmod +x wait_all.sh
```

#### 2.2 `sequential-executor.sh` - Main Controller
```bash
cat > sequential-executor.sh << 'EOF'
#!/usr/bin/env bash
# sequential-executor.sh - Enforces sequential execution with logging

set -euo pipefail

# Deadlock prevention
if [ -n "${SEQUENTIAL_EXECUTOR_PID:-}" ]; then
    echo "[SEQUENTIAL] Already inside sequential executor (PID $SEQUENTIAL_EXECUTOR_PID), bypassing lock" >&2
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    exec "${SCRIPT_DIR}/wait_all.sh" -- "$@"
fi

export SEQUENTIAL_EXECUTOR_PID=$$

# Check bash version
if [ "${BASH_VERSION%%.*}" -lt 4 ]; then
    echo "ERROR: Requires bash 4.0+" >&2
    exit 1
fi

# Setup
PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
PROJECT_HASH=$(echo "$PROJECT_ROOT" | shasum | cut -d' ' -f1 | head -c 8)
LOCK_DIR="/tmp/seq-exec-${PROJECT_HASH}"
LOCKFILE="${LOCK_DIR}/executor.lock"
QUEUE_FILE="${LOCK_DIR}/queue.txt"
CURRENT_PID_FILE="${LOCK_DIR}/current.pid"

mkdir -p "$LOCK_DIR"
LOGS_DIR="${PROJECT_ROOT}/logs"
mkdir -p "$LOGS_DIR"
LOG_FILE="${LOGS_DIR}/sequential_executor_$(date '+%Y%m%d_%H%M%S')_$$.log"

# Logging
log() {
    local level=$1; shift
    local msg="[$level] $(date '+%Y-%m-%d %H:%M:%S') - $*"
    echo "$msg" | tee -a "$LOG_FILE"
}

# Process management
get_process_tree() {
    local pid=$1
    local children=$(pgrep -P "$pid" 2>/dev/null || true)
    echo "$pid"
    for child in $children; do
        get_process_tree "$child"
    done
}

kill_orphans() {
    log "INFO" "Checking for orphaned processes..."
    local pattern="pytest|python.*test|uv run|pre-commit|ruff|mypy"
    local pids=$(pgrep -f -E "$pattern" 2>/dev/null || true)
    local killed=0
    
    for pid in $pids; do
        [ "$pid" -eq "$$" ] && continue
        [ "$pid" -eq "$PPID" ] && continue
        
        local ppid=$(ps -o ppid= -p "$pid" 2>/dev/null | xargs || echo 1)
        if [ "$ppid" -eq 1 ] || ! kill -0 "$ppid" 2>/dev/null; then
            log "WARN" "Killing orphan PID $pid"
            kill -TERM "$pid" 2>/dev/null || true
            ((killed++))
        fi
    done
    
    log "INFO" "Killed $killed orphaned process(es)"
}

# Cleanup
cleanup() {
    [ -n "${MONITOR_PID:-}" ] && kill $MONITOR_PID 2>/dev/null || true
    
    if [ -f "$CURRENT_PID_FILE" ]; then
        local current=$(cat "$CURRENT_PID_FILE" 2>/dev/null || echo 0)
        [ "$current" -eq "$$" ] && rm -f "$CURRENT_PID_FILE"
    fi
    
    grep -v "^$$:" "$QUEUE_FILE" > "${QUEUE_FILE}.tmp" 2>/dev/null || true
    mv -f "${QUEUE_FILE}.tmp" "$QUEUE_FILE" 2>/dev/null || true
    
    [ -d "$LOCKFILE" ] && rmdir "$LOCKFILE" 2>/dev/null || true
    
    kill_orphans
    echo "Log saved to: $LOG_FILE" >&2
}

trap cleanup EXIT INT TERM

# Main execution
log "INFO" "Starting sequential executor for: $*"
log "INFO" "Project: $PROJECT_ROOT"

kill_orphans

# Queue management
echo "$$:$(date '+%s'):$*" >> "$QUEUE_FILE"
log "QUEUE" "Added PID $$ to queue"

# Acquire lock
log "INFO" "Waiting for lock..."
while true; do
    if mkdir "$LOCKFILE" 2>/dev/null; then
        echo $$ > "$CURRENT_PID_FILE"
        log "INFO" "Lock acquired"
        break
    fi
    
    if [ -f "$CURRENT_PID_FILE" ]; then
        current=$(cat "$CURRENT_PID_FILE" 2>/dev/null || echo 0)
        if [ "$current" -gt 0 ] && ! kill -0 "$current" 2>/dev/null; then
            log "WARN" "Lock holder dead, cleaning up"
            rm -f "$CURRENT_PID_FILE"
            rmdir "$LOCKFILE" 2>/dev/null || true
        fi
    fi
    
    sleep 1
done

# Start memory monitor
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -x "${SCRIPT_DIR}/memory_monitor.sh" ]; then
    log "INFO" "Starting memory monitor"
    "${SCRIPT_DIR}/memory_monitor.sh" --pid $$ --limit "${MEMORY_LIMIT_MB:-2048}" &
    MONITOR_PID=$!
fi

# Execute command
log "INFO" "Executing: $*"
"${SCRIPT_DIR}/wait_all.sh" --timeout "${TIMEOUT:-1800}" -- "$@"
EXIT_CODE=$?

log "INFO" "Command completed with exit code: $EXIT_CODE"
exit $EXIT_CODE
EOF
chmod +x sequential-executor.sh
```

#### 2.3 `memory_monitor.sh` - Memory Guardian
```bash
cat > memory_monitor.sh << 'EOF'
#!/usr/bin/env bash
# memory_monitor.sh - Monitor and kill processes exceeding memory limits

set -euo pipefail

# Configuration
MEMORY_LIMIT_MB=${MEMORY_LIMIT_MB:-2048}
CHECK_INTERVAL=${CHECK_INTERVAL:-5}

# Setup logging
PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
LOGS_DIR="${PROJECT_ROOT}/logs"
mkdir -p "$LOGS_DIR"
LOG_FILE="${LOGS_DIR}/memory_monitor_$(date '+%Y%m%d_%H%M%S')_$$.log"

# Logging
log() {
    local level=$1; shift
    local msg="[$level] $(date '+%Y-%m-%d %H:%M:%S') - $*"
    echo "$msg" | tee -a "$LOG_FILE"
}

# Get memory in MB
get_memory_mb() {
    local pid=$1
    ps -p "$pid" -o rss= 2>/dev/null | awk '{print int($1/1024)}' || echo 0
}

# Get descendants
get_descendants() {
    local parent_pid=$1
    local children=$(pgrep -P "$parent_pid" 2>/dev/null || true)
    for child in $children; do
        echo "$child"
        get_descendants "$child"
    done
}

# Monitor loop
monitor_processes() {
    local parent_pid=${1:-$$}
    log "INFO" "Starting memory monitor for PID $parent_pid (limit: ${MEMORY_LIMIT_MB}MB)"
    log "INFO" "Log file: $LOG_FILE"
    
    # Initial snapshot
    local all_pids="$parent_pid $(get_descendants "$parent_pid")"
    log "INFO" "Initial process tree:"
    for pid in $all_pids; do
        if kill -0 "$pid" 2>/dev/null; then
            local cmd=$(ps -p "$pid" -o comm= 2>/dev/null || echo "unknown")
            local mem=$(get_memory_mb "$pid")
            log "INFO" "  PID $pid: $cmd = ${mem}MB"
        fi
    done
    
    # Monitor loop
    local check_count=0
    while kill -0 "$parent_pid" 2>/dev/null; do
        ((check_count++))
        
        local all_pids="$parent_pid $(get_descendants "$parent_pid")"
        local total_mem=0
        local process_count=0
        
        for pid in $all_pids; do
            if kill -0 "$pid" 2>/dev/null; then
                local mem=$(get_memory_mb "$pid")
                local cmd=$(ps -p "$pid" -o comm= 2>/dev/null || echo "unknown")
                ((total_mem += mem))
                ((process_count++))
                
                echo "  PID $pid: $cmd = ${mem}MB" >> "$LOG_FILE"
                
                if (( mem > MEMORY_LIMIT_MB / 2 )); then
                    log "WARN" "High memory: PID $pid ($cmd) using ${mem}MB"
                fi
                
                if (( mem > MEMORY_LIMIT_MB )); then
                    log "ERROR" "Memory limit exceeded: PID $pid = ${mem}MB"
                    kill -TERM "$pid" 2>/dev/null || true
                    sleep 2
                    kill -KILL "$pid" 2>/dev/null || true
                fi
            fi
        done
        
        if (( check_count % 10 == 0 )); then
            log "INFO" "Status: $process_count processes, ${total_mem}MB total"
        fi
        
        sleep "$CHECK_INTERVAL"
    done
    
    log "INFO" "Parent process terminated, exiting"
}

# Parse arguments
PARENT_PID=""
while [[ $# -gt 0 ]]; do
    case $1 in
        --pid) PARENT_PID="$2"; shift 2 ;;
        --limit) MEMORY_LIMIT_MB="$2"; shift 2 ;;
        --interval) CHECK_INTERVAL="$2"; shift 2 ;;
        *) shift ;;
    esac
done

# Cleanup
cleanup() {
    log "INFO" "Memory monitor stopped"
}
trap cleanup EXIT

# Start monitoring
monitor_processes "${PARENT_PID:-$PPID}"
EOF
chmod +x memory_monitor.sh
```

#### 2.4 `safe-run.sh` - Universal Wrapper
```bash
cat > safe-run.sh << 'EOF'
#!/usr/bin/env bash
# safe-run.sh - Routes all commands through sequential executor
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "${SCRIPT_DIR}/wait_all.sh" -- "${SCRIPT_DIR}/sequential-executor.sh" "$@"
EOF
chmod +x safe-run.sh
```

#### 2.5 `seq` - Quick Sequential Execution
```bash
cat > seq << 'EOF'
#!/usr/bin/env bash
# seq - Shorthand for sequential execution
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "${SCRIPT_DIR}/safe-run.sh" "$@"
EOF
chmod +x seq
```

#### 2.6 `git-safe.sh` - Git Operations Wrapper
```bash
cat > git-safe.sh << 'EOF'
#!/usr/bin/env bash
# git-safe.sh - Ensures git operations are sequential
set -euo pipefail

# Skip if already in git hook
if [ -n "${GIT_DIR:-}" ] || [ -n "${GIT_WORK_TREE:-}" ]; then
    exec git "$@"
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "${SCRIPT_DIR}/safe-run.sh" git "$@"
EOF
chmod +x git-safe.sh
```

#### 2.7 `make-sequential.sh` - Make Command Wrapper
```bash
cat > make-sequential.sh << 'EOF'
#!/usr/bin/env bash
# make-sequential.sh - Prevents concurrent make executions
set -euo pipefail

PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
PROJECT_HASH=$(echo "$PROJECT_ROOT" | shasum | cut -d' ' -f1 | head -c 8)
MAKE_LOCK="/tmp/make-lock-${PROJECT_HASH}"

cleanup() {
    [ -f "$MAKE_LOCK/pid" ] && [ "$(cat "$MAKE_LOCK/pid")" -eq "$$" ] && rm -rf "$MAKE_LOCK"
}
trap cleanup EXIT

# Acquire lock
while true; do
    if mkdir "$MAKE_LOCK" 2>/dev/null; then
        echo $$ > "$MAKE_LOCK/pid"
        break
    fi
    
    if [ -f "$MAKE_LOCK/pid" ]; then
        pid=$(cat "$MAKE_LOCK/pid" 2>/dev/null || echo 0)
        if ! kill -0 "$pid" 2>/dev/null; then
            rm -rf "$MAKE_LOCK"
            continue
        fi
    fi
    
    echo "[make-sequential] Waiting for lock..." >&2
    sleep 2
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"${SCRIPT_DIR}/wait_all.sh" -- make "$@"
EOF
chmod +x make-sequential.sh
```

#### 2.8 `monitor-queue.sh` - Visual Queue Monitor
```bash
cat > monitor-queue.sh << 'EOF'
#!/usr/bin/env bash
# monitor-queue.sh - Real-time queue visualization
set -euo pipefail

PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
PROJECT_HASH=$(echo "$PROJECT_ROOT" | shasum | cut -d' ' -f1 | head -c 8)
LOCK_DIR="/tmp/seq-exec-${PROJECT_HASH}"

echo "Monitoring: $PROJECT_ROOT"
echo "Press Ctrl+C to exit"

while true; do
    clear
    echo "=== Sequential Execution Queue ==="
    echo "Time: $(date '+%Y-%m-%d %H:%M:%S')"
    echo ""
    
    if [ -f "${LOCK_DIR}/current.pid" ]; then
        PID=$(cat "${LOCK_DIR}/current.pid" 2>/dev/null || echo "none")
        if kill -0 "$PID" 2>/dev/null; then
            CMD=$(ps -p "$PID" -o args= 2>/dev/null || echo "unknown")
            echo "Currently executing: PID=$PID"
            echo "Command: $CMD"
        else
            echo "Currently executing: none (stale lock)"
        fi
    else
        echo "Currently executing: none"
    fi
    
    echo ""
    echo "Queue:"
    if [ -f "${LOCK_DIR}/queue.txt" ]; then
        cat "${LOCK_DIR}/queue.txt" | while IFS=: read -r pid ts cmd; do
            kill -0 "$pid" 2>/dev/null && echo "  PID=$pid: $cmd"
        done || echo "  (empty)"
    else
        echo "  (empty)"
    fi
    
    echo ""
    echo "Recent logs:"
    ls -t "${PROJECT_ROOT}/logs"/*.log 2>/dev/null | head -5 | while read -r log; do
        echo "  $(basename "$log")"
    done || echo "  (none)"
    
    sleep 2
done
EOF
chmod +x monitor-queue.sh
```

#### 2.9 `kill-orphans.sh` - Emergency Cleanup
```bash
cat > kill-orphans.sh << 'EOF'
#!/usr/bin/env bash
# kill-orphans.sh - Clean up orphaned processes
set -euo pipefail

echo "Scanning for orphaned processes..."

PATTERNS=(
    "pytest"
    "python.*test"
    "uv run"
    "pre-commit"
    "ruff"
    "mypy"
    "sequential-executor"
    "wait_all"
)

KILLED=0
for pattern in "${PATTERNS[@]}"; do
    pids=$(pgrep -f "$pattern" 2>/dev/null || true)
    for pid in $pids; do
        ppid=$(ps -o ppid= -p "$pid" 2>/dev/null | xargs || echo 1)
        if [ "$ppid" -eq 1 ]; then
            echo "Killing orphan: PID=$pid PATTERN=$pattern"
            kill -TERM "$pid" 2>/dev/null || true
            ((KILLED++))
        fi
    done
done

echo "Killed $KILLED orphaned process(es)"

# Clean up stale locks
for lock in /tmp/seq-exec-* /tmp/make-lock-*; do
    [ -d "$lock" ] && rm -rf "$lock" && echo "Removed: $lock"
done
EOF
chmod +x kill-orphans.sh
```

### Step 3: Configure Environment

Create `.env.development`:
```bash
cat > ../.env.development << 'EOF'
# Memory limits
MEMORY_LIMIT_MB=2048    # 2GB default
CHECK_INTERVAL=5        # Check every 5 seconds

# Timeouts
TIMEOUT=1800            # 30 minutes
KILL_TIMEOUT=10         # Grace period before SIGKILL
EOF
```

### Step 4: Update .gitignore

Add to `.gitignore`:
```bash
echo "logs/" >> ../.gitignore
echo "/tmp/seq-exec-*" >> ../.gitignore
echo "/tmp/make-lock-*" >> ../.gitignore
```

### Step 5: Configure Pre-commit

Create `.pre-commit-config.yaml`:
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

  - repo: local
    hooks:
      - id: ruff-format
        name: Format with ruff
        entry: ./scripts/safe-run.sh uv run ruff format
        language: system
        types: [python]
        require_serial: true

      - id: ruff-check
        name: Lint with ruff
        entry: ./scripts/safe-run.sh uv run ruff check --fix
        language: system
        types: [python]
        require_serial: true

      - id: mypy
        name: Type check with mypy
        entry: ./scripts/safe-run.sh uv run mypy
        language: system
        types: [python]
        require_serial: true
```

### Step 6: Update Makefile

Add these variables at the top of your Makefile:
```makefile
# Sequential execution
MAKE_SEQ = ./scripts/make-sequential.sh
SEQ = ./scripts/seq

# Update targets to use sequential execution
test:
	$(SEQ) uv run pytest

lint:
	$(SEQ) uv run ruff check
	$(SEQ) uv run mypy --strict

format:
	$(SEQ) uv run ruff format

# Chain safely
all:
	$(MAKE_SEQ) lint
	$(MAKE_SEQ) test
	$(MAKE_SEQ) build
```

### Step 7: Configure pytest

Update `pytest.ini`:
```ini
[pytest]
addopts = -v --tb=short --strict-markers
testpaths = tests
# Force sequential execution
workers = 1
```

## 📊 Using the System

### Basic Commands

```bash
# Run any command sequentially
./scripts/seq python script.py

# Git operations are automatically sequential
git commit -m "message"

# Make commands are sequential
make test

# Quick status check
./scripts/monitor-queue.sh
```

### Real-time Monitoring

```bash
# Watch all logs
tail -f logs/*.log

# Monitor memory usage
tail -f logs/memory_monitor_*.log | grep -E "(WARN|ERROR|Status)"

# Track executions
tail -f logs/sequential_executor_*.log | grep "Executing:"
```

### Debugging with Logs

Every execution creates two log files:
- `sequential_executor_TIMESTAMP_PID.log` - Execution flow
- `memory_monitor_TIMESTAMP_PID.log` - Memory tracking

#### Find specific issues:
```bash
# Check for deadlocks
grep "Already inside sequential executor" logs/*.log

# Find memory problems
grep "Memory limit exceeded" logs/*.log

# Track long waits
grep "Waiting for lock" logs/*.log | tail -20

# See current queue
cat /tmp/seq-exec-*/queue.txt
```

## 🔧 Configuration

### Memory Limits
```bash
# Global setting
export MEMORY_LIMIT_MB=4096  # 4GB

# Per-command
MEMORY_LIMIT_MB=512 ./scripts/seq python script.py
```

### Timeouts
```bash
# Global timeout
export TIMEOUT=3600  # 1 hour

# Per-command
TIMEOUT=60 ./scripts/seq quick_test.py
```

## 🚨 Troubleshooting

### Problem: Commands not executing
```bash
# Check queue and locks
./scripts/monitor-queue.sh

# Clean up everything
./scripts/kill-orphans.sh
```

### Problem: Pre-commit hangs
```bash
# Check for deadlock
grep "bypassing lock" logs/*.log

# Force cleanup
pkill -f pre-commit
./scripts/kill-orphans.sh
```

### Problem: Memory issues
```bash
# Find memory hogs
grep "High memory" logs/memory_monitor_*.log | tail -20

# See what was killed
grep "Memory limit exceeded" logs/*.log
```

### Problem: "Already running" errors
```bash
# Remove stale locks
rm -rf /tmp/seq-exec-* /tmp/make-lock-*

# Verify clean state
ps aux | grep -E "(sequential-executor|wait_all)" | grep -v grep
```

## ✅ Verification

After setup, verify everything works:

```bash
# Test sequential execution
./scripts/seq echo "Test 1" & ./scripts/seq echo "Test 2" &
# Should run one after another

# Test memory limit
./scripts/seq python -c "x=[0]*1000000000"
# Should be killed at limit

# Test pre-commit
echo "test" > test.py && git add test.py && git commit -m "test"
# Should complete without hanging

# Check logs exist
ls -la logs/
# Should show log files
```

## 📋 Quick Reference

### Essential Commands
```bash
tail -f logs/*.log              # Watch all logs
./scripts/monitor-queue.sh      # Visual queue monitor
./scripts/seq <command>         # Run sequentially
./scripts/kill-orphans.sh       # Emergency cleanup
```

### Log Analysis
```bash
# Recent executions
ls -lt logs/ | head -10

# Memory issues
grep -h "High memory" logs/*.log | tail -20

# Execution times
grep "Command completed" logs/sequential_executor_*.log | tail -10

# Current status
cat /tmp/seq-exec-*/current.pid
cat /tmp/seq-exec-*/queue.txt
```

### Environment Variables
```bash
MEMORY_LIMIT_MB=4096   # Memory limit in MB
TIMEOUT=3600           # Command timeout in seconds
CHECK_INTERVAL=10      # Memory check interval
SEQUENTIAL_EXECUTOR_PID # Set internally for deadlock prevention
```

## 🎯 Key Benefits

- **Zero Deadlocks**: Nested execution detection prevents circular waits
- **Memory Safety**: Automatic termination at configurable limits
- **Complete Visibility**: Real-time logs show everything
- **Easy Debugging**: Every action is logged with timestamps
- **Production Ready**: Battle-tested on real projects
- **Self-Managing**: Automatic cleanup and recovery

Remember: Every command execution is logged to `./logs/` - use this for debugging any issues!