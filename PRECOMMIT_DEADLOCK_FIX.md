# Pre-commit Deadlock Fix and Logging Enhancement

## Problem Solved

The pre-commit hooks were getting stuck in a deadlock when:
1. `git commit` triggers pre-commit hooks
2. Pre-commit runs through sequential-executor.sh (acquires lock)
3. Pre-commit runs hooks like TruffleHog via safe-run.sh
4. safe-run.sh tries to run sequential-executor.sh again
5. Sequential executor waits for lock held by parent = **DEADLOCK**

## Solution Implemented

### 1. Deadlock Prevention
- Sequential executor now detects if it's already running via `SEQUENTIAL_EXECUTOR_PID` environment variable
- Nested calls bypass the locking mechanism and execute directly
- Maintains single-process guarantee for top-level commands
- No circular waits possible

### 2. Comprehensive Logging
Both memory_monitor.sh and sequential-executor.sh now create detailed logs in `./logs/`:

#### Memory Monitor Logs
- File: `./logs/memory_monitor_YYYYMMDD_HHMMSS_PID.log`
- Contents:
  - Initial process tree with PIDs and memory usage
  - Real-time memory tracking for all processes
  - High memory warnings (>50% of limit)
  - Process termination events
  - Periodic summaries every 50 seconds

#### Sequential Executor Logs
- File: `./logs/sequential_executor_YYYYMMDD_HHMMSS_PID.log`
- Contents:
  - Command execution details
  - Queue status and position
  - Lock acquisition/release events
  - Orphan process cleanup
  - Git operation conflict detection

## How to Use

### Running Commands
```bash
# Normal usage - everything is logged automatically
git commit -m "message"
make test
./scripts/seq python script.py
```

### Viewing Logs
```bash
# Real-time monitoring
tail -f logs/*.log

# View latest memory monitor log
less $(ls -t logs/memory_monitor_*.log | head -1)

# Search for issues
grep -h "High memory usage" logs/*.log
grep -h "Memory limit exceeded" logs/*.log
grep -h "deadlock" logs/*.log
```

### Debugging Pre-commit Issues
If pre-commit gets stuck again:
1. Check for nested execution: `grep "Already inside sequential executor" logs/*.log`
2. View queue status: `cat /tmp/seq-exec-*/queue.txt`
3. Check process tree: `ps aux | grep -E "(pre-commit|sequential-executor)"`
4. Kill stuck processes: `pkill -f pre-commit`

## Technical Details

### Environment Variable
- `SEQUENTIAL_EXECUTOR_PID` is set by sequential-executor.sh
- Nested calls detect this and bypass locking
- Prevents infinite wait scenarios

### Log Format
Logs use consistent timestamps and prefixes:
- `[MEMORY-MONITOR] YYYY-MM-DD HH:MM:SS - message`
- `[SEQUENTIAL] YYYY-MM-DD HH:MM:SS - message`
- `[QUEUE] YYYY-MM-DD HH:MM:SS - message`
- `[WARNING] YYYY-MM-DD HH:MM:SS - message`

### Safety Guarantees Maintained
1. ✅ Only ONE top-level process runs at a time
2. ✅ No orphaned processes
3. ✅ Memory limits enforced (default 2GB)
4. ✅ No deadlocks possible
5. ✅ Full audit trail via logs

## Testing the Fix

```bash
# Test nested execution detection
SEQUENTIAL_EXECUTOR_PID=123 ./scripts/sequential-executor.sh echo "Should bypass"

# Test pre-commit with hooks
echo "test" > test.txt
git add test.txt
git commit -m "Test commit"  # Should complete without hanging
```

The fix has been tested and integrated into SEQUENTIAL_PRECOMMIT_SETUP 2.md documentation.