# Universal Sequential Pre-commit Setup Guide

A complete recipe for implementing TRUE sequential execution in any project. This prevents process explosions and memory exhaustion by ensuring only ONE process runs at a time.

## Critical Safety Measures

1. **Sequential Executor**: Only ONE process runs at a time
2. **wait_all.sh**: Ensures complete process tree termination
3. **No exec commands**: All scripts use wait_all.sh instead
4. **Test safety**: Subprocess calls routed through sequential executor
5. **Pytest hooks**: Force sequential test execution

## Prerequisites

- Python 3.11+
- Git
- bash 4.0+ (macOS users: install via Homebrew)
- uv (`curl -LsSf https://astral.sh/uv/install.sh | sh`)

## Setup Instructions

### 1. Create Core Scripts

#### A. wait_all.sh - Process Completion Manager
- NEVER USE EXEC IN SCRIPTS FOR THE DEV PIPELINE!! Use `wait_all.sh` instead!!

Create `scripts/wait_all.sh`:

```bash
#!/usr/bin/env bash
# wait_all.sh — Execute a command, wait for every descendant, with optional
#               timeout, retries, JSON/log output, and configurable kill signal.
#
# -------------------------------------------------------------------------
# USAGE
#   ./wait_all.sh [OPTIONS] -- <command and args…>
#
#   (Legacy single-string form, still supported)
#   ./wait_all.sh [OPTIONS] "<command>"
#
# OPTIONS
#   --verbose                Emit internal progress messages to stderr
#   --log <file>             Append per-try stdout, stderr & exit status to <file>
#   --json                   Print a JSON object instead of raw stdout/stderr
#                            (uses jq if available, otherwise base64-encodes)
#   --timeout <sec>          Abort after SEC seconds (0 ⇒ no timeout)
#   --kill-signal <sig>      Signal sent on timeout (default SIGTERM)
#   --retry <N>              Retry up to N additional times after non-zero exit
#                            or timeout (0 ⇒ no retries)
#   --help                   Show this help text and exit 0
#
# EXIT CODES
#   0    Success (from last attempt)
#   1    Bad usage / option error
#   124  Command killed by timeout (same as GNU timeout(1))
#   *    Any other code is the wrapped command's exit status
#
# NOTES
#   • The command is started in its own **process group**; on timeout we send the
#     chosen signal to the whole group so every descendant is terminated.
#   • On macOS the system Bash (3.2) lacks some modern features; using Homebrew
#     Bash ≥ 5 is recommended. The shebang (`/usr/bin/env bash`) will pick it up
#     automatically if it's first in your PATH.
#
# -------------------------------------------------------------------------
# EXAMPLES
#
# 🔹 Basic usage:
#     ./wait_all.sh -- echo echo hello
#
# 🔹 Verbose mode:
#     ./wait_all.sh --verbose -- bash -c 'sleep 1 & sleep 2 & wait'
#
# 🔹 Logging output:
#     ./wait_all.sh --log out.log -- python3 -c 'print(42)'
#
# 🔹 JSON output:
#     ./wait_all.sh --json -- bash -c 'echo out; echo err >&2; exit 3'
#
# 🔹 Kill if it takes too long:
#     ./wait_all.sh --timeout 5 -- sleep 10
#
# 🔹 Use SIGKILL instead of SIGTERM on timeout:
#     ./wait_all.sh --timeout 5 --kill-signal SIGKILL -- sleep 10
#
# 🔹 Retry command up to 3 times:
#     ./wait_all.sh --retry 3 -- bash -c 'echo fail; exit 1'
#
# 🔹 Retry on timeout:
#     ./wait_all.sh --timeout 2 --retry 2 -- sleep 5
#
# 🔹 Combine all features:
#     ./wait_all.sh --timeout 3 --kill-signal SIGKILL --retry 2 \
#                   --verbose --log out.log --json -- \
#                   bash -c 'sleep 5; echo done'
#
# 🔹 Capture output into a variable:
#     result=$(./wait_all.sh -- echo foo)
#     echo "Got: $result"
#
# -------------------------------------------------------------------------

# ─────────────────────────── Strict-mode & traps ──────────────────────────
set -Eeuo pipefail                        # abort on error, unset var, or pipe fail

die()   { printf 'wait_all: %s\n' "$*" >&2; exit 1; }

# Print header up to the first totally blank line *after* EXAMPLES divider
usage() {
  awk '/^# EXAMPLES/{ex=1} ex && /^# *$/{exit} ex' "$0"
}

# List of temporary files created with mktemp; cleaned on any exit
TEMP_FILES=()
cleanup() { rm -f -- "${TEMP_FILES[@]:-}"; }
trap cleanup EXIT
trap 'die "unexpected error on line $LINENO"' ERR

# ───────────────────────── Helpers: validation ────────────────────────────
is_integer() { [[ $1 =~ ^[0-9]+$ ]]; }

is_valid_signal() {
  local sig=$1
  # numeric? → accept if integer
  if [[ $sig =~ ^[0-9]+$ ]]; then
    return 0
  fi
  # name? → check against kill -l output (portable across BSD & GNU)
  kill -l | tr ' ' '\n' | grep -qiE "^${sig}$"
}

# ───────────────────────── Default option values ──────────────────────────
VERBOSE=0
JSON=0
LOG_FILE=""
TIMEOUT=0
KILL_SIGNAL="SIGTERM"
RETRY_MAX=0
CMD=()                           # array; preserves spaces for modern form
LEGACY_CMD_STRING=""             # non-empty only for the old single-string form

# ───────────────────────────── Option parsing ─────────────────────────────
while (( $# )); do
  case $1 in
    --verbose) VERBOSE=1 ;;
    --json)    JSON=1 ;;
    --log)
        shift || die "--log needs a filename"
        LOG_FILE=$1 ;;
    --timeout)
        shift || die "--timeout needs a value"
        is_integer "$1" || die "--timeout must be a non-negative integer"
        TIMEOUT=$1 ;;
    --kill-signal)
        shift || die "--kill-signal needs a value"
        is_valid_signal "$1" || die "unknown signal: $1"
        KILL_SIGNAL=$1 ;;
    --retry)
        shift || die "--retry needs a value"
        is_integer "$1" || die "--retry must be a non-negative integer"
        RETRY_MAX=$1 ;;
    --help)    usage; exit 0 ;;
    --)        shift; CMD=("$@"); break ;;   # modern form: everything after -- is cmd
    --*)       die "unknown option: $1" ;;
    *)         # legacy single-string form (maintained for backward compatibility)
               LEGACY_CMD_STRING=$1; break ;;
  esac
  shift
done

if [[ -z $LEGACY_CMD_STRING && ${#CMD[@]} -eq 0 ]]; then
  die "no command specified.  see --help"
fi

(( VERBOSE )) && {
  if [[ -n $LEGACY_CMD_STRING ]]; then
    printf '[wait_all] Legacy command string: %s\n' "$LEGACY_CMD_STRING" >&2
  else
    printf '[wait_all] Command array: %q\n' "${CMD[@]}" >&2
  fi
}

# ─────────────────────── JSON/encoding helper function ────────────────────
json_encode() {
  local out=$1 err=$2 code=$3
  if command -v jq >/dev/null 2>&1; then
    jq -n --arg out "$out" --arg err "$err" --argjson code "$code" \
       '{stdout:$out, stderr:$err, exit_code:$code}'
  else
    printf '{"stdout_b64":"%s","stderr_b64":"%s","exit_code":%d}\n' \
           "$(printf %s "$out" | base64)" \
           "$(printf %s "$err" | base64)" \
           "$code"
    echo "# (stdout/stderr were base64-encoded because jq is absent)" >&2
  fi
}

# ────────────────── Function: run the command once (one try) ──────────────
run_once() {
  local attempt=$1
  local tmp_out tmp_err
  tmp_out=$(mktemp) && TEMP_FILES+=("$tmp_out")
  tmp_err=$(mktemp) && TEMP_FILES+=("$tmp_err")

  (( VERBOSE )) && echo "[wait_all] Try #$attempt → launching…" >&2

  # Start the command in a new session (setsid) so it gets its own PGID
  if [[ -n $LEGACY_CMD_STRING ]]; then
    setsid bash -c "$LEGACY_CMD_STRING" >"$tmp_out" 2>"$tmp_err" &
  else
    setsid "${CMD[@]}" >"$tmp_out" 2>"$tmp_err" &
  fi
  local main_pid=$!
  local pgid
  pgid=$(ps -o pgid= "$main_pid" | tr -d ' ')

  local timed_out=0 exit_code=0
  local start_ns deadline_ns now_ns

  if (( TIMEOUT > 0 )); then
    start_ns=$(date +%s%N)
    (( deadline_ns = start_ns + TIMEOUT*1000000000 ))
  fi

  # ---- monitor main process until it ends or we hit the deadline ----
  while kill -0 "$main_pid" 2>/dev/null; do
    sleep 0.1
    if (( TIMEOUT > 0 )); then
      now_ns=$(date +%s%N)
      if (( now_ns >= deadline_ns )); then
        (( VERBOSE )) && \
          echo "[wait_all] Timeout ${TIMEOUT}s → ${KILL_SIGNAL} PGID $pgid" >&2
        kill "-$KILL_SIGNAL" "-$pgid" 2>/dev/null || true
        timed_out=1
        break
      fi
    fi
  done

  wait "$main_pid" 2>/dev/null || true    # collect exit status quietly

  # spin until every process in the group is gone
  while pgrep -g "$pgid" >/dev/null 2>&1; do sleep 0.05; done

  if (( timed_out )); then
    exit_code=124
  else
    exit_code=$?
  fi

  local stdout stderr
  stdout=$(<"$tmp_out")
  stderr=$(<"$tmp_err")

  # ------------ optional log file -----------------------------------------
  if [[ -n $LOG_FILE ]]; then
    {
      echo "=== TRY #$attempt ==="
      echo "CMD : ${LEGACY_CMD_STRING:-${CMD[*]}}"
      echo "STDOUT:"
      printf '%s\n' "$stdout"
      echo "STDERR:"
      printf '%s\n' "$stderr"
      echo "EXIT : $exit_code"
      (( timed_out )) && echo "TIMEOUT after ${TIMEOUT}s"
      echo
    } >>"$LOG_FILE"
  fi

  # ------------- user-visible output --------------------------------------
  if (( JSON )); then
    json_encode "$stdout" "$stderr" "$exit_code"
  else
    printf '%s' "$stdout"
    [[ -n $stderr ]] && printf '%s' "$stderr" >&2
  fi

  (( VERBOSE )) && \
    echo "[wait_all] Try #$attempt finished with exit $exit_code" >&2
  (( timed_out )) && echo "[wait_all]   (timeout)" >&2

  return "$exit_code"
}

# ───────────────────────── Retry orchestration loop ───────────────────────
for (( attempt=1; ; ++attempt )); do
  run_once "$attempt"
  status=$?
  if (( status == 0 )); then exit 0; fi
  if (( attempt > RETRY_MAX )); then
    (( VERBOSE )) && echo "[wait_all] No retries left; exiting $status" >&2
    exit "$status"
  fi
  (( VERBOSE )) && \
    echo "[wait_all] attempt $attempt failed (exit $status) —" \
         "retrying $(( RETRY_MAX - attempt + 1 )) more time(s)…" >&2
done
```

