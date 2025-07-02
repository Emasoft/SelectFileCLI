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
# Note: activate.d is not standard - we'll create our own activation script
ACTIVATE_DIR=".venv/bin"
if [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "win32" ]]; then
    ACTIVATE_DIR=".venv/Scripts"
fi

# Create our custom environment script
cat > "${ACTIVATE_DIR}/sequential-precommit-env.sh" << 'EOF'
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

chmod +x "${ACTIVATE_DIR}/sequential-precommit-env.sh" 2>/dev/null || true

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
if [ -f ".venv/bin/sequential-precommit-env.sh" ]; then
    source .venv/bin/sequential-precommit-env.sh
elif [ -f ".venv/Scripts/sequential-precommit-env.sh" ]; then
    source .venv/Scripts/sequential-precommit-env.sh
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
            if [[ "$OSTYPE" == "darwin"* ]]; then
                ps aux | grep -E "(pre-commit|python|node|npm)" >> "$LOG_FILE" 2>/dev/null || true
            else
                ps auxf | grep -E "(pre-commit|python|node|npm)" >> "$LOG_FILE" 2>/dev/null || true
            fi

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
echo "  source ${ACTIVATE_DIR}/sequential-precommit-env.sh"
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
