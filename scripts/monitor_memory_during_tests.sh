#!/usr/bin/env bash
# Monitor memory usage during test execution
set -euo pipefail

LOG_FILE="${1:-memory_usage.log}"

echo "Starting memory monitoring..."
echo "Timestamp,Total_Memory_MB,Free_Memory_MB,Python_Processes,Pytest_Processes" > "$LOG_FILE"

while true; do
    # Get memory info on macOS
    TOTAL_MEM=$(sysctl -n hw.memsize | awk '{print int($1/1024/1024)}')
    FREE_MEM=$(vm_stat | grep "Pages free" | awk '{print int($2 * 4096 / 1024 / 1024)}')

    # Count Python and pytest processes
    PYTHON_COUNT=$(ps aux | grep -E "python|Python" | grep -v grep | wc -l | tr -d ' ')
    PYTEST_COUNT=$(ps aux | grep pytest | grep -v grep | wc -l | tr -d ' ')

    # Log the data
    echo "$(date '+%Y-%m-%d %H:%M:%S'),$TOTAL_MEM,$FREE_MEM,$PYTHON_COUNT,$PYTEST_COUNT" >> "$LOG_FILE"

    # Also display to console
    printf "\r[%s] Free Memory: %d MB | Python procs: %d | pytest procs: %d" \
        "$(date '+%H:%M:%S')" "$FREE_MEM" "$PYTHON_COUNT" "$PYTEST_COUNT"

    sleep 2
done