#### B. Sequential Executor

Create `scripts/sequential-executor.sh`:

```bash
#!/usr/bin/env bash
# sequential-executor.sh - TRUE sequential execution with orphan management
#
# GUARANTEES:
# 1. Only ONE process runs at a time - NO exceptions
# 2. Waits INDEFINITELY for previous process to complete
# 3. Detects and kills orphaned processes
# 4. Maintains process genealogy for cleanup

set -euo pipefail

# Check bash version (require 4.0+)
if [ "${BASH_VERSION%%.*}" -lt 4 ]; then
    echo "ERROR: This script requires bash 4.0 or higher" >&2
    echo "Your version: $BASH_VERSION" >&2
    echo "On macOS, install newer bash with: brew install bash" >&2
    exit 1
fi

# Global configuration
PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
PROJECT_NAME="$(basename "$PROJECT_ROOT")"
PROJECT_HASH=$(echo "$PROJECT_ROOT" | shasum | cut -d' ' -f1 | head -c 8)

# Lock and state files (consistent naming across all scripts)
LOCK_DIR="/tmp/seq-exec-${PROJECT_HASH}"
LOCKFILE="${LOCK_DIR}/executor.lock"
QUEUE_FILE="${LOCK_DIR}/queue.txt"
CURRENT_PID_FILE="${LOCK_DIR}/current.pid"
PROCESS_TREE_FILE="${LOCK_DIR}/process_tree.txt"
ORPHAN_LOG="${LOCK_DIR}/orphans.log"

# Ensure lock directory exists
mkdir -p "$LOCK_DIR"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Logging functions
log_info() {
    echo -e "${GREEN}[SEQUENTIAL]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $*"
}

log_warn() {
    echo -e "${YELLOW}[WARNING]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $*" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $*" >&2
}

log_queue() {
    echo -e "${BLUE}[QUEUE]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $*"
}

# Get all child processes recursively
get_process_tree() {
    local pid=$1
    local children=""

    # Get direct children
    if command -v pgrep >/dev/null 2>&1; then
        children=$(pgrep -P "$pid" 2>/dev/null || true)
    else
        children=$(ps --ppid "$pid" -o pid= 2>/dev/null || true)
    fi

    # Output current PID
    echo "$pid"

    # Recursively get children
    for child in $children; do
        get_process_tree "$child"
    done
}

# Kill entire process tree
kill_process_tree() {
    local pid=$1
    local signal=${2:-TERM}

    log_info "Killing process tree for PID $pid with signal $signal"

    # Get all PIDs in tree
    local all_pids=$(get_process_tree "$pid" | sort -u)

    # Kill in reverse order (children first)
    for p in $(echo "$all_pids" | tac); do
        if kill -0 "$p" 2>/dev/null; then
            log_info "  Killing PID $p"
            kill -"$signal" "$p" 2>/dev/null || true
        fi
    done
}

# Detect and kill orphaned processes
kill_orphans() {
    log_info "Checking for orphaned processes..."

    # Combined pattern for efficiency
    local pattern="pytest|python.*test|uv run|pre-commit|ruff|mypy|git.*commit"

    # Find all matching processes at once
    local pids=$(pgrep -f -E "$pattern" 2>/dev/null || true)
    local found_orphans=0

    for pid in $pids; do
        # Skip if it's us or our parent
        [ "$pid" -eq "$$" ] && continue
        [ "$pid" -eq "$PPID" ] && continue

        # Check if this process belongs to our project (portable)
        local cwd=""
        if [[ -d "/proc/$pid/cwd" ]]; then
            # Linux
            cwd=$(readlink "/proc/$pid/cwd" 2>/dev/null || true)
        else
            # macOS/BSD - only check if we have lsof
            if command -v lsof >/dev/null 2>&1; then
                cwd=$(lsof -p "$pid" 2>/dev/null | grep cwd | awk '{print $NF}' || true)
            fi
        fi

        # Skip if we couldn't determine CWD or it's not our project
        [ -z "$cwd" ] && continue
        if [[ "$cwd" != *"$PROJECT_NAME"* ]] && [[ "$cwd" != "$PROJECT_ROOT"* ]]; then
            continue
        fi

        # Check if it has a living parent
        local ppid=$(ps -o ppid= -p "$pid" 2>/dev/null | xargs || echo 1)

        if [ "$ppid" -eq 1 ] || ! kill -0 "$ppid" 2>/dev/null; then
            # It's an orphan!
            local cmd=$(ps -p "$pid" -o comm= 2>/dev/null || echo unknown)
            log_warn "Found orphan process: PID=$pid CMD=$cmd"
            echo "$(date) PID=$pid CMD=$cmd" >> "$ORPHAN_LOG"

            # Kill the orphan and its children
            kill_process_tree "$pid" TERM
            sleep 1
            if kill -0 "$pid" 2>/dev/null; then
                kill_process_tree "$pid" KILL
            fi

            found_orphans=$((found_orphans + 1))
        fi
    done

    if [ "$found_orphans" -gt 0 ]; then
        log_warn "Killed $found_orphans orphaned process(es)"
    else
        log_info "No orphaned processes found"
    fi
}

# Check if a PID is still alive and belongs to us
is_our_process_alive() {
    local pid=$1

    # Check if process exists
    if ! kill -0 "$pid" 2>/dev/null; then
        return 1
    fi

    # Verify it's still our command (not PID reuse)
    local cmd=$(ps -p "$pid" -o comm= 2>/dev/null || true)
    if [[ "$cmd" != *"bash"* ]] && [[ "$cmd" != *"python"* ]] && [[ "$cmd" != *"uv"* ]]; then
        return 1
    fi

    return 0
}

# Cleanup function
cleanup() {
    local exit_code=$?

    # Remove our PID from current if it's us
    if [ -f "$CURRENT_PID_FILE" ]; then
        local current_pid=$(cat "$CURRENT_PID_FILE" 2>/dev/null || echo 0)
        if [ "$current_pid" -eq "$$" ]; then
            rm -f "$CURRENT_PID_FILE"
        fi
    fi

    # Remove ourselves from queue
    if [ -f "$QUEUE_FILE" ]; then
        grep -v "^$$:" "$QUEUE_FILE" > "${QUEUE_FILE}.tmp" 2>/dev/null || true
        mv -f "${QUEUE_FILE}.tmp" "$QUEUE_FILE" 2>/dev/null || true
    fi

    # Remove lock if we hold it
    if [ -f "$CURRENT_PID_FILE" ]; then
        local current=$(cat "$CURRENT_PID_FILE" 2>/dev/null || echo 0)
        if [ "$current" -eq "$$" ]; then
            rmdir "$LOCKFILE" 2>/dev/null || true
        fi
    fi

    # Final orphan check on exit
    kill_orphans

    exit $exit_code
}

trap cleanup EXIT INT TERM

# Main execution starts here
log_info "Sequential executor starting for: $*"

# Step 1: Kill any orphans before we start
kill_orphans

# Step 2: Add ourselves to the queue
QUEUE_ENTRY="$$:$(date '+%s'):$*"
echo "$QUEUE_ENTRY" >> "$QUEUE_FILE"
log_queue "Added to queue: PID=$$ CMD=$*"

# Step 3: Wait for our turn (INDEFINITELY)
log_info "Waiting for exclusive lock..."
WAIT_COUNT=0

while true; do
    # Try to acquire lock
    if mkdir "$LOCKFILE" 2>/dev/null; then
        # We got the lock!
        echo $$ > "$CURRENT_PID_FILE"
        log_info "Lock acquired, starting execution"
        break
    fi

    # Check if current process is still alive
    if [ -f "$CURRENT_PID_FILE" ]; then
        CURRENT_PID=$(cat "$CURRENT_PID_FILE" 2>/dev/null || echo 0)

        if [ "$CURRENT_PID" -gt 0 ]; then
            if is_our_process_alive "$CURRENT_PID"; then
                # Still running, keep waiting
                if [ $((WAIT_COUNT % 30)) -eq 0 ]; then
                    cmd=$(ps -p "$CURRENT_PID" -o args= 2>/dev/null | head -1 || echo "unknown")
                    log_queue "Still waiting... Current process: PID=$CURRENT_PID CMD=$cmd"
                fi
            else
                # Current process is dead but didn't clean up
                log_warn "Current process (PID=$CURRENT_PID) is dead, cleaning up"
                rm -f "$CURRENT_PID_FILE"
                rmdir "$LOCKFILE" 2>/dev/null || true

                # Kill any orphans it may have left
                kill_orphans
            fi
        else
            # No current PID but lock exists - stale lock
            log_warn "Stale lock detected, cleaning up"
            rmdir "$LOCKFILE" 2>/dev/null || true
        fi
    fi

    # Check queue position
    if [ -f "$QUEUE_FILE" ] && [ $((WAIT_COUNT % 60)) -eq 0 ]; then
        position=$(grep -n "^$$:" "$QUEUE_FILE" 2>/dev/null | cut -d: -f1 || echo "?")
        total=$(wc -l < "$QUEUE_FILE" 2>/dev/null || echo "?")
        log_queue "Queue position: $position of $total"
    fi

    # Periodic orphan cleanup (every 5 minutes)
    if [ $((WAIT_COUNT % 300)) -eq 0 ] && [ $WAIT_COUNT -gt 0 ]; then
        kill_orphans
    fi

    sleep 1
    WAIT_COUNT=$((WAIT_COUNT + 1))
done

# Step 4: Execute using wait_all.sh
log_info "Executing: $*"

# Get script directory with robust path resolution
if command -v realpath >/dev/null 2>&1; then
    SCRIPT_DIR="$(realpath "$(dirname "${BASH_SOURCE[0]}")")"
elif command -v readlink >/dev/null 2>&1 && readlink -f "${BASH_SOURCE[0]}" >/dev/null 2>&1; then
    SCRIPT_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
else
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi
WAIT_ALL="${SCRIPT_DIR}/wait_all.sh"

if [ ! -x "$WAIT_ALL" ]; then
    log_error "wait_all.sh not found at: $WAIT_ALL"
    log_error "This is required to ensure proper process completion!"
    exit 1
fi

# Execute through wait_all.sh with timeout from environment
EXEC_TIMEOUT="${TIMEOUT:-1800}"  # Default 30 minutes
"$WAIT_ALL" --timeout "$EXEC_TIMEOUT" -- "$@"
EXIT_CODE=$?

# Step 5: Cleanup our execution
log_info "Command completed with exit code: $EXIT_CODE"

# Step 6: Release lock and clean up
rm -f "$CURRENT_PID_FILE"
rmdir "$LOCKFILE" 2>/dev/null || true

# Remove ourselves from queue
grep -v "^$$:" "$QUEUE_FILE" > "${QUEUE_FILE}.tmp" 2>/dev/null || true
mv -f "${QUEUE_FILE}.tmp" "$QUEUE_FILE" 2>/dev/null || true

# Final orphan check
kill_orphans

log_info "Execution complete"
exit $EXIT_CODE
```

