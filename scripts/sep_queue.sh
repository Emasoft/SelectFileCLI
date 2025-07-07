#!/usr/bin/env bash
# sep_queue.sh - Sequential Execution Pipeline Queue Manager
# Version: 8.5.0
#
# This version implements the correct flow:
# 1. Commands are added to queue (atomified if possible)
# 2. Queue is NOT executed automatically
# 3. Queue execution happens only with --queue-start
# 4. All commands execute in exact order of addition
#
# HERE IS THE CHANGELOG FOR THIS VERSION OF THE FILE:
# v8.5.0:
# - Added runner enforcement by default (use --dont_enforce_runners to disable)
# - Added --only_verified flag to skip unrecognized commands
# - Added --enable-second-tier flag to enable less-trusted tools
# - SEP is now uv-centric and enforces proper runners
# - Only supported runners: uv, pipx, pnpm, go, npx
# v8.4.0:
# - Fixed USER variable conflict by renaming to RUN_USER throughout
# - Added cross-platform date parsing function parse_date_to_epoch()
# - Added missing docstrings for utility functions
# - Fixed timeout_info validation in check_pipeline_timeout()
# - Simplified bash version check using BASH_VERSINFO array
# - Replaced ls usage in loops with glob expansion for efficiency
# - Added warning for unused 'attempt' parameter (retry not implemented)
# - Moved PUBLISHING.md and RELEASE_PROCESS.md to DOCS_DEV/
# - Removed old script versions (v4-v7, backup) to reduce clutter
# - Removed duplicate docs/ATOMIFICATION_FEATURE.md
# v8.3.0:
# - Implemented all 4 "missing" filters: user, commit, event, created
# - Enhanced metadata storage to capture git user, commit SHA, and created date
# - Added backward compatibility for existing metadata files
# - Fixed "failed" status filter to properly check exit codes
# - Enhanced JSON output to include actor and event fields
# - Updated view_run to display user, branch, and commit information
# v8.2.0:
# - Added missing parameters to function calls for list_runs (all 13 parameters)
# - Added missing parameters to function calls for view_runs (exit_status, attempt)
# - Implemented --exit-status flag for view command
# - Implemented JSON field filtering with --json FIELDS option
# - Implemented JQ expression filtering with --jq option
# - Fixed security vulnerability by replacing eval with safer command parsing
#
set -euo pipefail

VERSION='8.5.0'

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source common functions and definitions
source "${SCRIPT_DIR}/sep_common.sh"

# Initialize common variables
init_sep_common

# Constants
readonly DEFAULT_LIST_LIMIT=20
readonly DEFAULT_WATCH_INTERVAL=3
readonly INTERACTIVE_RUN_LIMIT=20
readonly DEFAULT_TIMEOUT=86400
readonly DEFAULT_MEMORY_LIMIT_MB=2048
readonly DEFAULT_PIPELINE_TIMEOUT=86400

# Display help message
show_help() {
    cat << 'EOF'
sep_queue.sh v8.4.0 - Sequential Execution Pipeline Queue Manager

USAGE:
    sep_queue.sh [OPTIONS] -- COMMAND [ARGS...]
    sep_queue.sh --queue-start
    sep_queue.sh --queue-status
    sep_queue.sh --queue-pause
    sep_queue.sh --queue-resume
    sep_queue.sh --queue-stop
    sep_queue.sh run list [OPTIONS]
    sep_queue.sh run view [RUN_ID] [OPTIONS]
    sep_queue.sh run watch [RUN_ID] [OPTIONS]
    sep_queue.sh --help

DESCRIPTION:
    Manages a sequential execution queue for commands.
    Commands are added to queue but NOT executed automatically.
    Use --queue-start to begin processing the queue.
    Auto-detects git and make commands for special handling.
    Automatically atomifies commands to process files individually.

OPTIONS:
    --help, -h             Show this help message
    --version              Show version information
    --timeout SECONDS      Command timeout in seconds (default: 86400)
    --pipeline-timeout SEC Pipeline timeout in seconds (default: 86400)
    --memory-limit MB      Memory limit per process in MB (default: 2048)
    --log-dir PATH         Custom log directory (default: ./logs)
    --verbose              Enable verbose output
    --no-atomify           Disable automatic command atomification
    --queue-start          Start processing the queue
    --queue-status         Show current queue status
    --queue-pause          Pause queue execution
    --queue-resume         Resume queue execution
    --queue-stop           Stop queue and clear all pending commands
    --clear-queue          Clear all entries from queue (queue keeps running)
    --close-queue          Close queue (stop accepting new commands)
    --reopen-queue         Reopen closed queue (accept new commands again)
    --dont_enforce_runners Do not enforce proper runners for tools
    --only_verified        Skip unrecognized commands (log them)
    --enable-second-tier   Enable second-tier tools (less trusted)

GITHUB CLI COMPATIBLE COMMANDS:
    run list               List recent runs (identical to gh run list)
        -L, --limit N      Maximum number of runs to fetch (default: 20)
        -s, --status STR   Filter by status (queued, in_progress, completed, failed)
        -b, --branch STR   Filter by branch
        -w, --workflow STR Filter by workflow name
        --json [FIELDS]    Output JSON with specified fields
        -t, --template STR Format JSON output using Go template
        -q, --jq EXPR      Filter JSON output using jq expression
        -a, --all          Include disabled workflows
        -u, --user STR     Filter by user who triggered the run
        -c, --commit SHA   Filter by commit SHA
        -e, --event EVENT  Filter by event type
        --created DATE     Filter by creation date

    run view [RUN_ID]      View run logs (identical to gh run view)
        --job JOB_ID       View specific job log
        --log              View full log
        --log-failed       View logs for failed jobs only
        -v, --verbose      Show job steps in detail
        --exit-status      Exit with non-zero status if run failed
        -a, --attempt NUM  Show logs for specific attempt
        -w, --web          Open run in web browser (not supported)

    run watch [RUN_ID]     Watch run progress (identical to gh run watch)
        -i, --interval N   Refresh interval in seconds (default: 3)
        --exit-status      Exit with same status as run
        --compact          Show only relevant/failed steps

ENVIRONMENT VARIABLES:
    LOG_DIR               Log directory path (default: ./logs)
    PIPELINE_TIMEOUT      Total pipeline timeout in seconds (default: 86400)
    MEMORY_LIMIT_MB       Memory limit per process in MB (default: 2048)
    TIMEOUT               Individual command timeout in seconds (default: 86400)
    VERBOSE               Set to 1 for verbose output
    ATOMIFY               Set to 0 to disable atomification globally

WORKFLOW:
    1. Add commands to queue:
       sep_queue.sh -- ruff check src/
       sep_queue.sh -- pytest tests/

    2. View queue status:
       sep_queue.sh --queue-status

    3. Start execution:
       sep_queue.sh --queue-start

    4. Pause/Resume as needed:
       sep_queue.sh --queue-pause
       sep_queue.sh --queue-resume

ATOMIFICATION:
    Commands are automatically broken down into atomic operations:
    - "ruff check src/" becomes individual "ruff check src/file.py" commands
    - Each atomic command is added as a separate queue entry
    - Single files are not atomified (already atomic)
    - Atomified commands maintain order

SPECIAL HANDLING:
    Git Commands:
        - Checks for concurrent git operations
        - Prevents git lock conflicts
        - Handles pre-commit hooks safely
        - Sets GIT_COMMIT_IN_PROGRESS for commits

    Make Commands:
        - Prevents parallel make execution
        - Automatically adds -j1 if not specified
        - Handles recursive makefiles safely

EXAMPLES:
    # Add commands to queue
    sep_queue.sh -- git add -A
    sep_queue.sh -- ruff format src/
    sep_queue.sh -- pytest tests/
    sep_queue.sh -- git commit -m "feat: new feature"

    # Check queue
    sep_queue.sh --queue-status

    # Start processing
    sep_queue.sh --queue-start

LOG FILES:
    Default location: ./logs (in project root)
    Can be changed with: --log-dir PATH or LOG_DIR environment variable
    Execution logs: logs/sep_queue_*.log
    Memory logs: logs/sep_memory_monitor_*.log
    Run logs: logs/queue_run_*.log

LOCK FILES:
    Lock directory: PROJECT_ROOT/.sequential-locks/sep-exec-PROJECT_HASH/
    Queue file: PROJECT_ROOT/.sequential-locks/sep-exec-PROJECT_HASH/queue.txt
    Pause file: PROJECT_ROOT/.sequential-locks/sep-exec-PROJECT_HASH/paused
    Running file: PROJECT_ROOT/.sequential-locks/sep-exec-PROJECT_HASH/running

EOF
    exit 0
}

# Queue management commands
queue_status() {
    if [[ ! -f "$QUEUE_FILE" ]]; then
        echo "Queue is empty"
        return
    fi

    echo "Queue Status:"
    echo "============="

    # Check if running
    if [[ -f "$RUNNING_FILE" ]]; then
        local runner_pid=$(cat "$RUNNING_FILE" 2>/dev/null || echo 0)
        if [[ $runner_pid -gt 0 ]] && kill -0 "$runner_pid" 2>/dev/null; then
            echo "Status: RUNNING (PID: $runner_pid)"
        else
            rm -f "$RUNNING_FILE"
            echo "Status: STOPPED"
        fi
    elif [[ -f "$PAUSE_FILE" ]]; then
        echo "Status: PAUSED"
    else
        echo "Status: STOPPED"
    fi

    # Show current command
    if [[ -f "$CURRENT_PID_FILE" ]]; then
        local current_pid=$(cat "$CURRENT_PID_FILE" 2>/dev/null || echo 0)
        if [[ $current_pid -gt 0 ]] && kill -0 "$current_pid" 2>/dev/null; then
            local current_cmd=$(ps -p "$current_pid" -o args= 2>/dev/null || echo "unknown")
            echo "Current: PID $current_pid - $current_cmd"
        fi
    fi

    # Show queue
    echo ""
    echo "Queued Commands:"
    local count=0
    while IFS=: read -r pid timestamp cmd; do
        ((count++)) || true
        echo "  $count. PID $pid - $cmd"
    done < "$QUEUE_FILE"

    if [[ $count -eq 0 ]]; then
        echo "  (none)"
    else
        echo ""
        echo "Total: $count commands"
    fi
}

