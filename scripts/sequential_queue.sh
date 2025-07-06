#!/usr/bin/env bash
# sequential_queue.sh - Universal sequential execution queue manager
# Version: 8.0.0
#
# This version implements the correct flow:
# 1. Commands are added to queue (atomified if possible)
# 2. Queue is NOT executed automatically
# 3. Queue execution happens only with --queue-start
# 4. All commands execute in exact order of addition
#
set -euo pipefail

VERSION='8.1.0'

# Display help message
show_help() {
    cat << 'EOF'
sequential_queue.sh v8.1.0 - Universal sequential execution queue

USAGE:
    sequential_queue.sh [OPTIONS] -- COMMAND [ARGS...]
    sequential_queue.sh --queue-start
    sequential_queue.sh --queue-status
    sequential_queue.sh --queue-pause
    sequential_queue.sh --queue-resume
    sequential_queue.sh --queue-stop
    sequential_queue.sh --help

DESCRIPTION:
    Manages a sequential execution queue for commands.
    Commands are added to queue but NOT executed automatically.
    Use --queue-start to begin processing the queue.
    Auto-detects git and make commands for special handling.
    Automatically atomifies commands to process files individually.

OPTIONS:
    --help, -h             Show this help message
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
    --list                 List recent runs (similar to gh run list)
        -L, --limit N      Maximum number of runs to fetch (default: 20)
        -s, --status STR   Filter by status (running, completed, stopped)
        -b, --branch STR   Filter by branch
        -w, --workflow STR Filter by workflow name
        --json [FIELDS]    Output JSON with specified fields
        -t, --template STR Format JSON output using Go template
        -a, --all          Include all workflows
    --view [RUN_ID]        View run logs (similar to gh run view)
    --view --job JOB_ID    View specific job log
    --view --log           View full log for run or job
    --view --log-failed    View logs for failed jobs only
    --view --verbose       Show job steps in detail
    --watch [RUN_ID]       Watch run progress (similar to gh run watch)
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
       sequential_queue.sh -- ruff check src/
       sequential_queue.sh -- pytest tests/

    2. View queue status:
       sequential_queue.sh --queue-status

    3. Start execution:
       sequential_queue.sh --queue-start

    4. Pause/Resume as needed:
       sequential_queue.sh --queue-pause
       sequential_queue.sh --queue-resume

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
    sequential_queue.sh -- git add -A
    sequential_queue.sh -- ruff format src/
    sequential_queue.sh -- pytest tests/
    sequential_queue.sh -- git commit -m "feat: new feature"

    # Check queue
    sequential_queue.sh --queue-status

    # Start processing
    sequential_queue.sh --queue-start

LOG FILES:
    Default location: ./logs (in project root)
    Can be changed with: --log-dir PATH or LOG_DIR environment variable
    Execution logs: logs/sequential_queue_*.log
    Memory logs: logs/memory_monitor_*.log
    Run logs: logs/queue_run_*.log

LOCK FILES:
    Lock directory: PROJECT_ROOT/.sequential-locks/seq-exec-PROJECT_HASH/
    Queue file: PROJECT_ROOT/.sequential-locks/seq-exec-PROJECT_HASH/queue.txt
    Pause file: PROJECT_ROOT/.sequential-locks/seq-exec-PROJECT_HASH/paused
    Running file: PROJECT_ROOT/.sequential-locks/seq-exec-PROJECT_HASH/running

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

    # Get current git branch if in git repo
    local current_branch=""
    if [[ -d "$PROJECT_ROOT/.git" ]]; then
        current_branch=$(git -C "$PROJECT_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
    fi
    
    # Store run metadata
    cat > "${run_meta_dir}/metadata.txt" << EOF
RUN_ID=$run_id
START_TIME=$run_start
PID=$$
STATUS=running
PROJECT=$PROJECT_ROOT
BRANCH=$current_branch
WORKFLOW=sequential_queue
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
        local start_epoch=$(date -j -f "%Y-%m-%d %H:%M:%S" "$run_start" "+%s" 2>/dev/null || date -d "$run_start" "+%s")
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
        local start_epoch=$(date -j -f "%Y-%m-%d %H:%M:%S" "$run_start" "+%s" 2>/dev/null || date -d "$run_start" "+%s")
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
list_runs() {
    local limit="${1:-20}"
    local status_filter="${2:-}"
    local branch_filter="${3:-}"
    local workflow_filter="${4:-}"
    local json_output="${5:-false}"
    local json_fields="${6:-}"
    local template="${7:-}"
    local all_workflows="${8:-false}"
    
    # Determine current branch if in git repo
    local current_branch=""
    if [[ -d "$PROJECT_ROOT/.git" ]]; then
        current_branch=$(git -C "$PROJECT_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
    fi
    
    # Get runs sorted by date (newest first)
    local runs=()
    if [[ -d "$RUNS_DIR" ]]; then
        for run_dir in $(ls -1t "$RUNS_DIR" 2>/dev/null); do
            if [[ -f "${RUNS_DIR}/${run_dir}/metadata.txt" ]]; then
                runs+=("$run_dir")
            fi
        done
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
        # Load run metadata
        local RUN_ID="" START_TIME="" PID="" STATUS="" PROJECT="" END_TIME="" DURATION="" EXIT_CODE="" BRANCH="" WORKFLOW=""
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
            esac
        done < "$meta_file"
        
        # Apply filters
        if [[ -n "$status_filter" ]] && [[ "$STATUS" != "$status_filter" ]]; then
            continue
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
        
        # Count jobs
        local job_count=0
        if [[ -d "${RUNS_DIR}/${run}/jobs" ]]; then
            job_count=$(ls -1 "${RUNS_DIR}/${run}/jobs" 2>/dev/null | wc -l | tr -d ' ')
        fi
        
        if [[ "$json_output" == "true" ]]; then
            [[ "$first_item" == "false" ]] && json_array+=","
            first_item=false
            
            json_array+="{\"runId\":\"$RUN_ID\","
            json_array+="\"status\":\"$STATUS\","
            json_array+="\"startTime\":\"$START_TIME\","
            json_array+="\"branch\":\"$BRANCH\","
            json_array+="\"workflow\":\"${WORKFLOW:-sequential_queue}\","
            json_array+="\"jobs\":$job_count,"
            json_array+="\"duration\":\"${DURATION:-}\","
            json_array+="\"exitCode\":${EXIT_CODE:-0}}"
        else
            # Terminal output
            local status_icon=""
            local status_color=""
            case $STATUS in
                running) status_icon="⚡"; status_color="$YELLOW" ;;
                completed)
                    if [[ "${EXIT_CODE:-0}" -eq 0 ]]; then
                        status_icon="✓"; status_color="$GREEN"
                    else
                        status_icon="✗"; status_color="$RED"
                    fi
                    ;;
                stopped) status_icon="⊘"; status_color="$YELLOW" ;;
                *) status_icon="?"; status_color="$NC" ;;
            esac
            
            printf "${status_color}%s${NC} %-20s %-10s %s" "$status_icon" "$RUN_ID" "$STATUS" "$START_TIME"
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
        echo "$json_array"
    fi
}