#### C. Safe Run Wrapper

Create `scripts/safe-run.sh`:

```bash
#!/usr/bin/env bash
# safe-run.sh - Wrapper that delegates to sequential-executor.sh
# Usage: ./scripts/safe-run.sh <command> [args...]

set -euo pipefail

# Get script directory with robust path resolution
if command -v realpath >/dev/null 2>&1; then
    SCRIPT_DIR="$(realpath "$(dirname "${BASH_SOURCE[0]}")")"
elif command -v readlink >/dev/null 2>&1 && readlink -f "${BASH_SOURCE[0]}" >/dev/null 2>&1; then
    SCRIPT_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
else
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi
SEQUENTIAL_EXECUTOR="${SCRIPT_DIR}/sequential-executor.sh"
WAIT_ALL="${SCRIPT_DIR}/wait_all.sh"

# Check if sequential executor exists
if [ ! -x "$SEQUENTIAL_EXECUTOR" ]; then
    echo "ERROR: sequential-executor.sh not found or not executable" >&2
    echo "Path: $SEQUENTIAL_EXECUTOR" >&2
    exit 1
fi

# Check if wait_all.sh exists
if [ ! -x "$WAIT_ALL" ]; then
    echo "ERROR: wait_all.sh not found or not executable" >&2
    echo "Path: $WAIT_ALL" >&2
    exit 1
fi

# Delegate to sequential executor using wait_all.sh
"$WAIT_ALL" -- "$SEQUENTIAL_EXECUTOR" "$@"
```