# Helper function to load metadata from a file into variables
# Usage: load_metadata <file_path>
# Sets: RUN_ID, START_TIME, PID, STATUS, PROJECT, END_TIME, DURATION, EXIT_CODE, BRANCH, WORKFLOW, RUN_USER, COMMIT, EVENT, CREATED
load_metadata() {
    local meta_file="$1"

    # Reset variables
    RUN_ID="" START_TIME="" PID="" STATUS="" PROJECT="" END_TIME="" DURATION="" EXIT_CODE="" BRANCH="" WORKFLOW=""
    RUN_USER="" COMMIT="" EVENT="" CREATED=""  # New fields (RUN_USER to avoid conflict with system USER)
    JOB_ID="" COMMAND="" LOG_FILE=""  # Job-specific fields

    if [[ ! -f "$meta_file" ]]; then
        return 1
    fi

    while IFS='=' read -r key value; do
        case "$key" in
            RUN_ID) RUN_ID="$value" ;;
            START_TIME) START_TIME="$value" ;;
            PID) PID="$value" ;;
            STATUS) STATUS="$value" ;;
            PROJECT) PROJECT="$value" ;;
            END_TIME) END_TIME="$value" ;;
            DURATION) DURATION="$value" ;;
            EXIT_CODE) EXIT_CODE="$value" ;;
            BRANCH) BRANCH="$value" ;;
            WORKFLOW) WORKFLOW="$value" ;;
            USER) RUN_USER="$value" ;;  # Map old USER field to RUN_USER
            RUN_USER) RUN_USER="$value" ;;
            COMMIT) COMMIT="$value" ;;
            EVENT) EVENT="$value" ;;
            CREATED) CREATED="$value" ;;
            # Job-specific fields
            JOB_ID) JOB_ID="$value" ;;
            SESSION_ID) RUN_ID="$value" ;;  # Handle old field name
            COMMAND) COMMAND="$value" ;;
            LOG_FILE) LOG_FILE="$value" ;;
        esac
    done < "$meta_file"

    # Provide defaults for backward compatibility
    if [[ -z "$RUN_USER" ]]; then
        RUN_USER="${USER:-unknown}"  # Use system USER as fallback
    fi
    if [[ -z "$EVENT" ]]; then
        EVENT="manual"
    fi
    if [[ -z "$CREATED" ]] && [[ -n "$START_TIME" ]]; then
        CREATED="$START_TIME"
    fi

    return 0
}

# Helper function to get status display (icon and color)
# Usage: get_status_display <status> <exit_code>
# Returns: Sets STATUS_ICON and STATUS_COLOR variables
get_status_display() {
    local status="$1"
    local exit_code="${2:-0}"

    case $status in
        running)
            STATUS_ICON="⚡"
            STATUS_COLOR="$YELLOW"
            ;;
        completed)
            if [[ "$exit_code" -eq 0 ]]; then
                STATUS_ICON="✓"
                STATUS_COLOR="$GREEN"
            else
                STATUS_ICON="✗"
                STATUS_COLOR="$RED"
            fi
            ;;
        stopped)
            STATUS_ICON="⊘"
            STATUS_COLOR="$YELLOW"
            ;;
        *)
            STATUS_ICON="?"
            STATUS_COLOR="$NC"
            ;;
    esac
}

# Helper function to calculate duration between two timestamps
# Usage: calculate_duration <start_time> <end_time>
# Returns: Sets DURATION_STR variable
calculate_duration() {
    local start_time="$1"
    local end_time="$2"

    local start_epoch=$(date -j -f "%Y-%m-%d %H:%M:%S" "$start_time" "+%s" 2>/dev/null || date -d "$start_time" "+%s" 2>/dev/null || echo 0)
    local end_epoch=$(date -j -f "%Y-%m-%d %H:%M:%S" "$end_time" "+%s" 2>/dev/null || date -d "$end_time" "+%s" 2>/dev/null || echo 0)
    local duration=$((end_epoch - start_epoch))
    local hours=$((duration / 3600))
    local minutes=$(((duration % 3600) / 60))
    local seconds=$((duration % 60))

    DURATION_STR="${hours}h ${minutes}m ${seconds}s"
}

# Helper function for cross-platform date parsing
# Usage: parse_date_to_epoch <date_string> [format]
# Returns: epoch time or 0 on failure
parse_date_to_epoch() {
    local date_str="$1"
    local format="${2:-%Y-%m-%d %H:%M:%S}"

    # Try macOS date first
    local epoch=$(date -j -f "$format" "$date_str" "+%s" 2>/dev/null)
    if [[ -z "$epoch" ]] || [[ "$epoch" == "0" ]]; then
        # Try GNU date
        epoch=$(date -d "$date_str" "+%s" 2>/dev/null || echo 0)
    fi
    echo "${epoch:-0}"
}