# Watch run progress (similar to gh run watch)
watch_run() {
    local run_id="$1"
    local interval="${2:-3}"
    local exit_status="${3:-false}"
    local compact="${4:-false}"
    
    # If no run_id specified, get the latest running run
    if [[ -z "$run_id" ]]; then
        if [[ -d "$RUNS_DIR" ]]; then
            for run_dir in $(ls -1t "$RUNS_DIR" 2>/dev/null); do
                if [[ -f "${RUNS_DIR}/${run_dir}/metadata.txt" ]]; then
                    local test_status=$(grep "^STATUS=" "${RUNS_DIR}/${run_dir}/metadata.txt" | cut -d= -f2)
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
        
        # Load run metadata
        local RUN_ID="" START_TIME="" PID="" STATUS="" PROJECT="" END_TIME="" DURATION="" EXIT_CODE="" BRANCH="" WORKFLOW=""
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
            esac
        done < "$meta_file"
        
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
            for job_file in $(ls -1t "${RUNS_DIR}/${run_id}/jobs" 2>/dev/null); do
                local job_meta="${RUNS_DIR}/${run_id}/jobs/${job_file}"
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
                
                # Job status icon
                local job_icon=""
                local job_color=""
                case $JOB_STATUS in
                    running) job_icon="⚡"; job_color="$YELLOW" ;;
                    completed)
                        if [[ "${JOB_EXIT:-0}" -eq 0 ]]; then
                            job_icon="✓"; job_color="$GREEN"
                        else
                            job_icon="✗"; job_color="$RED"
                        fi
                        ;;
                    *) job_icon="?"; job_color="$NC" ;;
                esac
                
                printf "${job_color}%s${NC} %-20s %s\n" "$job_icon" "$JOB_ID" "$JOB_COMMAND"
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
view_runs() {
    local run_id="$1"
    local job_id="$2"
    local show_log="$3"
    local show_failed="$4"
    local verbose="$5"

    # If no run_id specified, show recent runs interactively
    if [[ -z "$run_id" ]] && [[ -z "$job_id" ]]; then
        echo "Recent Queue Runs:"
        echo "====================="
        echo ""

        # List recent runs
        local runs=()
        if [[ -d "$RUNS_DIR" ]]; then
            # Get runs sorted by date (newest first)
            for run_dir in $(ls -1t "$RUNS_DIR" 2>/dev/null | head -20); do
                if [[ -f "${RUNS_DIR}/${run_dir}/metadata.txt" ]]; then
                    runs+=("$run_dir")
                fi
            done
        fi

        if [[ ${#runs[@]} -eq 0 ]]; then
            echo "No runs found."
            return 0
        fi

        # Display runs
        local i=1
        for run in "${runs[@]}"; do
            local meta_file="${RUNS_DIR}/${run}/metadata.txt"
            # Load run metadata
            local RUN_ID="" START_TIME="" PID="" STATUS="" PROJECT="" END_TIME="" DURATION="" EXIT_CODE=""
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
                esac
            done < "$meta_file"

            local status_color=""
            case $STATUS in
                running) status_color="$GREEN" ;;
                completed)
                    if [[ "${EXIT_CODE:-0}" -eq 0 ]]; then
                        status_color="$GREEN"
                    else
                        status_color="$RED"
                    fi
                    ;;
                stopped) status_color="$YELLOW" ;;
                *) status_color="$NC" ;;
            esac

            printf "%2d. %s ${status_color}%-10s${NC} %s" "$i" "$RUN_ID" "$STATUS" "$START_TIME"
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
        view_run "$run_id" "$show_log" "$show_failed" "$verbose"
        return $?
    fi
}