#### D. Quick Sequential Wrapper

Create `scripts/seq`:

```bash
#!/usr/bin/env bash
# seq - Short alias for sequential execution

# Get script directory with robust path resolution
if command -v realpath >/dev/null 2>&1; then
    SCRIPT_DIR="$(realpath "$(dirname "${BASH_SOURCE[0]}")")"
elif command -v readlink >/dev/null 2>&1 && readlink -f "${BASH_SOURCE[0]}" >/dev/null 2>&1; then
    SCRIPT_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
else
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi
SEQUENTIAL_EXECUTOR="${SCRIPT_DIR}/sequential-executor.sh"
WAIT_ALL="${SCRIPT_DIR}/wait_all.sh"

# Check if both scripts exist
if [ ! -x "$SEQUENTIAL_EXECUTOR" ]; then
    echo "ERROR: sequential-executor.sh not found or not executable" >&2
    exit 1
fi

if [ ! -x "$WAIT_ALL" ]; then
    echo "ERROR: wait_all.sh not found or not executable" >&2
    exit 1
fi

# Use wait_all.sh to ensure proper process completion
"$WAIT_ALL" -- "$SEQUENTIAL_EXECUTOR" "$@"
```

#### E. Ensure Sequential Setup Script

Create `scripts/ensure-sequential.sh`:

```bash
#!/usr/bin/env bash
# ensure-sequential.sh - Ensures ALL operations use sequential executor

set -euo pipefail

PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
SEQUENTIAL_EXECUTOR="$PROJECT_ROOT/scripts/sequential-executor.sh"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}=== Ensuring Sequential Execution Setup ===${NC}"

# 1. Check sequential executor exists and is executable
if [ ! -f "$SEQUENTIAL_EXECUTOR" ]; then
    echo -e "${RED}ERROR: Sequential executor not found at: $SEQUENTIAL_EXECUTOR${NC}"
    exit 1
fi

if [ ! -x "$SEQUENTIAL_EXECUTOR" ]; then
    echo -e "${YELLOW}Making sequential executor executable...${NC}"
    chmod +x "$SEQUENTIAL_EXECUTOR"
fi

# 2. Check safe-run.sh delegates to sequential executor
SAFE_RUN="$PROJECT_ROOT/scripts/safe-run.sh"
if [ -f "$SAFE_RUN" ]; then
    if ! grep -q "sequential-executor.sh" "$SAFE_RUN"; then
        echo -e "${RED}ERROR: safe-run.sh does not use sequential executor${NC}"
        exit 1
    fi
    chmod +x "$SAFE_RUN"
    echo -e "${GREEN}✓ safe-run.sh properly configured${NC}"
fi

# 3. Update ALL git hooks to use sequential execution
HOOKS_DIR="$PROJECT_ROOT/.git/hooks"
if [ -d "$HOOKS_DIR" ]; then
    # Check pre-commit hook uses wait_all.sh
    if [ -f "$HOOKS_DIR/pre-commit" ]; then
        if ! grep -q "wait_all.sh" "$HOOKS_DIR/pre-commit"; then
            echo -e "${YELLOW}Updating pre-commit hook to use wait_all.sh...${NC}"
            cat > "$HOOKS_DIR/pre-commit" << 'EOF'
#!/usr/bin/env bash
# This hook uses wait_all.sh to ensure proper process completion

# Find the wait_all.sh and sequential executor
PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
WAIT_ALL="$PROJECT_ROOT/scripts/wait_all.sh"
SEQUENTIAL_EXECUTOR="$PROJECT_ROOT/scripts/sequential-executor.sh"

if [ ! -x "$WAIT_ALL" ]; then
    echo "ERROR: wait_all.sh not found at: $WAIT_ALL" >&2
    exit 1
fi

if [ ! -x "$SEQUENTIAL_EXECUTOR" ]; then
    echo "ERROR: sequential-executor.sh not found at: $SEQUENTIAL_EXECUTOR" >&2
    exit 1
fi

# Execute pre-commit through sequential executor
"$WAIT_ALL" -- "$SEQUENTIAL_EXECUTOR" pre-commit "$@"
EOF
            chmod +x "$HOOKS_DIR/pre-commit"
        fi
    fi
fi

# 4. Create wrapper for direct commands
DIRECT_WRAPPER="$PROJECT_ROOT/scripts/seq"
if [ -f "$DIRECT_WRAPPER" ]; then
    chmod +x "$DIRECT_WRAPPER"
    echo -e "${GREEN}✓ 'seq' wrapper ready for easy sequential execution${NC}"
fi

# 5. Check Python/pytest configuration
if [ -f "$PROJECT_ROOT/pytest.ini" ]; then
    if grep -q "addopts.*-n" "$PROJECT_ROOT/pytest.ini"; then
        if ! grep -q "addopts.*-n 0" "$PROJECT_ROOT/pytest.ini"; then
            echo -e "${YELLOW}WARNING: pytest.ini may allow parallel execution${NC}"
        fi
    fi
    echo -e "${GREEN}✓ pytest.ini checked${NC}"
fi

# 6. Check environment file
if [ -f "$PROJECT_ROOT/.env.development" ]; then
    if ! grep -q "PYTEST_MAX_WORKERS=1" "$PROJECT_ROOT/.env.development"; then
        echo -e "${YELLOW}WARNING: .env.development missing PYTEST_MAX_WORKERS=1${NC}"
    fi
    echo -e "${GREEN}✓ .env.development checked${NC}"
fi

# 7. Create command intercept aliases
INTERCEPT_FILE="$PROJECT_ROOT/.sequential-aliases"
cat > "$INTERCEPT_FILE" << 'EOF'
# Sequential execution aliases - source this file to enforce sequential execution
# Usage: source .sequential-aliases

# Get the directory of this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SEQ_EXEC="$SCRIPT_DIR/scripts/sequential-executor.sh"

# Intercept common commands that can spawn multiple processes
alias pytest="$SEQ_EXEC uv run pytest"
alias python="$SEQ_EXEC python"
alias uv="$SEQ_EXEC uv"
alias git="$SEQ_EXEC git"
alias make="$SEQ_EXEC make"
alias npm="$SEQ_EXEC npm"
alias pnpm="$SEQ_EXEC pnpm"
alias yarn="$SEQ_EXEC yarn"

# Show active intercepts
echo "Sequential execution enforced for: pytest, python, uv, git, make, npm, pnpm, yarn"
echo "To run without sequential execution, use: command <cmd> or \<cmd>"
EOF

echo -e "${GREEN}✓ Created command intercept aliases${NC}"
echo -e "${YELLOW}To enforce sequential execution for ALL commands:${NC}"
echo -e "  source .sequential-aliases"

# 8. Verify no background processes are running
echo -e "\n${GREEN}Checking for background processes...${NC}"
PYTHON_PROCS=$(pgrep -c python 2>/dev/null || echo 0)
GIT_PROCS=$(pgrep -c git 2>/dev/null || echo 0)
if [ "$PYTHON_PROCS" -gt 1 ] || [ "$GIT_PROCS" -gt 1 ]; then
    echo -e "${YELLOW}WARNING: Multiple processes detected:${NC}"
    echo "  Python processes: $PYTHON_PROCS"
    echo "  Git processes: $GIT_PROCS"
    echo -e "${YELLOW}Consider running: make kill-all${NC}"
fi

# 9. Summary
echo -e "\n${GREEN}=== Sequential Execution Setup Summary ===${NC}"
echo "1. Sequential executor: $SEQUENTIAL_EXECUTOR"
echo "2. Safe wrapper: $SAFE_RUN"
echo "3. Direct wrapper: seq (use as: ./scripts/seq <command>)"
echo "4. Git hooks: Updated to use sequential execution"
echo "5. Command aliases: source .sequential-aliases"
echo ""
echo -e "${GREEN}CRITICAL RULES:${NC}"
echo "- NEVER use & for background execution"
echo "- NEVER run pytest with -n auto or -n >1"
echo "- ALWAYS use 'make' commands or './scripts/seq' wrapper"
echo "- ALWAYS wait for commands to complete"
echo ""
echo -e "${YELLOW}Monitor queue in another terminal:${NC} make monitor"
```