# Queue management functions
queue_start() {
    # Check if already running
    if [[ -f "$RUNNING_FILE" ]]; then
        local runner_pid=$(cat "$RUNNING_FILE" 2>/dev/null || echo 0)
        if [[ $runner_pid -gt 0 ]] && kill -0 "$runner_pid" 2>/dev/null; then
            echo "Queue is already running (PID: $runner_pid)"
            return 1
        else
            rm -f "$RUNNING_FILE"
        fi
    fi

    # Allow starting empty queue - it will wait for commands

    echo "Starting queue processing..."
    echo $$ > "$RUNNING_FILE"

    # Generate run ID
    local run_id=$(date '+%Y%m%d_%H%M%S')
    local run_start=$(date '+%Y-%m-%d %H:%M:%S')
    echo "$run_start" > "$RUN_START_FILE"
    echo "$run_id" > "$CURRENT_RUN_FILE"

    # Create run metadata directory
    local run_meta_dir="${RUNS_DIR}/${run_id}"
    mkdir -p "${run_meta_dir}/jobs"

    # Get git information if in git repo
    local current_branch=""
    local commit_sha=""
    local git_user=""
    if [[ -d "$PROJECT_ROOT/.git" ]]; then
        current_branch=$(git -C "$PROJECT_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
        commit_sha=$(git -C "$PROJECT_ROOT" rev-parse HEAD 2>/dev/null || echo "")
        git_user=$(git -C "$PROJECT_ROOT" config user.name 2>/dev/null || echo "${USER:-unknown}")
    fi

    # Store run metadata
    cat > "${run_meta_dir}/metadata.txt" << EOF
RUN_ID=$run_id
START_TIME=$run_start
PID=$$
STATUS=running
PROJECT=$PROJECT_ROOT
BRANCH=$current_branch
WORKFLOW=sep_queue
RUN_USER=$git_user
COMMIT=$commit_sha
EVENT=manual
CREATED=$run_start
EOF

    # Create run log
    local RUN_LOG="${LOGS_DIR}/queue_run_${run_id}_$$.log"
    echo "Queue Run Started: $run_start" > "$RUN_LOG"
    echo "Project: $PROJECT_ROOT" >> "$RUN_LOG"
    echo "PID: $$" >> "$RUN_LOG"
    echo "========================================" >> "$RUN_LOG"

    # Store run info for subprocesses
    echo "$RUN_LOG" > "${LOCK_DIR}/run_log"
    echo "$run_id" > "${LOCK_DIR}/run_id"

    # Need to ensure functions are available
    # Call this script recursively with special internal flag
    "$0" --internal-process-queue
    local exit_code=$?

    rm -f "$RUNNING_FILE"

    # Record run end
    local run_end=$(date '+%Y-%m-%d %H:%M:%S')
    echo "========================================" >> "$RUN_LOG"
    echo "Queue Run Ended: $run_end" >> "$RUN_LOG"
    echo "Exit Code: $exit_code" >> "$RUN_LOG"

    # Calculate run duration if run start file exists
    if [[ -f "$RUN_START_FILE" ]]; then
        local start_epoch=$(parse_date_to_epoch "$run_start")
        local end_epoch=$(date "+%s")
        local duration=$((end_epoch - start_epoch))
        local hours=$((duration / 3600))
        local minutes=$(((duration % 3600) / 60))
        local seconds=$((duration % 60))
        echo "Session Duration: ${hours}h ${minutes}m ${seconds}s" >> "$RUN_LOG"
        rm -f "$RUN_START_FILE"
    fi

    # Update run status
    if [[ -f "$CURRENT_RUN_FILE" ]]; then
        local run_id=$(cat "$CURRENT_RUN_FILE")
        local run_meta_dir="${RUNS_DIR}/${run_id}"
        if [[ -f "${run_meta_dir}/metadata.txt" ]]; then
            sed -i.bak "s/STATUS=running/STATUS=completed/" "${run_meta_dir}/metadata.txt" 2>/dev/null || \
            sed -i "" "s/STATUS=running/STATUS=completed/" "${run_meta_dir}/metadata.txt"
            echo "END_TIME=$run_end" >> "${run_meta_dir}/metadata.txt"
            echo "EXIT_CODE=$exit_code" >> "${run_meta_dir}/metadata.txt"
            echo "DURATION=${hours}h ${minutes}m ${seconds}s" >> "${run_meta_dir}/metadata.txt"
        fi
    fi

    # Clean up run references
    rm -f "${LOCK_DIR}/run_log"
    rm -f "${LOCK_DIR}/run_id"
    rm -f "$CURRENT_RUN_FILE"

    if [[ $exit_code -eq 0 ]]; then
        echo "Queue processing completed successfully"
    else
        echo "Queue processing failed with exit code: $exit_code"
    fi

    return $exit_code
}

queue_pause() {
    touch "$PAUSE_FILE"
    echo "Queue paused. Use --queue-resume to continue."
}

queue_resume() {
    rm -f "$PAUSE_FILE"
    echo "Queue resumed."
}

queue_stop() {
    echo "Stopping queue and clearing all pending commands..."

    # Create run log if run was running
    if [[ -f "$RUN_START_FILE" ]]; then
        local run_start=$(cat "$RUN_START_FILE")
        local run_end=$(date '+%Y-%m-%d %H:%M:%S')
        local RUN_LOG="${LOGS_DIR}/queue_run_stopped_$(date '+%Y%m%d_%H%M%S')_$$.log"

        echo "Queue Run Started: $run_start" > "$RUN_LOG"
        echo "Project: $PROJECT_ROOT" >> "$RUN_LOG"
        echo "========================================" >> "$RUN_LOG"
        echo "Session was stopped by user" >> "$RUN_LOG"
        echo "========================================" >> "$RUN_LOG"
        echo "Queue Run Ended: $run_end" >> "$RUN_LOG"
        echo "Exit Code: 130 (User stopped)" >> "$RUN_LOG"

        # Calculate run duration
        local start_epoch=$(parse_date_to_epoch "$run_start")
        local end_epoch=$(date "+%s")
        local duration=$((end_epoch - start_epoch))
        local hours=$((duration / 3600))
        local minutes=$(((duration % 3600) / 60))
        local seconds=$((duration % 60))
        echo "Session Duration: ${hours}h ${minutes}m ${seconds}s" >> "$RUN_LOG"

        # Update run status to stopped
        if [[ -f "$CURRENT_RUN_FILE" ]]; then
            local stopped_run_id=$(cat "$CURRENT_RUN_FILE")
            local stopped_meta_dir="${RUNS_DIR}/${stopped_run_id}"
            if [[ -f "${stopped_meta_dir}/metadata.txt" ]]; then
                sed -i.bak "s/STATUS=running/STATUS=stopped/" "${stopped_meta_dir}/metadata.txt" 2>/dev/null || \
                sed -i "" "s/STATUS=running/STATUS=stopped/" "${stopped_meta_dir}/metadata.txt"
                echo "END_TIME=$run_end" >> "${stopped_meta_dir}/metadata.txt"
                echo "EXIT_CODE=130" >> "${stopped_meta_dir}/metadata.txt"
                echo "DURATION=${hours}h ${minutes}m ${seconds}s" >> "${stopped_meta_dir}/metadata.txt"
                echo "STOPPED_BY=user" >> "${stopped_meta_dir}/metadata.txt"
            fi
        fi

        rm -f "$RUN_START_FILE"
        rm -f "${LOCK_DIR}/run_log"
        rm -f "${LOCK_DIR}/run_id"
        rm -f "$CURRENT_RUN_FILE"
    fi

    # Stop the runner process if running
    if [[ -f "$RUNNING_FILE" ]]; then
        local runner_pid=$(cat "$RUNNING_FILE" 2>/dev/null || echo 0)
        if [[ $runner_pid -gt 0 ]] && kill -0 "$runner_pid" 2>/dev/null; then
            echo "Stopping runner process: PID $runner_pid"
            kill "$runner_pid" 2>/dev/null || true
        fi
        rm -f "$RUNNING_FILE"
    fi

    # Kill current process if running
    if [[ -f "$CURRENT_PID_FILE" ]]; then
        local current_pid=$(cat "$CURRENT_PID_FILE" 2>/dev/null || echo 0)
        if [[ $current_pid -gt 0 ]] && kill -0 "$current_pid" 2>/dev/null; then
            echo "Killing current process: PID $current_pid"
            kill_process_tree "$current_pid"
        fi
    fi

    # Clear queue
    > "$QUEUE_FILE"
    rm -f "$PAUSE_FILE"
    echo "Queue stopped and cleared."
}

clear_queue() {
    echo "Clearing all entries from the queue..."

    # Clear the queue file
    > "$QUEUE_FILE"

    echo "Queue cleared. The queue will continue running if active."
}

close_queue() {
    echo "Closing queue - no new commands will be accepted..."

    # Create closed marker file
    touch "$CLOSED_FILE"

    echo "Queue closed. Use --reopen-queue to accept new commands again."
}

reopen_queue() {
    if [[ ! -f "$CLOSED_FILE" ]]; then
        echo "Queue is not closed."
        return 0
    fi

    echo "Reopening queue for new commands..."

    # Remove closed marker file
    rm -f "$CLOSED_FILE"

    echo "Queue reopened. New commands can now be added."
}

# List runs (similar to gh run list)
# Shows recent queue runs with filtering and formatting options
#
# Arguments:
#   $1 - limit: Maximum number of runs to show (default: 20)
#   $2 - status_filter: Filter by status (running, completed, stopped)
#   $3 - branch_filter: Filter by git branch
#   $4 - workflow_filter: Filter by workflow name
#   $5 - json_output: Output as JSON (true/false)
#   $6 - json_fields: Specific JSON fields to output
#   $7 - template: Go template for formatting (unused)
#   $8 - all_workflows: Include all workflows (true/false)
#   $9 - user_filter: Filter by user (unused in our context)
#   $10 - commit_filter: Filter by commit SHA (unused)
#   $11 - event_filter: Filter by event type (unused)
#   $12 - created_filter: Filter by creation date (unused)
#   $13 - jq_filter: JQ expression to filter JSON output
#
# Returns:
#   0 on success, 1 on error
#   Outputs formatted run list to stdout
list_runs() {
    local limit="${1:-$DEFAULT_LIST_LIMIT}"
    local status_filter="${2:-}"
    local branch_filter="${3:-}"
    local workflow_filter="${4:-}"
    local json_output="${5:-false}"
    local json_fields="${6:-}"
    local template="${7:-}"
    local all_workflows="${8:-}"
    local user_filter="${9:-}"
    local commit_filter="${10:-}"
    local event_filter="${11:-}"
    local created_filter="${12:-}"
    local jq_filter="${13:-}"

    # Determine current branch if in git repo
    local current_branch=""
    if [[ -d "$PROJECT_ROOT/.git" ]]; then
        current_branch=$(git -C "$PROJECT_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
    fi

    # Get runs sorted by date (newest first)
    local runs=()
    if [[ -d "$RUNS_DIR" ]]; then
        # Use glob expansion instead of ls
        local run_dirs=()
        for run_path in "$RUNS_DIR"/*; do
            [[ -d "$run_path" ]] || continue
            local run_dir=$(basename "$run_path")
            [[ -f "${run_path}/metadata.txt" ]] || continue
            run_dirs+=("$run_dir")
        done
        # Sort by modification time using stat
        if [[ ${#run_dirs[@]} -gt 0 ]]; then
            while IFS= read -r run_dir; do
                runs+=("$run_dir")
            done < <(for dir in "${run_dirs[@]}"; do
                stat -f "%m %N" "$RUNS_DIR/$dir" 2>/dev/null || stat -c "%Y %n" "$RUNS_DIR/$dir" 2>/dev/null
            done | sort -rn | cut -d' ' -f2- | xargs -n1 basename)
        fi
    fi

    if [[ ${#runs[@]} -eq 0 ]]; then
        if [[ "$json_output" == "true" ]]; then
            echo "[]"
        else
            echo "No runs found."
        fi
        return 0
    fi

    # Filter and display runs
    local count=0
    local json_array="["
    local first_item=true

    for run in "${runs[@]}"; do
        [[ $count -ge $limit ]] && break

        local meta_file="${RUNS_DIR}/${run}/metadata.txt"
        # Load run metadata using helper function
        load_metadata "$meta_file" || continue

        # Apply filters
        if [[ -n "$status_filter" ]]; then
            # Special handling for "failed" status
            if [[ "$status_filter" == "failed" ]]; then
                if [[ "$STATUS" != "completed" ]] || [[ "${EXIT_CODE:-0}" -eq 0 ]]; then
                    continue
                fi
            elif [[ "$STATUS" != "$status_filter" ]]; then
                continue
            fi
        fi

        # If no branch in metadata, assume current branch
        if [[ -z "$BRANCH" ]] && [[ -n "$current_branch" ]]; then
            BRANCH="$current_branch"
        fi

        if [[ -n "$branch_filter" ]] && [[ "$BRANCH" != "$branch_filter" ]]; then
            continue
        fi

        if [[ -n "$workflow_filter" ]] && [[ "$WORKFLOW" != "$workflow_filter" ]]; then
            continue
        fi

        # Apply additional filters
        if [[ -n "$user_filter" ]] && [[ "$RUN_USER" != "$user_filter" ]]; then
            continue
        fi

        if [[ -n "$commit_filter" ]] && [[ "$COMMIT" != "$commit_filter" ]]; then
            continue
        fi

        if [[ -n "$event_filter" ]] && [[ "$EVENT" != "$event_filter" ]]; then
            continue
        fi

        # Date filter - compare created date
        if [[ -n "$created_filter" ]]; then
            # Convert both dates to epoch for comparison
            local created_epoch=$(parse_date_to_epoch "${CREATED:-$START_TIME}")
            local filter_epoch=$(parse_date_to_epoch "$created_filter" "%Y-%m-%d")
            if [[ $created_epoch -eq 0 ]] || [[ $filter_epoch -eq 0 ]] || [[ $created_epoch -lt $filter_epoch ]]; then
                continue
            fi
        fi

        # Count jobs
        local job_count=0
        if [[ -d "${RUNS_DIR}/${run}/jobs" ]]; then
            # Count job files using glob
            for job_file in "${RUNS_DIR}/${run}/jobs"/*; do
                [[ -f "$job_file" ]] && ((job_count++))
            done
        fi

        if [[ "$json_output" == "true" ]]; then
            [[ "$first_item" == "false" ]] && json_array+=","
            first_item=false

            # Map our status to GitHub status names
            local gh_status="$STATUS"
            if [[ "$STATUS" == "running" ]]; then
                gh_status="in_progress"
            elif [[ "$STATUS" == "completed" ]] && [[ "${EXIT_CODE:-0}" -ne 0 ]]; then
                gh_status="failure"
            elif [[ "$STATUS" == "completed" ]]; then
                gh_status="success"
            elif [[ "$STATUS" == "stopped" ]]; then
                gh_status="cancelled"
            fi

            # Calculate elapsed time
            local created_at="$START_TIME"
            local updated_at="${END_TIME:-$(date '+%Y-%m-%d %H:%M:%S')}"

            json_array+="{\"databaseId\":$count,"
            json_array+="\"name\":\"$RUN_ID\","
            json_array+="\"displayTitle\":\"Queue Run $RUN_ID\","
            json_array+="\"status\":\"$gh_status\","
            json_array+="\"conclusion\":\"$gh_status\","
            json_array+="\"workflowName\":\"${WORKFLOW:-sep_queue}\","
            json_array+="\"headBranch\":\"$BRANCH\","
            json_array+="\"headSha\":\"${COMMIT:-}\","
            json_array+="\"createdAt\":\"$created_at\","
            json_array+="\"updatedAt\":\"$updated_at\","
            json_array+="\"startedAt\":\"$START_TIME\","
            json_array+="\"workflowDatabaseId\":1,"
            json_array+="\"url\":\"file://${RUNS_DIR}/${run}\","
            json_array+="\"actor\":{\"login\":\"${RUN_USER:-unknown}\"},"
            json_array+="\"event\":\"${EVENT:-manual}\""
            json_array+="}"
        else
            # Terminal output - use helper for status display
            get_status_display "$STATUS" "${EXIT_CODE:-0}"

            printf "${STATUS_COLOR}%s${NC} %-20s %-10s %s" "$STATUS_ICON" "$RUN_ID" "$STATUS" "$START_TIME"
            if [[ -n "$BRANCH" ]]; then
                printf " (branch: %s)" "$BRANCH"
            fi
            if [[ $job_count -gt 0 ]]; then
                printf " [%d jobs]" "$job_count"
            fi
            if [[ -n "${DURATION:-}" ]]; then
                printf " %s" "$DURATION"
            fi
            echo ""
        fi

        ((count++)) || true
    done

    if [[ "$json_output" == "true" ]]; then
        json_array+="]"

        # Apply field filtering and/or JQ filtering
        local output="$json_array"

        # Field filtering
        if [[ -n "$json_fields" ]] && command -v jq >/dev/null 2>&1; then
            # Convert space-separated fields to JQ select expression
            local field_list=$(echo "$json_fields" | tr ' ' ',')
            output=$(echo "$output" | jq ".[] | {$field_list}" | jq -s '.')
        fi

        # JQ expression filtering
        if [[ -n "$jq_filter" ]] && command -v jq >/dev/null 2>&1; then
            output=$(echo "$output" | jq "$jq_filter")
        elif [[ -n "$jq_filter" ]]; then
            echo "Warning: jq not installed, cannot apply filter" >&2
        fi

        echo "$output"
    fi
}

# Watch run progress (similar to gh run watch)
# Monitors a queue run in real-time with automatic refresh
#
# Arguments:
#   $1 - run_id: ID of the run to watch (optional, defaults to latest running)
#   $2 - interval: Refresh interval in seconds (default: 3)
#   $3 - exit_status: Exit with same status as run (true/false)
#   $4 - compact: Show only failed/relevant steps (true/false)
#
# Returns:
#   0 on success, or run's exit code if exit_status is true
#   Displays live updating run status to stdout
watch_run() {
    local run_id="$1"
    local interval="${2:-$DEFAULT_WATCH_INTERVAL}"
    local exit_status="${3:-false}"
    local compact="${4:-false}"

    # If no run_id specified, get the latest running run
    if [[ -z "$run_id" ]]; then
        if [[ -d "$RUNS_DIR" ]]; then
            # Find the latest running run using glob
            for run_path in "$RUNS_DIR"/*; do
                [[ -d "$run_path" ]] || continue
                local run_dir=$(basename "$run_path")
                if [[ -f "${run_path}/metadata.txt" ]]; then
                    local test_status=$(grep "^STATUS=" "${run_path}/metadata.txt" | cut -d= -f2)
                    if [[ "$test_status" == "running" ]]; then
                        run_id="$run_dir"
                        break
                    fi
                fi
            done
        fi

        if [[ -z "$run_id" ]]; then
            echo "No running runs found."
            return 1
        fi
    fi

    local meta_file="${RUNS_DIR}/${run_id}/metadata.txt"
    if [[ ! -f "$meta_file" ]]; then
        echo "Error: Run $run_id not found."
        return 1
    fi

    # Watch loop
    local last_job_count=0
    while true; do
        # Clear screen
        printf "\033c"

        # Load run metadata using helper
        load_metadata "$meta_file"

        # Display header
        echo "Watching run: $RUN_ID"
        echo "Status: $STATUS"
        echo "Started: $START_TIME"
        if [[ -n "$END_TIME" ]]; then
            echo "Ended: $END_TIME"
        fi
        if [[ -n "$BRANCH" ]]; then
            echo "Branch: $BRANCH"
        fi
        echo ""

        # Display jobs
        echo "Jobs:"
        echo "====="
        local job_count=0
        if [[ -d "${RUNS_DIR}/${run_id}/jobs" ]]; then
            for job_path in "${RUNS_DIR}/${run_id}/jobs"/*; do
                [[ -f "$job_path" ]] || continue
                local job_meta="$job_path"
                local JOB_ID="" JOB_STATUS="" JOB_COMMAND="" JOB_START="" JOB_END="" JOB_EXIT=""
                while IFS='=' read -r key value; do
                    case "$key" in
                        JOB_ID) JOB_ID="$value" ;;
                        STATUS) JOB_STATUS="$value" ;;
                        COMMAND) JOB_COMMAND="$value" ;;
                        START_TIME) JOB_START="$value" ;;
                        END_TIME) JOB_END="$value" ;;
                        EXIT_CODE) JOB_EXIT="$value" ;;
                    esac
                done < "$job_meta"

                # Skip if compact mode and job succeeded
                if [[ "$compact" == "true" ]] && [[ "$JOB_STATUS" == "completed" ]] && [[ "${JOB_EXIT:-0}" -eq 0 ]]; then
                    continue
                fi

                # Use helper for job status display
                get_status_display "$JOB_STATUS" "${JOB_EXIT:-0}"

                printf "${STATUS_COLOR}%s${NC} %-20s %s\n" "$STATUS_ICON" "$JOB_ID" "$JOB_COMMAND"
                ((job_count++)) || true
            done
        fi

        # Check if run completed
        if [[ "$STATUS" != "running" ]]; then
            echo ""
            echo "Run completed with status: $STATUS"
            if [[ -n "$EXIT_CODE" ]]; then
                echo "Exit code: $EXIT_CODE"
            fi

            if [[ "$exit_status" == "true" ]] && [[ -n "$EXIT_CODE" ]]; then
                exit "$EXIT_CODE"
            else
                exit 0
            fi
        fi

        # Show update time
        echo ""
        echo "Last updated: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "Press Ctrl+C to stop watching"

        # Sleep for interval
        sleep "$interval"
    done
}

# View runs and jobs (similar to gh run view)
# Displays detailed information about runs and jobs with optional log viewing
#
# Arguments:
#   $1 - run_id: ID of the run to view (optional, interactive if not provided)
#   $2 - job_id: ID of a specific job to view
#   $3 - show_log: Show full logs (true/false)
#   $4 - show_failed: Show only failed job logs (true/false)
#   $5 - verbose: Show detailed job steps (true/false)
#   $6 - exit_status: Exit with run's exit status (true/false)
#   $7 - attempt: Show logs for specific attempt number (not implemented - no retry mechanism)
#
# Returns:
#   0 on success, 1 on error, or run's exit code if exit_status is true
#   Displays run/job information to stdout
view_runs() {
    local run_id="$1"
    local job_id="$2"
    local show_log="$3"
    local show_failed="$4"
    local verbose="$5"
    local exit_status="$6"
    local attempt="$7"

    # Note: attempt parameter is accepted for GitHub CLI compatibility but not used
    # as this implementation doesn't support retrying failed runs
    if [[ -n "$attempt" ]] && [[ "$attempt" != "1" ]]; then
        echo "Warning: Attempt number specified but retry mechanism not implemented" >&2
    fi

    # If no run_id specified, show recent runs interactively
    if [[ -z "$run_id" ]] && [[ -z "$job_id" ]]; then
        echo "Recent Queue Runs:"
        echo "====================="
        echo ""

        # List recent runs
        local runs=()
        if [[ -d "$RUNS_DIR" ]]; then
            # Get runs sorted by date (newest first) using stat for modification time
            local run_dirs=()
            for run_path in "$RUNS_DIR"/*/; do
                [[ -d "$run_path" ]] || continue
                run_dir="${run_path%/}"
                run_dir="${run_dir##*/}"
                if [[ -f "${RUNS_DIR}/${run_dir}/metadata.txt" ]]; then
                    # Get modification time for sorting
                    local mtime
                    if [[ "$OSTYPE" == "darwin"* ]]; then
                        mtime=$(stat -f "%m" "${RUNS_DIR}/${run_dir}" 2>/dev/null || echo 0)
                    else
                        mtime=$(stat -c "%Y" "${RUNS_DIR}/${run_dir}" 2>/dev/null || echo 0)
                    fi
                    run_dirs+=("$mtime:$run_dir")
                fi
            done

            # Sort by modification time (newest first) and limit
            if [[ ${#run_dirs[@]} -gt 0 ]]; then
                while IFS= read -r entry; do
                    runs+=("${entry#*:}")
                done < <(printf '%s\n' "${run_dirs[@]}" | sort -rn | head -$INTERACTIVE_RUN_LIMIT)
            fi
        fi

        if [[ ${#runs[@]} -eq 0 ]]; then
            echo "No runs found."
            return 0
        fi

        # Display runs
        local i=1
        for run in "${runs[@]}"; do
            local meta_file="${RUNS_DIR}/${run}/metadata.txt"
            # Load run metadata using helper
            load_metadata "$meta_file" || continue

            # Get status display using helper
            get_status_display "$STATUS" "${EXIT_CODE:-0}"

            printf "%2d. %s ${STATUS_COLOR}%-10s${NC} %s" "$i" "$RUN_ID" "$STATUS" "$START_TIME"
            if [[ -n "${DURATION:-}" ]]; then
                printf " (Duration: %s)" "$DURATION"
            fi
            if [[ "${EXIT_CODE:-0}" -ne 0 ]]; then
                printf " ${RED}[Exit: %s]${NC}" "$EXIT_CODE"
            fi
            echo ""
            ((i++)) || true
        done

        echo ""
        echo "Select a run number (1-${#runs[@]}) or press Enter to cancel: "
        read -r selection

        if [[ -z "$selection" ]] || ! [[ "$selection" =~ ^[0-9]+$ ]] || [[ $selection -lt 1 ]] || [[ $selection -gt ${#runs[@]} ]]; then
            return 0
        fi

        run_id="${runs[$((selection-1))]}"
    fi

    # View specific job
    if [[ -n "$job_id" ]]; then
        view_job "$job_id" "$show_log" "$verbose"
        return $?
    fi

    # View specific run/run
    if [[ -n "$run_id" ]]; then
        view_run "$run_id" "$show_log" "$show_failed" "$verbose" "$exit_status"
        return $?
    fi
}

# View a specific run
# Displays detailed information about a single run including all its jobs
#
# Arguments:
#   $1 - run_id: ID of the run to view
#   $2 - show_log: Show full run log (true/false)
#   $3 - show_failed: Show only failed job logs (true/false)
#   $4 - verbose: Show detailed information (true/false)
#   $5 - exit_status: Exit with run's exit status (true/false)
#
# Returns:
#   0 on success, 1 if run not found, or run's exit code if exit_status is true
view_run() {
    local run_id="$1"
    local show_log="$2"
    local show_failed="$3"
    local verbose="$4"
    local exit_status="$5"

    local meta_file="${RUNS_DIR}/${run_id}/metadata.txt"
    if [[ ! -f "$meta_file" ]]; then
        echo "Error: Run $run_id not found."
        return 1
    fi

    # Load run metadata using helper
    load_metadata "$meta_file"

    echo "Run: $RUN_ID"
    echo "========================================"
    echo "Status: $STATUS"
    echo "Start Time: $START_TIME"
    if [[ -n "${END_TIME:-}" ]]; then
        echo "End Time: $END_TIME"
    fi
    if [[ -n "${DURATION:-}" ]]; then
        echo "Duration: $DURATION"
    fi
    if [[ -n "${EXIT_CODE:-}" ]]; then
        echo "Exit Code: $EXIT_CODE"
    fi
    echo "Project: $PROJECT"
    if [[ -n "${RUN_USER:-}" ]]; then
        echo "User: $RUN_USER"
    fi
    if [[ -n "${BRANCH:-}" ]]; then
        echo "Branch: $BRANCH"
    fi
    if [[ -n "${COMMIT:-}" ]]; then
        echo "Commit: ${COMMIT:0:8}"  # Show short SHA
    fi
    echo ""

    # List jobs
    echo "Jobs:"
    echo "-----"
    local job_count=0
    local failed_jobs=()

    if [[ -d "${RUNS_DIR}/${run_id}/jobs" ]]; then
        # Get job files sorted by modification time
        local job_files=()
        for job_file in "${RUNS_DIR}/${run_id}/jobs/"*.txt; do
            [[ -f "$job_file" ]] || continue
            local mtime
            if [[ "$OSTYPE" == "darwin"* ]]; then
                mtime=$(stat -f "%m" "$job_file" 2>/dev/null || echo 0)
            else
                mtime=$(stat -c "%Y" "$job_file" 2>/dev/null || echo 0)
            fi
            job_files+=("$mtime:$job_file")
        done

        # Sort by modification time (newest first)
        if [[ ${#job_files[@]} -gt 0 ]]; then
            while IFS= read -r entry; do
                job_file="${entry#*:}"
                ((job_count++)) || true
            # Read job metadata
            local job_id="" job_status="" job_command="" job_exit_code="" job_log_file=""
            while IFS='=' read -r key value; do
                case "$key" in
                    JOB_ID) job_id="$value" ;;
                    STATUS) job_status="$value" ;;
                    COMMAND) job_command="$value" ;;
                    EXIT_CODE) job_exit_code="$value" ;;
                    LOG_FILE) job_log_file="$value" ;;
                esac
            done < "$job_file"

            local job_status_color=""
            case "$job_status" in
                running) job_status_color="$YELLOW" ;;
                completed)
                    if [[ "${job_exit_code:-0}" -eq 0 ]]; then
                        job_status_color="$GREEN"
                    else
                        job_status_color="$RED"
                        failed_jobs+=("$job_id")
                    fi
                    ;;
                *) job_status_color="$NC" ;;
            esac

            printf "  ${job_status_color}%-20s${NC} %s" "$job_id" "$job_command"
            if [[ "${job_exit_code:-0}" -ne 0 ]]; then
                printf " ${RED}[Exit: %s]${NC}" "$job_exit_code"
            fi
            echo ""

            if [[ "$verbose" == "true" ]] && [[ -n "$job_log_file" ]]; then
                echo "    Log: $job_log_file"
            fi
            done < <(printf '%s\n' "${job_files[@]}" | sort -rn)
        fi
    fi

    if [[ $job_count -eq 0 ]]; then
        echo "  (No jobs found)"
    fi

    echo ""

    # Show run log if requested
    if [[ "$show_log" == "true" ]]; then
        local run_log="${LOGS_DIR}/queue_run_${run_id}_${PID}.log"
        if [[ ! -f "$run_log" ]]; then
            # Try without PID
            # Find first matching log file using glob
            local log_files=("${LOGS_DIR}/queue_run_${run_id}_"*.log)
            if [[ -f "${log_files[0]}" ]]; then
                run_log="${log_files[0]}"
            else
                run_log=""
            fi
        fi

        if [[ -f "$run_log" ]]; then
            echo "Session Log:"
            echo "============"
            cat "$run_log"
        else
            echo "Session log not found."
        fi
    elif [[ "$show_failed" == "true" ]] && [[ ${#failed_jobs[@]} -gt 0 ]]; then
        echo "Failed Job Logs:"
        echo "================"
        for failed_job in "${failed_jobs[@]}"; do
            view_job "$failed_job" "true" "false"
            echo ""
        done
    fi

    # Handle exit status flag
    if [[ "$exit_status" == "true" ]] && [[ -n "${EXIT_CODE:-}" ]]; then
        exit "$EXIT_CODE"
    fi
}

# View a specific job
# Displays detailed information about a single job
#
# Arguments:
#   $1 - job_id: ID of the job to view
#   $2 - show_log: Show full job log (true/false)
#   $3 - verbose: Show detailed information (true/false)
#
# Returns:
#   0 on success, 1 if job not found
view_job() {
    local job_id="$1"
    local show_log="$2"
    local verbose="$3"

    # Find job in any run
    local job_meta_file=""
    # Use glob to find job file in any run directory
    for run_path in "$RUNS_DIR"/*/; do
        [[ -d "$run_path" ]] || continue
        local test_file="${run_path}jobs/${job_id}.txt"
        if [[ -f "$test_file" ]]; then
            job_meta_file="$test_file"
            break
        fi
    done

    if [[ -z "$job_meta_file" ]] || [[ ! -f "$job_meta_file" ]]; then
        echo "Error: Job $job_id not found."
        return 1
    fi

    # Load job metadata
    local job_id_val="" run_id="" job_status="" job_command="" job_start_time=""
    local job_end_time="" job_exit_code="" job_log_file=""
    while IFS='=' read -r key value; do
        case "$key" in
            JOB_ID) job_id_val="$value" ;;
            RUN_ID) run_id="$value" ;;
            STATUS) job_status="$value" ;;
            COMMAND) job_command="$value" ;;
            START_TIME) job_start_time="$value" ;;
            END_TIME) job_end_time="$value" ;;
            EXIT_CODE) job_exit_code="$value" ;;
            LOG_FILE) job_log_file="$value" ;;
        esac
    done < "$job_meta_file"

    echo "Job: $job_id_val"
    echo "========================================"
    echo "Run: $run_id"
    echo "Status: $job_status"
    echo "Command: $job_command"
    echo "Start Time: $job_start_time"
    if [[ -n "$job_end_time" ]]; then
        echo "End Time: $job_end_time"
    fi
    if [[ -n "$job_exit_code" ]]; then
        echo "Exit Code: $job_exit_code"
    fi
    echo ""

    # Show job log if requested
    if [[ "$show_log" == "true" ]] && [[ -n "$job_log_file" ]]; then
        if [[ -f "$job_log_file" ]]; then
            echo "Job Log:"
            echo "========"
            cat "$job_log_file"
        else
            echo "Job log file not found: $job_log_file"
        fi
    fi
}

# Parse command line options
CUSTOM_LOG_DIR=""
ATOMIFY="${ATOMIFY:-1}"  # Enable atomification by default
ENFORCE_RUNNERS="${ENFORCE_RUNNERS:-1}"  # Enforce runners by default
ONLY_VERIFIED="${ONLY_VERIFIED:-0}"  # Don't skip unrecognized by default
ENABLE_SECOND_TIER="${ENABLE_SECOND_TIER:-0}"  # Disable second-tier by default
PARSED_TIMEOUT=""
PARSED_PIPELINE_TIMEOUT=""
PARSED_MEMORY_LIMIT=""
PARSED_VERBOSE=""
QUEUE_COMMAND=""
VIEW_RUN_ID=""
VIEW_JOB_ID=""
VIEW_LOG=false
VIEW_LOG_FAILED=false
VIEW_VERBOSE=false
LIST_LIMIT=$DEFAULT_LIST_LIMIT
LIST_STATUS=""
LIST_BRANCH=""
LIST_WORKFLOW=""
LIST_JSON=false
LIST_JSON_FIELDS=""
LIST_TEMPLATE=""
LIST_JQ=""
LIST_ALL_WORKFLOWS=false
LIST_USER=""
LIST_COMMIT=""
LIST_EVENT=""
LIST_CREATED=""
VIEW_EXIT_STATUS=false
VIEW_ATTEMPT=""
WATCH_RUN_ID=""
WATCH_INTERVAL=$DEFAULT_WATCH_INTERVAL
WATCH_EXIT_STATUS=false
WATCH_COMPACT=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --help|-h)
            show_help
            ;;
        --version)
            echo "sep_queue.sh v$VERSION"
            exit 0
            ;;
        --timeout)
            PARSED_TIMEOUT="$2"
            shift 2
            ;;
        --pipeline-timeout)
            PARSED_PIPELINE_TIMEOUT="$2"
            shift 2
            ;;
        --memory-limit)
            PARSED_MEMORY_LIMIT="$2"
            shift 2
            ;;
        --log-dir)
            CUSTOM_LOG_DIR="$2"
            shift 2
            ;;
        --verbose)
            PARSED_VERBOSE=1
            shift
            ;;
        --no-atomify)
            ATOMIFY=0
            shift
            ;;
        --dont_enforce_runners)
            ENFORCE_RUNNERS=0
            shift
            ;;
        --only_verified)
            ONLY_VERIFIED=1
            shift
            ;;
        --enable-second-tier)
            ENABLE_SECOND_TIER=1
            shift
            ;;
        run)
            # GitHub CLI compatible commands
            shift
            if [[ $# -eq 0 ]]; then
                echo "Error: Missing subcommand for 'run'" >&2
                echo "Available subcommands: list, view, watch" >&2
                exit 1
            fi

            case $1 in
                list)
                    QUEUE_COMMAND="list"
                    shift
                    # Parse list options
                    while [[ $# -gt 0 ]]; do
                        case $1 in
                            -L|--limit)
                                LIST_LIMIT="$2"
                                shift 2
                                ;;
                            -s|--status)
                                # Map GitHub status names to our names
                                case "$2" in
                                    queued) LIST_STATUS="queued" ;;
                                    in_progress) LIST_STATUS="running" ;;
                                    completed) LIST_STATUS="completed" ;;
                                    failed) LIST_STATUS="failed" ;; # Special case handled in filter
                                    cancelled) LIST_STATUS="stopped" ;;
                                    *) LIST_STATUS="$2" ;;
                                esac
                                shift 2
                                ;;
                            -b|--branch)
                                LIST_BRANCH="$2"
                                shift 2
                                ;;
                            -w|--workflow)
                                LIST_WORKFLOW="$2"
                                shift 2
                                ;;
                            --json)
                                LIST_JSON=true
                                if [[ $# -gt 1 ]] && [[ ! "$2" =~ ^- ]]; then
                                    LIST_JSON_FIELDS="$2"
                                    shift
                                fi
                                shift
                                ;;
                            -t|--template)
                                LIST_TEMPLATE="$2"
                                shift 2
                                ;;
                            -q|--jq)
                                LIST_JQ="$2"
                                shift 2
                                ;;
                            -a|--all)
                                LIST_ALL_WORKFLOWS=true
                                shift
                                ;;
                            -u|--user)
                                LIST_USER="$2"
                                shift 2
                                ;;
                            -c|--commit)
                                LIST_COMMIT="$2"
                                shift 2
                                ;;
                            -e|--event)
                                LIST_EVENT="$2"
                                shift 2
                                ;;
                            --created)
                                LIST_CREATED="$2"
                                shift 2
                                ;;
                            *)
                                break
                                ;;
                        esac
                    done
                    ;;
                view)
                    QUEUE_COMMAND="view"
                    shift
                    # Check for run ID (if next arg doesn't start with -)
                    if [[ $# -gt 0 ]] && [[ ! "$1" =~ ^- ]]; then
                        VIEW_RUN_ID="$1"
                        shift
                    fi
                    # Parse view options
                    while [[ $# -gt 0 ]]; do
                        case $1 in
                            --job)
                                VIEW_JOB_ID="$2"
                                shift 2
                                ;;
                            --log)
                                VIEW_LOG=true
                                shift
                                ;;
                            --log-failed)
                                VIEW_LOG_FAILED=true
                                shift
                                ;;
                            -v|--verbose)
                                VIEW_VERBOSE=true
                                shift
                                ;;
                            --exit-status)
                                VIEW_EXIT_STATUS=true
                                shift
                                ;;
                            -a|--attempt)
                                VIEW_ATTEMPT="$2"
                                shift 2
                                ;;
                            -w|--web)
                                echo "Error: --web option not supported (no web interface)" >&2
                                exit 1
                                ;;
                            *)
                                break
                                ;;
                        esac
                    done
                    ;;
                watch)
                    QUEUE_COMMAND="watch"
                    shift
                    # Check for run ID (if next arg doesn't start with -)
                    if [[ $# -gt 0 ]] && [[ ! "$1" =~ ^- ]]; then
                        WATCH_RUN_ID="$1"
                        shift
                    fi
                    # Parse watch options
                    while [[ $# -gt 0 ]]; do
                        case $1 in
                            -i|--interval)
                                WATCH_INTERVAL="$2"
                                shift 2
                                ;;
                            --exit-status)
                                WATCH_EXIT_STATUS=true
                                shift
                                ;;
                            --compact)
                                WATCH_COMPACT=true
                                shift
                                ;;
                            *)
                                break
                                ;;
                        esac
                    done
                    ;;
                *)
                    echo "Error: Unknown run subcommand: $1" >&2
                    echo "Available subcommands: list, view, watch" >&2
                    exit 1
                    ;;
            esac
            ;;
        --queue-start)
            QUEUE_COMMAND="start"
            shift
            ;;
        --queue-status)
            QUEUE_COMMAND="status"
            shift
            ;;
        --queue-pause)
            QUEUE_COMMAND="pause"
            shift
            ;;
        --queue-resume)
            QUEUE_COMMAND="resume"
            shift
            ;;
        --queue-stop)
            QUEUE_COMMAND="stop"
            shift
            ;;
        --clear-queue)
            QUEUE_COMMAND="clear"
            shift
            ;;
        --close-queue)
            QUEUE_COMMAND="close"
            shift
            ;;
        --reopen-queue)
            QUEUE_COMMAND="reopen"
            shift
            ;;
        --internal-process-queue)
            QUEUE_COMMAND="internal-process"
            shift
            ;;
        --)
            shift
            break
            ;;
        *)
            break
            ;;
    esac
done

# Verify minimum bash version (3.2+)
if [[ "${BASH_VERSINFO[0]}" -lt 3 ]] || { [[ "${BASH_VERSINFO[0]}" -eq 3 ]] && [[ "${BASH_VERSINFO[1]}" -lt 2 ]]; }; then
    echo "ERROR: This script requires bash 3.2 or higher" >&2
    echo "Current version: $BASH_VERSION" >&2
    exit 1
fi

# Global configuration
PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
PROJECT_HASH=$(echo "$PROJECT_ROOT" | shasum | cut -d' ' -f1 | head -c 8)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Lock and state files - simple relative paths
LOCK_BASE_DIR="${SEQUENTIAL_LOCK_BASE_DIR:-./.sequential-locks}"
LOCK_DIR="${LOCK_BASE_DIR}/sep-exec-${PROJECT_HASH}"
LOCKFILE="${LOCK_DIR}/executor.lock"
# Source .env.development if it exists
if [ -f "${PROJECT_ROOT}/.env.development" ]; then
    set -a  # Export all variables
    source "${PROJECT_ROOT}/.env.development"
    set +a
fi

# Pipeline timeout (applies to entire chain)
PIPELINE_TIMEOUT="${PARSED_PIPELINE_TIMEOUT:-${PIPELINE_TIMEOUT:-$DEFAULT_PIPELINE_TIMEOUT}}"
MEMORY_LIMIT_MB="${PARSED_MEMORY_LIMIT:-${MEMORY_LIMIT_MB:-$DEFAULT_MEMORY_LIMIT_MB}}"
TIMEOUT="${PARSED_TIMEOUT:-${TIMEOUT:-$DEFAULT_TIMEOUT}}"
VERBOSE="${PARSED_VERBOSE:-${VERBOSE:-0}}"

# Create logs directory - simple relative path
LOGS_DIR="${CUSTOM_LOG_DIR:-./logs}"
mkdir -p "$LOGS_DIR"

# Now define paths that depend on LOGS_DIR
QUEUE_FILE="${LOCK_DIR}/queue.txt"
CURRENT_PID_FILE="${LOCK_DIR}/current.pid"
PIPELINE_TIMEOUT_FILE="${LOCK_DIR}/pipeline_timeout.txt"
PAUSE_FILE="${LOCK_DIR}/paused"
RUNNING_FILE="${LOCK_DIR}/running"
CLOSED_FILE="${LOCK_DIR}/closed"
RUN_START_FILE="${LOCK_DIR}/run_start"
RUNS_DIR="${LOGS_DIR}/runs"
CURRENT_RUN_FILE="${LOCK_DIR}/current_run"

# Ensure lock directory exists
mkdir -p "$LOCK_DIR"
mkdir -p "$RUNS_DIR"
EXEC_LOG="${LOGS_DIR}/sep_queue_$(date '+%Y%m%d_%H%M%S')_$$.log"

# Defer handling queue management commands until functions are defined

# Check for help or no arguments (but not if we have a queue command)
if [[ $# -eq 0 ]] && [[ -z "$QUEUE_COMMAND" ]]; then
    show_help
fi

# Get the command and its arguments
COMMAND="${1:-}"
shift || true
ARGS=("$@")

# Colors are now defined in sep_common.sh

# Logging functions
log() {
    local level=$1; shift
    local color=""
    case $level in
        ERROR) color=$RED ;;
        WARN)  color=$YELLOW ;;
        INFO)  color=$GREEN ;;
        DEBUG) color=$BLUE ;;
    esac
    local msg
    msg="[SEQ-QUEUE] $(date '+%Y-%m-%d %H:%M:%S') [$level] $*"
    echo -e "${color}${msg}${NC}" >&2
    echo "$msg" >> "$EXEC_LOG"
}

# Get all descendant PIDs of a given process
# Recursively finds all child processes
#
# Arguments:
#   $1 - pid: Process ID to find descendants for
#
# Returns:
#   Prints PIDs of all descendants, one per line
get_descendants() {
    local pid=$1
    local children
    children=$(pgrep -P "$pid" 2>/dev/null || true)
    for child in $children; do
        echo "$child"
        get_descendants "$child"
    done
}

# Kill entire process tree including all descendants
# Sends signal to parent and all child processes
#
# Arguments:
#   $1 - pid: Root process ID to kill
#   $2 - signal: Signal to send (default: TERM)
#
# Returns:
#   0 on success (all processes terminated)
kill_process_tree() {
    local pid=$1
    local signal=${2:-TERM}

    # Get all descendants first
    local all_pids
    all_pids="$pid $(get_descendants "$pid")"

    # Send signal to all
    for p in $all_pids; do
        if kill -0 "$p" 2>/dev/null; then
            kill -"$signal" "$p" 2>/dev/null || true
        fi
    done

    # Give time to terminate gracefully
    sleep 2

    # Force kill any remaining
    for p in $all_pids; do
        if kill -0 "$p" 2>/dev/null; then
            kill -KILL "$p" 2>/dev/null || true
        fi
    done
}

# Git-specific safety checks to prevent concurrent operations
# Checks for existing git processes that might conflict
#
# Arguments:
#   $1 - git_cmd: Git subcommand being executed (e.g., commit, push)
#
# Returns:
#   0 if safe to proceed, 1 if conflict detected
check_git_safety() {
    local git_cmd="${1:-}"

    # Skip if already in a git hook to prevent deadlocks
    if [ -n "${GIT_DIR:-}" ] || [ -n "${GIT_WORK_TREE:-}" ]; then
        log INFO "Already in git hook - skipping safety checks"
        return 0
    fi

    # Check for existing git operations
    local git_procs
    git_procs=$(pgrep -f "git (commit|merge|rebase|cherry-pick|push|pull)" 2>/dev/null || true)

    for pid in $git_procs; do
        # Skip our own process
        [ "$pid" -eq "$$" ] && continue

        local cmd
        cmd=$(ps -p "$pid" -o args= 2>/dev/null || echo "unknown")
        log ERROR "Git operation already in progress: PID $pid - $cmd"
        return 1
    done

    # Check for git lock files
    if [ -f "$PROJECT_ROOT/.git/index.lock" ]; then
        log ERROR "Git index lock exists - another git process may be running"
        log WARN "To force remove: rm -f $PROJECT_ROOT/.git/index.lock"
        return 1
    fi

    # Set environment for commit hooks
    if [[ "$git_cmd" == "commit" ]]; then
        export GIT_COMMIT_IN_PROGRESS=1
        export SEQUENTIAL_EXECUTOR_PID=$$
        log INFO "Set GIT_COMMIT_IN_PROGRESS=1 for pre-commit hooks"
    fi

    return 0
}

# Prepare make command with safety options
# Ensures make runs with -j1 to prevent parallel builds
#
# Arguments:
#   $@ - make command arguments
#
# Returns:
#   Prints modified make arguments
prepare_make_command() {
    local make_args=("$@")

    # Check if -j is already specified
    local has_j_flag=0
    for arg in "${make_args[@]}"; do
        if [[ "$arg" =~ ^-j ]]; then
            has_j_flag=1
            break
        fi
    done

    # Add -j1 if not specified
    if [ $has_j_flag -eq 0 ]; then
        make_args+=("-j1")
        log WARN "Added -j1 to make command for safety"
    fi

    echo "${make_args[@]}"
}

# Check and enforce pipeline timeout
# Monitors total execution time and kills all processes if exceeded
#
# Arguments:
#   None (uses global PIPELINE_TIMEOUT variable)
#
# Returns:
#   0 if within timeout, exits script if timeout exceeded
check_pipeline_timeout() {
    if [ ! -f "$PIPELINE_TIMEOUT_FILE" ]; then
        # First process in pipeline - set timeout
        echo "$(date +%s):$PIPELINE_TIMEOUT" > "$PIPELINE_TIMEOUT_FILE"
        log INFO "Pipeline timeout set to ${PIPELINE_TIMEOUT}s"

        # Start timeout monitor in background
        (
            sleep "$PIPELINE_TIMEOUT"
            if [ -f "$PIPELINE_TIMEOUT_FILE" ]; then
                log ERROR "PIPELINE TIMEOUT after ${PIPELINE_TIMEOUT}s - killing all processes"

                # Kill all processes in queue
                if [ -f "$QUEUE_FILE" ]; then
                    while IFS=: read -r pid _ cmd; do
                        if kill -0 "$pid" 2>/dev/null; then
                            log WARN "Killing queued process PID $pid"
                            kill_process_tree "$pid"
                        fi
                    done < "$QUEUE_FILE"
                fi

                # Kill current process
                if [ -f "$CURRENT_PID_FILE" ]; then
                    local current
                    current=$(cat "$CURRENT_PID_FILE" 2>/dev/null || echo 0)
                    if [ "$current" -gt 0 ] && kill -0 "$current" 2>/dev/null; then
                        log WARN "Killing current process PID $current"
                        kill_process_tree "$current"
                    fi
                fi

                # Clean up all locks
                rm -rf "$LOCK_DIR"
            fi
        ) &
    else
        # Check if pipeline already timed out
        local timeout_info
        timeout_info=$(cat "$PIPELINE_TIMEOUT_FILE" 2>/dev/null || echo "0:0")
        # Validate timeout_info format
        if [[ ! "$timeout_info" =~ ^[0-9]+:[0-9]+$ ]]; then
            log WARN "Invalid pipeline timeout format, resetting"
            timeout_info="0:0"
        fi
        local start_time
        start_time=$(echo "$timeout_info" | cut -d: -f1)
        local timeout_val
        timeout_val=$(echo "$timeout_info" | cut -d: -f2)
        local now
        now=$(date +%s)
        local elapsed=$((now - start_time))

        if [ $elapsed -gt "$timeout_val" ]; then
            log ERROR "Pipeline already timed out (${elapsed}s > ${timeout_val}s)"
            # Clean up stale timeout file
            rm -f "$PIPELINE_TIMEOUT_FILE"
            log INFO "Cleaned up stale pipeline timeout - restarting pipeline"
            # Restart pipeline with fresh timeout
            echo "$(date +%s):$PIPELINE_TIMEOUT" > "$PIPELINE_TIMEOUT_FILE"
            log INFO "Pipeline timeout reset to ${PIPELINE_TIMEOUT}s"
        fi

        log INFO "Pipeline time remaining: $((timeout_val - elapsed))s"
    fi
}

# Execute a single command from the queue
execute_command() {
    local cmd_string="$1"
    local cmd_array=()

    # Generate job ID
    local job_id="job_$(date '+%Y%m%d_%H%M%S')_$(openssl rand -hex 3 2>/dev/null || echo $RANDOM)"

    # Parse command string into array (safer than eval)
    IFS=' ' read -ra cmd_array <<< "$cmd_string"

    local command="${cmd_array[0]}"
    local args=("${cmd_array[@]:1}")

    # Apply special handling based on command type
    case "$command" in
        git)
            log INFO "Detected git command - applying safety checks"
            if ! check_git_safety "${args[0]:-}"; then
                return 1
            fi
            ;;
        make)
            log INFO "Detected make command - enforcing sequential execution"
            # Prepare make arguments
            mapfile -t args < <(prepare_make_command "${args[@]}")
            ;;
        *)
            # No special handling needed
            ;;
    esac

    log INFO "Executing: $command ${args[*]} (Job: $job_id)"

    # Create job metadata if run is active
    if [[ -f "${LOCK_DIR}/run_id" ]]; then
        local run_id=$(cat "${LOCK_DIR}/run_id" 2>/dev/null)
        if [[ -n "$run_id" ]]; then
            local job_meta_file="${RUNS_DIR}/${run_id}/jobs/${job_id}.txt"
            local job_start=$(date '+%Y-%m-%d %H:%M:%S')
            cat > "$job_meta_file" << EOF
JOB_ID=$job_id
RUN_ID=$run_id
START_TIME=$job_start
COMMAND=$command ${args[*]}
STATUS=running
EOF
        fi
    fi

    # Log command start to run log if run is active
    if [[ -f "${LOCK_DIR}/run_log" ]]; then
        local cmd_start=$(date '+%Y-%m-%d %H:%M:%S')
        local run_log=$(cat "${LOCK_DIR}/run_log" 2>/dev/null)
        if [[ -n "$run_log" ]] && [[ -f "$run_log" ]]; then
            echo "" >> "$run_log"
            echo "Job ID: $job_id" >> "$run_log"
            echo "Command Started: $cmd_start" >> "$run_log"
            echo "Command: $command ${args[*]}" >> "$run_log"
        fi
    fi

    # Start memory monitor
    local monitor_pid=""
    if [ -x "${SCRIPT_DIR}/sep_memory_monitor.sh" ]; then
        log INFO "Starting memory monitor"
        "${SCRIPT_DIR}/sep_memory_monitor.sh" --pid $$ --limit "$MEMORY_LIMIT_MB" &
        monitor_pid=$!
    fi

    # Ensure sep.sh is available
    if [ ! -x "${SCRIPT_DIR}/sep.sh" ]; then
        log ERROR "sep.sh not found at: ${SCRIPT_DIR}/sep.sh"
        log ERROR "This script requires sep.sh for atomic execution"
        return 1
    fi

    # Execute through sep.sh with job ID
    JOB_ID="$job_id" "${SCRIPT_DIR}/sep.sh" --timeout "$TIMEOUT" -- "$command" "${args[@]}"
    local exit_code=$?

    # Stop memory monitor
    if [[ -n "$monitor_pid" ]]; then
        kill "$monitor_pid" 2>/dev/null || true
    fi

    # Update job metadata
    if [[ -f "${LOCK_DIR}/run_id" ]]; then
        local run_id=$(cat "${LOCK_DIR}/run_id" 2>/dev/null)
        if [[ -n "$run_id" ]]; then
            local job_meta_file="${RUNS_DIR}/${run_id}/jobs/${job_id}.txt"
            if [[ -f "$job_meta_file" ]]; then
                local job_end=$(date '+%Y-%m-%d %H:%M:%S')
                sed -i.bak "s/STATUS=running/STATUS=completed/" "$job_meta_file" 2>/dev/null || \
                sed -i "" "s/STATUS=running/STATUS=completed/" "$job_meta_file"
                echo "END_TIME=$job_end" >> "$job_meta_file"
                echo "EXIT_CODE=$exit_code" >> "$job_meta_file"

                # Link to sep log if it exists
                local sep_log="${LOGS_DIR}/sep_${job_id}.log"
                if [[ -f "$sep_log" ]]; then
                    echo "LOG_FILE=$sep_log" >> "$job_meta_file"

                    # Parse pytest results if this was a pytest command
                    if [[ "$command" == "pytest" ]] || [[ "$cmd_string" =~ pytest ]]; then
                        local results_file="${RUNS_DIR}/${run_id}/jobs/${job_id}_pytest_results.json"
                        if [[ -x "${SCRIPT_DIR}/parse_pytest_results.sh" ]]; then
                            "${SCRIPT_DIR}/parse_pytest_results.sh" "$sep_log" "$results_file" >/dev/null 2>&1 || true
                            if [[ -f "$results_file" ]]; then
                                echo "PYTEST_RESULTS=$results_file" >> "$job_meta_file"

                                # Extract summary stats and add to metadata
                                local passed=$(python3 -c "import json; d=json.load(open('$results_file')); print(d.get('summary',{}).get('passed',0))" 2>/dev/null || echo "0")
                                local failed=$(python3 -c "import json; d=json.load(open('$results_file')); print(d.get('summary',{}).get('failed',0))" 2>/dev/null || echo "0")
                                local total=$(python3 -c "import json; d=json.load(open('$results_file')); print(d.get('summary',{}).get('total',0))" 2>/dev/null || echo "0")

                                echo "TESTS_PASSED=$passed" >> "$job_meta_file"
                                echo "TESTS_FAILED=$failed" >> "$job_meta_file"
                                echo "TESTS_TOTAL=$total" >> "$job_meta_file"

                                # Print test results to run log
                                if [[ -n "$run_log" ]] && [[ -f "$run_log" ]]; then
                                    echo "" >> "$run_log"
                                    echo "Test Results: PASSED=$passed FAILED=$failed TOTAL=$total" >> "$run_log"
                                    if [[ $failed -gt 0 ]]; then
                                        echo "FAILED TESTS:" >> "$run_log"
                                        python3 -c "
import json
with open('$results_file') as f:
    data = json.load(f)
    for test in data.get('tests', []):
        if test.get('result') == 'FAILED':
            print(f\"  - {test.get('test', 'unknown')}\")" >> "$run_log" 2>/dev/null || true
                                    fi
                                fi

                                # Also print to job log
                                echo "" >> "$sep_log"
                                echo "=== TEST RESULTS ===" >> "$sep_log"
                                echo "PASSED: $passed" >> "$sep_log"
                                echo "FAILED: $failed" >> "$sep_log"
                                echo "TOTAL: $total" >> "$sep_log"
                            fi
                        fi
                    fi
                fi
            fi
        fi
    fi

    # Log command end to run log if run is active
    if [[ -f "${LOCK_DIR}/run_log" ]]; then
        local run_log=$(cat "${LOCK_DIR}/run_log" 2>/dev/null)
        if [[ -n "$run_log" ]] && [[ -f "$run_log" ]]; then
            local cmd_end=$(date '+%Y-%m-%d %H:%M:%S')
            echo "Command Ended: $cmd_end" >> "$run_log"
            echo "Exit Code: $exit_code" >> "$run_log"
        fi
    fi

    log INFO "Command completed with exit code: $exit_code"
    return $exit_code
}

# Process the queue
process_queue() {
    local overall_exit_code=0

    # Check pipeline timeout
    check_pipeline_timeout

    while true; do
        # Check if paused
        while [[ -f "$PAUSE_FILE" ]]; do
            log INFO "Queue is paused. Waiting..."
            sleep 5
        done

        # Check if queue is empty
        if [[ ! -s "$QUEUE_FILE" ]]; then
            log INFO "Queue is empty - waiting for new commands..."
            sleep 5
            continue
        fi

        # Get next command from queue
        local next_cmd=""
        local next_pid=""

        # Read first line and remove it atomically
        # Use a simple lock file approach since flock is not available on macOS
        local lock_acquired=0
        local lock_file="${QUEUE_FILE}.lock"

        # Try to acquire lock
        for i in {1..30}; do
            if mkdir "$lock_file" 2>/dev/null; then
                lock_acquired=1
                break
            fi
            sleep 0.1
        done

        if [[ $lock_acquired -eq 1 ]]; then
            if [[ -s "$QUEUE_FILE" ]]; then
                IFS=: read -r next_pid _ next_cmd < "$QUEUE_FILE"
                tail -n +2 "$QUEUE_FILE" > "${QUEUE_FILE}.tmp"
                mv -f "${QUEUE_FILE}.tmp" "$QUEUE_FILE"
            fi
            rmdir "$lock_file" 2>/dev/null || true
        else
            log WARN "Failed to acquire queue lock after 3 seconds"
            continue
        fi

        if [[ -z "$next_cmd" ]]; then
            continue
        fi

        # Wait for lock
        log INFO "Waiting for exclusive lock..."
        while true; do
            if mkdir "$LOCKFILE" 2>/dev/null; then
                echo $$ > "$CURRENT_PID_FILE"
                log INFO "Lock acquired"
                break
            fi

            # Check if current holder is alive
            local holder_pid=$(cat "$CURRENT_PID_FILE" 2>/dev/null || echo 0)
            if [[ $holder_pid -gt 0 ]] && ! kill -0 "$holder_pid" 2>/dev/null; then
                log WARN "Lock holder died, cleaning up"
                rm -f "$CURRENT_PID_FILE"
                rmdir "$LOCKFILE" 2>/dev/null || true
            fi

            sleep 1
        done

        # Execute command
        execute_command "$next_cmd"
        local exit_code=$?

        if [[ $exit_code -ne 0 ]]; then
            log ERROR "Command failed with exit code: $exit_code"
            overall_exit_code=$exit_code
            # Continue processing queue even on failure
        fi

        # Release lock
        rm -f "$CURRENT_PID_FILE"
        rmdir "$LOCKFILE" 2>/dev/null || true
        log INFO "Lock released"
    done

    # Clean up pipeline timeout if queue is empty
    if [[ ! -s "$QUEUE_FILE" ]]; then
        rm -f "$PIPELINE_TIMEOUT_FILE"
        log INFO "Pipeline complete - cleaned up timeout"
    fi

    return $overall_exit_code
}

# Cleanup function
cleanup() {
    local exit_code=$?

    # Don't remove from queue - commands should only be removed when executed
    # Only clean up if we're the runner

    # Clean up running file if we're the runner
    if [[ "$QUEUE_COMMAND" == "start" ]] && [[ -f "$RUNNING_FILE" ]]; then
        local runner_pid=$(cat "$RUNNING_FILE" 2>/dev/null || echo 0)
        if [[ $runner_pid -eq $$ ]]; then
            rm -f "$RUNNING_FILE"
        fi
    fi

    log INFO "Sequential queue exiting with code: $exit_code"
    [[ $VERBOSE -eq 1 ]] && echo "Log saved to: $EXEC_LOG" >&2

    exit $exit_code
}

trap cleanup EXIT INT TERM

# Now handle queue management commands (functions are defined)
if [[ -n "$QUEUE_COMMAND" ]]; then
    case "$QUEUE_COMMAND" in
        start) queue_start ;;
        status) queue_status ;;
        pause) queue_pause ;;
        resume) queue_resume ;;
        stop) queue_stop ;;
        clear) clear_queue ;;
        close) close_queue ;;
        reopen) reopen_queue ;;
        list) list_runs "$LIST_LIMIT" "$LIST_STATUS" "$LIST_BRANCH" "$LIST_WORKFLOW" "$LIST_JSON" "$LIST_JSON_FIELDS" "$LIST_TEMPLATE" "$LIST_ALL_WORKFLOWS" "$LIST_USER" "$LIST_COMMIT" "$LIST_EVENT" "$LIST_CREATED" "$LIST_JQ" ;;
        view) view_runs "$VIEW_RUN_ID" "$VIEW_JOB_ID" "$VIEW_LOG" "$VIEW_LOG_FAILED" "$VIEW_VERBOSE" "$VIEW_EXIT_STATUS" "$VIEW_ATTEMPT" ;;
        watch) watch_run "$WATCH_RUN_ID" "$WATCH_INTERVAL" "$WATCH_EXIT_STATUS" "$WATCH_COMPACT" ;;
        internal-process) process_queue ;;
    esac
    exit $?
fi

# Only process commands if not a queue management command
if [[ -z "$QUEUE_COMMAND" ]]; then
    # Check if queue is closed
    if [[ -f "$CLOSED_FILE" ]]; then
        log ERROR "Queue is closed and not accepting new commands"
        echo "[SEQ-QUEUE] ERROR: Queue is closed. Use --reopen-queue to accept new commands."
        exit 1
    fi

    log INFO "Adding command to queue: $COMMAND ${ARGS[*]}"
    log INFO "Project: $PROJECT_ROOT"

    # Export flags for tool config
    export ENABLE_SECOND_TIER

    # STEP 0: Enforce runners if enabled
    if [[ $ENFORCE_RUNNERS -eq 1 ]]; then
        # Source tool config for runner enforcement
        if [[ -f "${SCRIPT_DIR}/sep_tool_config.sh" ]]; then
            source "${SCRIPT_DIR}/sep_tool_config.sh"

            # Check and enforce runner
            enforced_cmd=()
            # Capture both output and exit code
            enforce_output=$(enforce_runner "$COMMAND" "${ARGS[@]}" 2>&1)
            enforce_result=$?

            if [[ $enforce_result -eq 0 ]]; then
                # Successfully enforced or no enforcement needed
                if [[ -n "$enforce_output" ]]; then
                    mapfile -t enforced_cmd <<< "$enforce_output"
                    if [[ ${#enforced_cmd[@]} -gt 0 ]]; then
                        COMMAND="${enforced_cmd[0]}"
                        ARGS=("${enforced_cmd[@]:1}")
                        log INFO "Command after runner enforcement: $COMMAND ${ARGS[*]}"
                    fi
                fi
            elif [[ $enforce_result -eq 2 ]]; then
                # Unsupported runner detected (poetry, conda, etc.)
                log WARN "Unsupported runner detected. SEP only supports: uv, pipx, pnpm, go, npx"
                log INFO "Running command as-is without atomification"
                ATOMIFY=0  # Disable atomification for unsupported runners
            elif [[ $enforce_result -eq 1 ]] && [[ $ONLY_VERIFIED -eq 1 ]]; then
                # Unrecognized tool and --only_verified is set
                log WARN "Unrecognized tool '$COMMAND' - skipping due to --only_verified flag"
                echo "[SEQ-QUEUE] WARNING: Unrecognized tool '$COMMAND' - skipped"
                echo "[SEQ-QUEUE] To run anyway, remove --only_verified flag"
                exit 0
            fi
        fi
    fi

    # STEP 1: Check if command can be atomified
    if [[ $ATOMIFY -eq 1 ]]; then
        # Source atomifier if available
        ATOMIFIER_SCRIPT="${SCRIPT_DIR}/sep_tool_atomifier.sh"
        if [[ -f "$ATOMIFIER_SCRIPT" ]]; then
            source "$ATOMIFIER_SCRIPT"

            # Generate atomic commands
            mapfile -t ATOMIC_COMMANDS < <(generate_atomic_commands "$COMMAND" "${ARGS[@]}" | grep "^ATOMIC:")

            [[ "${VERBOSE:-0}" -eq 1 ]] && echo "[SEQ-QUEUE] DEBUG: Generated ${#ATOMIC_COMMANDS[@]} atomic commands" >&2

            if [[ ${#ATOMIC_COMMANDS[@]} -gt 1 ]]; then
                echo "[SEQ-QUEUE] Command will be atomified into ${#ATOMIC_COMMANDS[@]} atomic operations" >&2

                # STEP 2-7: Add all atomic commands to queue
                cmd_count=0
                for atomic_cmd in "${ATOMIC_COMMANDS[@]}"; do
                    ((cmd_count++)) || true
                    # Remove ATOMIC: prefix
                    actual_cmd="${atomic_cmd#ATOMIC:}"

                    # Add to queue
                    echo "$$:$(date '+%s'):$actual_cmd" >> "$QUEUE_FILE"
                    echo "[SEQ-QUEUE] Added atomic command $cmd_count/${#ATOMIC_COMMANDS[@]} to queue"
                done

                echo "[SEQ-QUEUE] All ${#ATOMIC_COMMANDS[@]} atomic commands added to queue"
                echo "[SEQ-QUEUE] Use 'sep_queue.sh --queue-start' to begin processing"
                exit 0
            elif [[ ${#ATOMIC_COMMANDS[@]} -eq 1 ]]; then
                # Single file - proceed with default sequence
                log INFO "Single atomic command detected, adding to queue"
            fi
        fi
    fi

    # STEP 8: DEFAULT SEQUENCE - Add single command to queue
    echo "$$:$(date '+%s'):$COMMAND ${ARGS[*]}" >> "$QUEUE_FILE"
    echo "[SEQ-QUEUE] Command added to queue"
    echo "[SEQ-QUEUE] Use 'sep_queue.sh --queue-start' to begin processing"
fi