# View a specific run/run
view_run() {
    local run_id="$1"
    local show_log="$2"
    local show_failed="$3"
    local verbose="$4"

    local meta_file="${RUNS_DIR}/${run_id}/metadata.txt"
    if [[ ! -f "$meta_file" ]]; then
        echo "Error: Run $run_id not found."
        return 1
    fi

    # Load run metadata
    local RUN_ID="" START_TIME="" PID="" STATUS="" PROJECT="" END_TIME="" DURATION="" EXIT_CODE=""
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
        esac
    done < "$meta_file"

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
    echo ""

    # List jobs
    echo "Jobs:"
    echo "-----"
    local job_count=0
    local failed_jobs=()

    if [[ -d "${RUNS_DIR}/${run_id}/jobs" ]]; then
        for job_file in $(ls -1t "${RUNS_DIR}/${run_id}/jobs/"*.txt 2>/dev/null); do
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
        done
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
            run_log=$(ls -1 "${LOGS_DIR}/queue_run_${run_id}_"*.log 2>/dev/null | head -1 || echo "")
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
}

# View a specific job
view_job() {
    local job_id="$1"
    local show_log="$2"
    local verbose="$3"

    # Find job in any run
    local job_meta_file=""
    for run_dir in $(ls -1 "$RUNS_DIR" 2>/dev/null); do
        local test_file="${RUNS_DIR}/${run_dir}/jobs/${job_id}.txt"
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
            echo "Job log file not found: ${job_meta[LOG_FILE]}"
        fi
    fi
}