#### F. Monitor Queue Script

Create `scripts/monitor-queue.sh`:

```bash
#!/usr/bin/env bash
# monitor-queue.sh - Monitor the sequential execution queue and system state

set -euo pipefail

# Get project info
PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
PROJECT_HASH=$(echo "$PROJECT_ROOT" | shasum | cut -d' ' -f1 | head -c 8)

# State files (consistent naming across all scripts)
LOCK_DIR="/tmp/seq-exec-${PROJECT_HASH}"
LOCKFILE="${LOCK_DIR}/executor.lock"
QUEUE_FILE="${LOCK_DIR}/queue.txt"
CURRENT_PID_FILE="${LOCK_DIR}/current.pid"
ORPHAN_LOG="${LOCK_DIR}/orphans.log"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Clear screen and show header
show_header() {
    clear
    echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}       Sequential Execution Monitor - $(date '+%Y-%m-%d %H:%M:%S')${NC}"
    echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"
    echo
}

# Show current execution status
show_current() {
    echo -e "${GREEN}▶ Current Execution:${NC}"

    if [ -f "$LOCKFILE" ] && [ -f "$CURRENT_PID_FILE" ]; then
        local pid=$(cat "$CURRENT_PID_FILE" 2>/dev/null || echo "unknown")

        if kill -0 "$pid" 2>/dev/null; then
            local cmd=$(ps -p "$pid" -o args= 2>/dev/null | head -1 || echo "unknown")
            local elapsed=$(ps -p "$pid" -o etime= 2>/dev/null || echo "00:00")
            # RSS is already in KB on most systems
            local mem=$(ps -p "$pid" -o rss= 2>/dev/null | awk '{printf "%.1f MB", $1/1024}' || echo "0 MB")

            echo -e "  ${YELLOW}PID:${NC} $pid"
            echo -e "  ${YELLOW}Command:${NC} $cmd"
            echo -e "  ${YELLOW}Elapsed:${NC} $elapsed"
            echo -e "  ${YELLOW}Memory:${NC} ${mem}"

            # Show child processes
            local children=$(pgrep -P "$pid" 2>/dev/null | wc -l || echo 0)
            if [ "$children" -gt 0 ]; then
                echo -e "  ${YELLOW}Children:${NC} $children processes"
            fi
        else
            echo -e "  ${RED}Process $pid is dead but lock exists!${NC}"
        fi
    else
        echo -e "  ${GREEN}No process currently executing${NC}"
    fi
    echo
}

# Show queue
show_queue() {
    echo -e "${BLUE}📋 Execution Queue:${NC}"

    if [ -f "$QUEUE_FILE" ] && [ -s "$QUEUE_FILE" ]; then
        local count=1
        while IFS=: read -r pid timestamp cmd; do
            if [ -n "$pid" ]; then
                local wait_time=$(($(date +%s) - timestamp))
                local wait_formatted=$(printf "%02d:%02d" $((wait_time/60)) $((wait_time%60)))

                if kill -0 "$pid" 2>/dev/null; then
                    echo -e "  ${count}. ${YELLOW}PID $pid${NC} - Waiting ${wait_formatted} - $cmd"
                else
                    echo -e "  ${count}. ${RED}PID $pid (dead)${NC} - $cmd"
                fi
                count=$((count + 1))
            fi
        done < "$QUEUE_FILE"
    else
        echo -e "  ${GREEN}Queue is empty${NC}"
    fi
    echo
}

# Show orphan processes
show_orphans() {
    echo -e "${RED}☠️  Potential Orphans:${NC}"

    local patterns=(
        "pytest"
        "python.*test"
        "uv run"
        "pre-commit"
        "ruff"
        "mypy"
    )

    local found=0
    for pattern in "${patterns[@]}"; do
        local pids=$(pgrep -f "$pattern" 2>/dev/null || true)

        for pid in $pids; do
            # Skip monitor process
            [ "$pid" -eq "$$" ] && continue

            # Check if it's an orphan (parent is init)
            local ppid=$(ps -o ppid= -p "$pid" 2>/dev/null | xargs || echo 1)
            if [ "$ppid" -eq 1 ]; then
                local cmd=$(ps -p "$pid" -o comm= 2>/dev/null || echo unknown)
                echo -e "  ${RED}⚠${NC}  PID $pid - $cmd (orphaned)"
                found=$((found + 1))
            fi
        done
    done

    if [ "$found" -eq 0 ]; then
        echo -e "  ${GREEN}No orphan processes detected${NC}"
    fi
    echo
}

# Show system resources
show_resources() {
    echo -e "${CYAN}💻 System Resources:${NC}"

    # Memory
    if command -v free >/dev/null 2>&1; then
        local mem_info=$(free -h | grep Mem)
        local total=$(echo "$mem_info" | awk '{print $2}')
        local used=$(echo "$mem_info" | awk '{print $3}')
        local free=$(echo "$mem_info" | awk '{print $4}')
        echo -e "  ${YELLOW}Memory:${NC} $used used / $free free / $total total"
    fi

    # Load average
    local load=$(uptime | awk -F'load average:' '{print $2}' | xargs)
    echo -e "  ${YELLOW}Load:${NC} $load"

    # Process counts
    local total_procs=$(ps aux | wc -l)
    local python_procs=$(pgrep -c python 2>/dev/null || echo 0)
    local git_procs=$(pgrep -c git 2>/dev/null || echo 0)
    echo -e "  ${YELLOW}Processes:${NC} $total_procs total, $python_procs python, $git_procs git"
    echo
}

# Show recent orphan kills
show_orphan_log() {
    if [ -f "$ORPHAN_LOG" ]; then
        echo -e "${YELLOW}📜 Recent Orphan Kills:${NC}"
        tail -5 "$ORPHAN_LOG" 2>/dev/null | while read -r line; do
            echo "  $line"
        done
        echo
    fi
}

# Main monitoring loop
echo -e "${GREEN}Starting queue monitor. Press Ctrl+C to exit.${NC}"
echo -e "${YELLOW}Refreshing every 2 seconds...${NC}"
sleep 2

while true; do
    show_header
    show_current
    show_queue
    show_orphans
    show_resources
    show_orphan_log

    # Footer
    echo -e "${CYAN}────────────────────────────────────────────────────────────────${NC}"
    echo -e "Press ${RED}Ctrl+C${NC} to exit | ${YELLOW}Q${NC} to kill queue | ${RED}K${NC} to kill all"

    # Check for input with timeout
    if read -t 2 -n 1 key; then
        case "$key" in
            q|Q)
                echo -e "\n${YELLOW}Clearing queue...${NC}"
                rm -f "$QUEUE_FILE"
                ;;
            k|K)
                echo -e "\n${RED}Killing all processes...${NC}"
                pkill -f "sequential-executor.sh" || true
                pkill -f pytest || true
                rm -f "$LOCKFILE" "$CURRENT_PID_FILE" "$QUEUE_FILE"
                ;;
        esac
    fi
done
```

