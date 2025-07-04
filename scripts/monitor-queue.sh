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