# Parse command line options
CUSTOM_LOG_DIR=""
ATOMIFY="${ATOMIFY:-1}"  # Enable atomification by default
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
LIST_LIMIT=20
LIST_STATUS=""
LIST_BRANCH=""
LIST_WORKFLOW=""
LIST_JSON=false
LIST_JSON_FIELDS=""
LIST_TEMPLATE=""
LIST_ALL_WORKFLOWS=false
WATCH_RUN_ID=""
WATCH_INTERVAL=3
WATCH_EXIT_STATUS=false
WATCH_COMPACT=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --help|-h)
            show_help
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
        --list)
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
                        LIST_STATUS="$2"
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
                    -a|--all)
                        LIST_ALL_WORKFLOWS=true
                        shift
                        ;;
                    *)
                        break
                        ;;
                esac
            done
            ;;
        --watch)
            QUEUE_COMMAND="watch"
            shift
            # Check for run ID (if next arg doesn't start with --)
            if [[ $# -gt 0 ]] && [[ ! "$1" =~ ^-- ]]; then
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
        --view)
            QUEUE_COMMAND="view"
            shift
            # Check for run ID (if next arg doesn't start with --)
            if [[ $# -gt 0 ]] && [[ ! "$1" =~ ^-- ]]; then
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
                    --verbose)
                        VIEW_VERBOSE=true
                        shift
                        ;;
                    *)
                        break
                        ;;
                esac
            done
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

# Verify minimum bash version
if [ "${BASH_VERSION%%.*}" -lt 3 ] || { [ "${BASH_VERSION%%.*}" -eq 3 ] && [ "${BASH_VERSION#*.}" -lt 2 ]; }; then
    echo "ERROR: This script requires bash 3.2 or higher" >&2
    echo "Current version: $BASH_VERSION" >&2
    exit 1
fi

# Global configuration
PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
PROJECT_HASH=$(echo "$PROJECT_ROOT" | shasum | cut -d' ' -f1 | head -c 8)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Lock and state files
LOCK_BASE_DIR="${SEQUENTIAL_LOCK_BASE_DIR:-${PROJECT_ROOT}/.sequential-locks}"
LOCK_DIR="${LOCK_BASE_DIR}/seq-exec-${PROJECT_HASH}"
LOCKFILE="${LOCK_DIR}/executor.lock"
QUEUE_FILE="${LOCK_DIR}/queue.txt"
CURRENT_PID_FILE="${LOCK_DIR}/current.pid"
PIPELINE_TIMEOUT_FILE="${LOCK_DIR}/pipeline_timeout.txt"
PAUSE_FILE="${LOCK_DIR}/paused"
RUNNING_FILE="${LOCK_DIR}/running"
CLOSED_FILE="${LOCK_DIR}/closed"
RUN_START_FILE="${LOCK_DIR}/run_start"
RUNS_DIR="${LOCK_DIR}/runs"
CURRENT_RUN_FILE="${LOCK_DIR}/current_run"

# Ensure lock directory exists
mkdir -p "$LOCK_DIR"
mkdir -p "$RUNS_DIR"

# Source .env.development if it exists
if [ -f "${PROJECT_ROOT}/.env.development" ]; then
    set -a  # Export all variables
    source "${PROJECT_ROOT}/.env.development"
    set +a
fi

# Pipeline timeout (applies to entire chain)
PIPELINE_TIMEOUT="${PARSED_PIPELINE_TIMEOUT:-${PIPELINE_TIMEOUT:-86400}}"  # 24 hours default
MEMORY_LIMIT_MB="${PARSED_MEMORY_LIMIT:-${MEMORY_LIMIT_MB:-2048}}"
TIMEOUT="${PARSED_TIMEOUT:-${TIMEOUT:-86400}}"  # 24 hours default
VERBOSE="${PARSED_VERBOSE:-${VERBOSE:-0}}"

# Create logs directory
if [[ -n "$CUSTOM_LOG_DIR" ]]; then
    LOGS_DIR="$CUSTOM_LOG_DIR"
else
    LOGS_DIR="${LOG_DIR:-${PROJECT_ROOT}/logs}"
fi
mkdir -p "$LOGS_DIR"
EXEC_LOG="${LOGS_DIR}/sequential_queue_$(date '+%Y%m%d_%H%M%S')_$$.log"

# Defer handling queue management commands until functions are defined

# Check for help or no arguments (but not if we have a queue command)
if [[ $# -eq 0 ]] && [[ -z "$QUEUE_COMMAND" ]]; then
    show_help
fi

# Get the command and its arguments
COMMAND="${1:-}"
shift || true
ARGS=("$@")

# Source .env.development if it exists
if [ -f "${PROJECT_ROOT}/.env.development" ]; then
    set -a  # Export all variables
    source "${PROJECT_ROOT}/.env.development"
    set +a
fi

# Pipeline timeout (applies to entire chain)
PIPELINE_TIMEOUT="${PARSED_PIPELINE_TIMEOUT:-${PIPELINE_TIMEOUT:-86400}}"  # 24 hours default
MEMORY_LIMIT_MB="${PARSED_MEMORY_LIMIT:-${MEMORY_LIMIT_MB:-2048}}"
TIMEOUT="${PARSED_TIMEOUT:-${TIMEOUT:-86400}}"  # 24 hours default
VERBOSE="${PARSED_VERBOSE:-${VERBOSE:-0}}"

# Create logs directory
if [[ -n "$CUSTOM_LOG_DIR" ]]; then
    LOGS_DIR="$CUSTOM_LOG_DIR"
else
    LOGS_DIR="${LOG_DIR:-${PROJECT_ROOT}/logs}"
fi
mkdir -p "$LOGS_DIR"
EXEC_LOG="${LOGS_DIR}/sequential_queue_$(date '+%Y%m%d_%H%M%S')_$$.log"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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

# Get all descendant PIDs
get_descendants() {
    local pid=$1
    local children
    children=$(pgrep -P "$pid" 2>/dev/null || true)
    for child in $children; do
        echo "$child"
        get_descendants "$child"
    done
}

# Kill entire process tree
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

# Git-specific safety checks
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

# Make-specific handling
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

    # Parse command string into array
    eval "cmd_array=($cmd_string)"

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
    if [ -x "${SCRIPT_DIR}/memory_monitor.sh" ]; then
        log INFO "Starting memory monitor"
        "${SCRIPT_DIR}/memory_monitor.sh" --pid $$ --limit "$MEMORY_LIMIT_MB" &
        monitor_pid=$!
    fi

    # Ensure wait_all.sh is available
    if [ ! -x "${SCRIPT_DIR}/wait_all.sh" ]; then
        log ERROR "wait_all.sh not found at: ${SCRIPT_DIR}/wait_all.sh"
        log ERROR "This script requires wait_all.sh for atomic execution"
        return 1
    fi

    # Execute through wait_all.sh with job ID
    JOB_ID="$job_id" "${SCRIPT_DIR}/wait_all.sh" --timeout "$TIMEOUT" -- "$command" "${args[@]}"
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

                # Link to wait_all log if it exists
                local wait_all_log="${LOGS_DIR}/wait_all_${job_id}.log"
                if [[ -f "$wait_all_log" ]]; then
                    echo "LOG_FILE=$wait_all_log" >> "$job_meta_file"
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
        list) list_runs "$LIST_LIMIT" "$LIST_STATUS" "$LIST_BRANCH" "$LIST_WORKFLOW" "$LIST_JSON" "$LIST_JSON_FIELDS" "$LIST_TEMPLATE" "$LIST_ALL_WORKFLOWS" ;;
        view) view_runs "$VIEW_RUN_ID" "$VIEW_JOB_ID" "$VIEW_LOG" "$VIEW_LOG_FAILED" "$VIEW_VERBOSE" ;;
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

    # STEP 1: Check if command can be atomified
    if [[ $ATOMIFY -eq 1 ]]; then
        # Source atomifier if available
        ATOMIFIER_SCRIPT="${SCRIPT_DIR}/tool_atomifier.sh"
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
                echo "[SEQ-QUEUE] Use 'sequential_queue.sh --queue-start' to begin processing"
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
    echo "[SEQ-QUEUE] Use 'sequential_queue.sh --queue-start' to begin processing"
fi