### 2. Make Scripts Executable

```bash
chmod +x scripts/wait_all.sh
chmod +x scripts/sequential-executor.sh
chmod +x scripts/safe-run.sh
chmod +x scripts/seq
chmod +x scripts/ensure-sequential.sh
chmod +x scripts/monitor-queue.sh
```

### 3. Environment Configuration

Create `.env.development`:

```bash
# Development Environment Resource Limits
# Source this file before running tests or heavy operations:
# source .env.development

# Pytest configuration
export PYTEST_MAX_WORKERS=1
export PYTEST_DISABLE_XDIST=1
export PYTEST_CURRENT_TEST_TIMEOUT=300

# Prefect configuration
export PREFECT_TASK_RUNNER_MAX_WORKERS=1
export PREFECT_LOCAL_STORAGE_PATH=./.prefect
export PREFECT_API_ENABLE_HTTP2=false

# Python configuration
export PYTHONDONTWRITEBYTECODE=1
export PYTHON_GC_THRESHOLD=100  # Aggressive garbage collection
export PYTHONUNBUFFERED=1

# UV configuration
export UV_NO_CACHE=1
export UV_SYSTEM_PYTHON=0

# System resource limits (enforced by safe-run.sh)
export MAX_MEMORY_MB=8192       # 8GB max per operation
export MAX_PROCESSES=50         # 50 processes max
export CHECK_INTERVAL=2         # Check every 2 seconds
export TIMEOUT=1800            # 30 minute timeout

# Development flags (project-agnostic)
export PROJECT_SEQUENTIAL_MODE=1
export PROJECT_RESOURCE_MONITORING=1
export PROJECT_FAIL_FAST=1

# Pre-commit configuration
export PRE_COMMIT_MAX_WORKERS=1
export PRE_COMMIT_NO_CONCURRENCY=1
export PRE_COMMIT_COLOR=always

# TruffleHog specific settings
export TRUFFLEHOG_TIMEOUT=300
export TRUFFLEHOG_MEMORY_MB=1024
export TRUFFLEHOG_CONCURRENCY=1
export TRUFFLEHOG_MAX_DEPTH=50

# Set system limits (if supported by shell)
if [ -n "$BASH_VERSION" ] || [ -n "$ZSH_VERSION" ]; then
    echo "Setting resource limits..."

    # Process limits
    if ulimit -u 100 2>/dev/null; then
        echo "  Max processes: 100"
    else
        echo "  Max processes: (not supported on this system)"
    fi

    # Memory limits (often not supported on macOS)
    if ulimit -v 8388608 2>/dev/null; then
        echo "  Max virtual memory: 8GB"
    else
        echo "  Max virtual memory: (not supported on this system)"
    fi

    if ulimit -m 8388608 2>/dev/null; then
        echo "  Max RSS memory: 8GB"
    else
        echo "  Max RSS memory: (not supported on this system)"
    fi

    # File limits
    if ulimit -n 1024 2>/dev/null; then
        echo "  Max open files: 1024"
    else
        echo "  Max open files: (not supported on this system)"
    fi

    echo "  Sequential mode: ENABLED"
fi
```

### 4. Test Safety Configuration

#### A. Pytest Configuration

Create `pytest.ini`:

```ini
[pytest]
# Force sequential execution to prevent process explosions
addopts =
    # Parallelism control
    -n 0                      # Disable xdist parallelism
    --maxprocesses=1          # Single process execution
    --dist=no                 # No distributed testing

    # Output control
    --tb=short                # Shorter tracebacks
    --strict-markers          # Strict marker usage
    --no-header               # No header in output

    # Timeouts and safety
    --timeout=300             # 5-minute timeout per test
    --timeout-method=thread   # Thread-based timeout

    # Performance
    --durations=10            # Show 10 slowest tests
    -ra                       # Show all test outcomes

# Test discovery
testpaths = tests
python_files = test_*.py
python_classes = Test*
python_functions = test_*

# Markers
markers =
    slow: marks tests as slow (deselect with '-m "not slow"')
    integration: marks tests as integration tests
    unit: marks tests as unit tests

# Coverage options (when using pytest-cov)
[coverage:run]
source = src
omit =
    */tests/*
    */__pycache__/*
    */venv/*
    */.venv/*

[coverage:report]
exclude_lines =
    pragma: no cover
    def __repr__
    raise AssertionError
    raise NotImplementedError
    if __name__ == .__main__.:
    if TYPE_CHECKING:
```

#### B. Test Conftest for Sequential Execution

Create `tests/conftest.py`:

```python
#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Pytest configuration for sequential execution.
Prevents multiple processes from spawning during tests.
"""

import os
import pytest


def pytest_configure(config):
    """Configure pytest to run sequentially and with resource limits."""
    # Force sequential execution
    os.environ["PYTEST_MAX_WORKERS"] = "1"
    os.environ["PYTEST_DISABLE_XDIST"] = "1"

    # Set resource limits
    os.environ["PYTHONDONTWRITEBYTECODE"] = "1"
    os.environ["PYTHONUNBUFFERED"] = "1"

    # Disable any parallel execution plugins
    if hasattr(config.option, "numprocesses"):
        config.option.numprocesses = 1
    if hasattr(config.option, "dist"):
        config.option.dist = "no"


def pytest_cmdline_preparse(config, args):
    """Preprocess command line arguments to enforce sequential execution."""
    # Remove any parallel execution flags
    filtered_args = []
    skip_next = False

    for arg in args:
        if skip_next:
            skip_next = False
            continue

        if arg in ["-n", "--numprocesses", "--dist"]:
            skip_next = True
            continue
        elif arg.startswith("-n=") or arg.startswith("--numprocesses="):
            continue
        elif arg == "--dist=loadscope" or arg == "--dist=each":
            continue
        else:
            filtered_args.append(arg)

    args[:] = filtered_args


@pytest.fixture(autouse=True)
def enforce_sequential_execution():
    """Fixture that runs for every test to enforce sequential execution."""
    # Set environment variables for each test
    os.environ["PYTEST_CURRENT_TEST"] = "1"
    os.environ["PROJECT_SEQUENTIAL_MODE"] = "1"

    yield

    # Cleanup after test
    os.environ.pop("PYTEST_CURRENT_TEST", None)
```

#### C. Test Utilities for Sequential Subprocess

Create `tests/test_utils.py`:

```python
#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Test utilities for sequential subprocess execution.
Prevents multiple processes from spawning during tests.
"""

import subprocess
import os
from pathlib import Path
from typing import Optional, List, Tuple


def get_sequential_executor() -> Optional[Path]:
    """Get the path to the sequential executor if available."""
    # Try to find the sequential executor
    project_root = Path(__file__).parent.parent
    sequential_executor = project_root / "scripts" / "sequential-executor.sh"
    wait_all = project_root / "scripts" / "wait_all.sh"

    if sequential_executor.exists() and wait_all.exists():
        return sequential_executor
    return None


def run_command_sequential(
    cmd: List[str],
    cwd: Optional[Path] = None,
    timeout: int = 300,
    use_sequential: bool = True
) -> Tuple[int, str, str]:
    """
    Run a command with optional sequential execution.

    Args:
        cmd: Command and arguments as a list
        cwd: Working directory
        timeout: Timeout in seconds
        use_sequential: Whether to use the sequential executor

    Returns:
        Tuple of (exit_code, stdout, stderr)
    """
    # Check if we should use sequential execution
    sequential_executor = get_sequential_executor()
    wait_all = Path(__file__).parent.parent / "scripts" / "wait_all.sh"

    if use_sequential and sequential_executor and wait_all.exists():
        # Use wait_all.sh with sequential executor
        full_cmd = [str(wait_all), "--timeout", str(timeout), "--", str(sequential_executor)] + cmd
    else:
        # Direct execution (fallback)
        full_cmd = cmd

    try:
        result = subprocess.run(
            full_cmd,
            cwd=cwd,
            capture_output=True,
            text=True,
            timeout=timeout,
            check=False
        )
        return result.returncode, result.stdout, result.stderr
    except subprocess.TimeoutExpired:
        return -1, "", f"Command timed out after {timeout} seconds"


# For backward compatibility, create an alias
run_command = run_command_sequential
```

### 5. Makefile for Safe Commands

Create `Makefile`:

```makefile
# Makefile for Safe Sequential Execution
# Enforces safe execution patterns to prevent resource exhaustion

.PHONY: help test lint format check clean install dev-setup monitor kill-all safe-commit

# Default shell
SHELL := /bin/bash

# Colors
GREEN := \033[0;32m
YELLOW := \033[1;33m
RED := \033[0;31m
NC := \033[0m # No Color

# Safe run wrapper
SAFE_RUN := ./scripts/safe-run.sh

help: ## Show this help message
	@echo -e "$(GREEN)Safe Sequential Execution Commands$(NC)"
	@echo -e "$(YELLOW)Always use these commands instead of running tools directly!$(NC)"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "$(GREEN)%-20s$(NC) %s\n", $$1, $$2}'

check-env: ## Check system resources
	@echo -e "$(GREEN)Checking system resources...$(NC)"
	@if [ -f .env.development ]; then \
		source .env.development; \
	fi
	@echo "Memory free: $$(free -h 2>/dev/null | grep Mem | awk '{print $$4}' || echo 'N/A')"
	@echo "Load average: $$(uptime | awk -F'load average:' '{print $$2}')"
	@echo "Python processes: $$(pgrep -c python 2>/dev/null || echo 0)"
	@echo "Git processes: $$(pgrep -c git 2>/dev/null || echo 0)"

dev-setup: ## Set up development environment
	@echo -e "$(GREEN)Setting up development environment...$(NC)"
	@if [ ! -f .env.development ]; then \
		echo -e "$(RED)Creating .env.development file...$(NC)"; \
	fi
	@source .env.development 2>/dev/null || true
	@uv venv
	@source .venv/bin/activate && uv sync --all-extras
	@chmod +x scripts/*.sh
	@./scripts/ensure-sequential.sh
	@echo -e "$(GREEN)Development environment ready!$(NC)"
	@echo -e "$(YELLOW)Remember to: source .env.development$(NC)"

install: ## Install dependencies safely
	@echo -e "$(GREEN)Installing dependencies...$(NC)"
	@$(SAFE_RUN) uv sync --all-extras

test: check-env ## Run tests safely (sequential)
	@echo -e "$(GREEN)Running tests sequentially...$(NC)"
	@source .env.development 2>/dev/null || true
	@$(SAFE_RUN) uv run pytest -v

test-fast: check-env ## Run fast tests only
	@echo -e "$(GREEN)Running fast tests...$(NC)"
	@source .env.development 2>/dev/null || true
	@$(SAFE_RUN) uv run pytest -v -m "not slow"

test-file: check-env ## Run specific test file (usage: make test-file FILE=tests/test_foo.py)
	@if [ -z "$(FILE)" ]; then \
		echo -e "$(RED)ERROR: Specify FILE=tests/test_something.py$(NC)"; \
		exit 1; \
	fi
	@echo -e "$(GREEN)Running test: $(FILE)$(NC)"
	@source .env.development 2>/dev/null || true
	@$(SAFE_RUN) uv run pytest -v $(FILE)

lint: check-env ## Run linters safely
	@echo -e "$(GREEN)Running linters...$(NC)"
	@source .env.development 2>/dev/null || true
	@$(SAFE_RUN) uv run ruff check src tests
	@$(SAFE_RUN) uv run mypy src --strict

format: check-env ## Format code safely
	@echo -e "$(GREEN)Formatting code...$(NC)"
	@source .env.development 2>/dev/null || true
	@$(SAFE_RUN) uv run ruff format src tests
	@$(SAFE_RUN) uv run ruff check --fix src tests

check: lint test ## Run all checks

clean: ## Clean temporary files
	@echo -e "$(GREEN)Cleaning temporary files...$(NC)"
	@find . -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
	@find . -type f -name "*.pyc" -delete 2>/dev/null || true
	@find . -type f -name "*.pyo" -delete 2>/dev/null || true
	@find . -type f -name ".coverage" -delete 2>/dev/null || true
	@rm -rf .pytest_cache 2>/dev/null || true
	@rm -rf .mypy_cache 2>/dev/null || true
	@rm -rf .ruff_cache 2>/dev/null || true
	@rm -rf htmlcov 2>/dev/null || true
	@rm -f /tmp/seq-exec-*/executor.lock 2>/dev/null || true
	@echo -e "$(GREEN)Cleanup complete!$(NC)"

kill-all: ## Emergency: Kill all Python/test processes
	@echo -e "$(RED)EMERGENCY: Killing all Python processes...$(NC)"
	@pkill -f pytest || true
	@pkill -f python || true
	@pkill -f pre-commit || true
	@killall -9 python python3 2>/dev/null || true
	@rm -rf /tmp/seq-exec-*/executor.lock 2>/dev/null || true
	@rm -rf /tmp/seq-exec-*/current.pid 2>/dev/null || true
	@rm -rf /tmp/seq-exec-*/queue.txt 2>/dev/null || true
	@echo -e "$(GREEN)All processes killed$(NC)"

monitor: ## Start sequential execution queue monitor
	@echo -e "$(GREEN)Starting queue monitor...$(NC)"
	@./scripts/monitor-queue.sh

safe-commit: check-env ## Safely commit changes
	@echo -e "$(GREEN)Checking for running git operations...$(NC)"
	@if pgrep -f "git commit" > /dev/null; then \
		echo -e "$(RED)ERROR: Git commit already in progress!$(NC)"; \
		exit 1; \
	fi
	@echo -e "$(GREEN)Safe to proceed with commit$(NC)"
	@echo -e "$(YELLOW)Run: git add -A && $(SAFE_RUN) git commit$(NC)"

# Hidden targets for CI
.ci-test:
	@$(SAFE_RUN) uv run pytest --cov=src --cov-report=xml

.ci-lint:
	@$(SAFE_RUN) uv run ruff check src tests --format=github
	@$(SAFE_RUN) uv run mypy src --no-error-summary
```

### 6. Pre-commit Configuration

Create `.pre-commit-config.yaml`:

```yaml
# Sequential pre-commit configuration
# All hooks run one at a time to prevent process explosions

default_language_version:
  python: python3.11

default_stages: [pre-commit]

# CRITICAL: Every hook MUST have require_serial: true
# This prevents ANY parallel execution

repos:
  # Basic file checks
  - repo: https://github.com/pre-commit/pre-commit-hooks
    rev: v5.0.0
    hooks:
      - id: trailing-whitespace
        stages: [pre-commit]
        require_serial: true
      - id: end-of-file-fixer
        stages: [pre-commit]
        require_serial: true
      - id: check-yaml
        stages: [pre-commit]
        require_serial: true
      - id: check-added-large-files
        stages: [pre-commit]
        args: ['--maxkb=1000']
        require_serial: true
      - id: check-toml
        stages: [pre-commit]
        require_serial: true
      - id: check-json
        stages: [pre-commit]
        require_serial: true
      - id: check-merge-conflict
        stages: [pre-commit]
        require_serial: true

  # Python tools with sequential execution
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

  # Use safe-run.sh for resource-intensive hooks
  - repo: local
    hooks:
      - id: mypy-safe
        name: Type checking (safe)
        entry: ./scripts/safe-run.sh uv run mypy
        language: system
        types: [python]
        require_serial: true
        pass_filenames: true
        stages: [pre-commit]
        args: [--ignore-missing-imports, --strict]

      - id: trufflehog-safe
        name: Secret detection (safe)
        entry: ./scripts/safe-run.sh trufflehog git file://. --only-verified --fail --no-update
        language: system
        pass_filenames: false
        require_serial: true
        stages: [pre-commit]

# CI configuration
ci:
  skip:
    - mypy-safe
    - trufflehog-safe
```

### 7. Subprocess Runner Safety

For any code that uses subprocess, create a safe wrapper:

```python
#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Subprocess runner with sequential execution.
Prevents multiple processes from running simultaneously.
"""

import subprocess
import os
from pathlib import Path
from typing import List, Optional, Tuple


def get_sequential_executor() -> Tuple[Optional[Path], Optional[Path]]:
    """Get paths to sequential executor and wait_all.sh if available."""
    # Try multiple potential locations
    possible_roots = [
        Path(__file__).parent.parent,  # From src/
        Path(os.getcwd()),  # Current working directory
        Path(os.environ.get("PROJECT_ROOT", ".")),  # Environment variable
    ]

    for root in possible_roots:
        sequential_executor = root / "scripts" / "sequential-executor.sh"
        wait_all = root / "scripts" / "wait_all.sh"

        if sequential_executor.exists() and wait_all.exists():
            return sequential_executor, wait_all

    return None, None


def run_subprocess_command(command: List[str], description: str) -> bool:
    """Run a subprocess command safely through sequential executor."""
    try:
        # Check if we should use sequential execution
        sequential_executor, wait_all = get_sequential_executor()

        if sequential_executor and wait_all:
            # Use wait_all.sh with sequential executor for proper process completion
            full_command = [str(wait_all), "--", str(sequential_executor)] + command
        else:
            # Fallback to direct execution (when scripts not available)
            full_command = command

        result = subprocess.run(full_command, capture_output=True, text=True, check=True)
        if result.stdout:
            print(result.stdout)
        if result.stderr:
            print(result.stderr)
        return True
    except subprocess.CalledProcessError as e:
        print(f"Failed during {description}: {e}")
        if e.stdout:
            print(e.stdout)
        if e.stderr:
            print(e.stderr)
        return False
```

### 8. GitHub Actions Configuration

Create `.github/workflows/sequential-ci.yml`:

```yaml
name: Sequential CI Pipeline

on:
  pull_request:
  push:
    branches: [main, develop]

# Prevent ANY parallel execution
concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: false  # NEVER cancel - wait instead

env:
  # Force sequential execution everywhere
  PYTEST_MAX_WORKERS: 1
  PRE_COMMIT_MAX_WORKERS: 1
  PYTHONDONTWRITEBYTECODE: 1
  UV_NO_CACHE: 1

  # Resource limits
  MEMORY_LIMIT_MB: 4096
  MAX_PROCESSES: 50

  # Timeouts
  TIMEOUT_SECONDS: 600
  TRUFFLEHOG_TIMEOUT: 300

jobs:
  sequential-pipeline:
    runs-on: ubuntu-latest
    timeout-minutes: 60  # Global timeout

    steps:
    - uses: actions/checkout@v4
      with:
        fetch-depth: 0

    - name: Set up Python
      uses: actions/setup-python@v5
      with:
        python-version: '3.11'

    - name: Install uv
      uses: astral-sh/setup-uv@v6
      with:
        enable-cache: true

    - name: Create virtual environment
      run: uv venv

    - name: Install dependencies
      run: |
        source .venv/bin/activate
        uv sync --all-extras
        uv pip install pre-commit

    - name: Set resource limits
      run: |
        # Set reasonable process limit
        ulimit -u 500 2>/dev/null || echo "Process limit not supported"

        # Set file limit
        ulimit -n 2048 2>/dev/null || echo "File limit not supported"

        # Show current limits
        echo "=== Current Resource Limits ==="
        ulimit -a

    - name: Run pre-commit checks
      run: |
        source .venv/bin/activate
        pre-commit run --all-files --show-diff-on-failure

    - name: Run tests sequentially
      run: |
        source .venv/bin/activate
        uv run pytest tests -v --tb=short

    - name: Build project
      run: |
        source .venv/bin/activate
        uv build

    - name: Memory usage report
      if: always()
      run: |
        echo "=== System Resources ==="
        free -h
        ps aux --sort=-%mem | head -10
```

## Quick Start

1. **Create scripts directory**:
   ```bash
   mkdir -p scripts tests
   ```

2. **Copy all scripts from this guide**

3. **Make executable**:
   ```bash
   chmod +x scripts/*.sh
   ```

4. **Run setup**:
   ```bash
   ./scripts/ensure-sequential.sh
   source .env.development
   uv venv && source .venv/bin/activate
   uv sync --all-extras
   uv pip install pre-commit
   pre-commit install
   ```

## Usage

### Command Execution

```bash
# ✅ CORRECT - Using wrappers
make test
./scripts/seq uv run pytest
./scripts/safe-run.sh python script.py

# ❌ WRONG - Direct execution
pytest
python script.py &
uv run mypy src
```

### Monitoring

```bash
# Always run in separate terminal
make monitor
```

## Key Integration Points

1. **Never use `exec`** - Always use wait_all.sh
2. **All subprocess calls** must use sequential executor
3. **Test utilities** must use run_command_sequential
4. **Git hooks** must use wait_all.sh
5. **CI/CD** must set PYTEST_MAX_WORKERS=1

## Troubleshooting

### Emergency Kill

```bash
make kill-all
rm -rf /tmp/seq-exec-*
```

### Verification

```bash
./scripts/ensure-sequential.sh
make check-env
```

## Verification Checklist

```bash
# All scripts present and executable
[ -x scripts/wait_all.sh ] && echo "✓ wait_all.sh" || echo "✗ Missing"
[ -x scripts/sequential-executor.sh ] && echo "✓ Sequential executor" || echo "✗ Missing"
[ -x scripts/safe-run.sh ] && echo "✓ Safe wrapper" || echo "✗ Missing"
[ -x scripts/seq ] && echo "✓ Quick wrapper" || echo "✗ Missing"

# Git hooks use wait_all.sh
grep -q "wait_all.sh" .git/hooks/pre-commit && echo "✓ Git hooks" || echo "✗ Not integrated"

# Environment configured
grep -q "PYTEST_MAX_WORKERS=1" .env.development && echo "✓ Environment" || echo "✗ Missing"

# No exec commands in scripts (except wait_all.sh)
grep -r "exec " scripts/*.sh | grep -v wait_all.sh | grep -v "# " && echo "✗ Found exec commands" || echo "✓ No exec commands"
```

## Summary

This setup prevents process explosions through:
1. **Sequential executor** - One process at a time
2. **wait_all.sh** - Complete process tree termination
3. **No exec bypasses** - All scripts use wait_all.sh
4. **Test safety** - Sequential subprocess execution
5. **Complete integration** - All tools use the system

## Key Safety Features

1. **Consistent lock directory naming** - Uses `/tmp/seq-exec-${PROJECT_HASH}` across all scripts
2. **Cross-platform compatibility** - Works on Linux, macOS, and BSD systems
3. **Robust path resolution** - Handles symlinks and various path configurations
4. **Timeout propagation** - Commands respect environment timeout settings
5. **Bash version checking** - Ensures compatibility with required features
6. **Error handling** - Graceful degradation when features aren't supported
7. **Resource limit safety** - Checks if ulimit commands are supported before using them
8. **Efficient orphan detection** - Uses combined patterns for better performance
9. **Project-agnostic** - No hardcoded project names or paths
