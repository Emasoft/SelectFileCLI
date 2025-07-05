# Deadlock Prevention Guide

## Overview

This guide documents the deadlock issues discovered in the sequential execution pipeline and the comprehensive fixes implemented to prevent them.

## Root Causes of Deadlocks

### 1. Mixed Execution Patterns
The original pre-commit configuration had hooks with different execution patterns:
- Some used direct `uv run` commands
- Others used `./scripts/safe-run.sh`

This created a scenario where:
- Pre-commit spawns multiple hooks
- Direct hooks bypass sequential control
- Sequential hooks wait for locks
- Circular dependencies form

### 2. Indefinite Lock Waiting
The original sequential executor waited forever for locks with no timeout, making deadlocks permanent.

### 3. No Deadlock Detection
The system had no way to detect circular dependencies between waiting processes.

### 4. Nested Execution Issues
The nested execution detection only worked within the same process, not across different processes in the execution tree.

## Implemented Solutions

### 1. Sequential Executor V2 (`sequential-executor-v2.sh`)

Key improvements:
- **Lock acquisition timeout**: Default 5 minutes (configurable via `MAX_LOCK_WAIT`)
- **Deadlock detection**: Tracks dependencies and detects circular waits
- **Automatic resolution**: Fails requests involved in deadlocks with exit code 125
- **Better logging**: Comprehensive logs with dependency tracking
- **Lock timeout**: Maximum time to hold a lock (30 minutes default)

### 2. Pre-commit Safe Wrapper (`pre-commit-safe.sh`)

This wrapper:
- Detects if running inside pre-commit
- Bypasses sequential execution for hooks to prevent double-locking
- Sets `PRE_COMMIT_RUNNING` environment variable

### 3. Enhanced Git Safe Wrapper

Updated `git-safe.sh` to:
- Detect when running inside git hooks
- Set `PRE_COMMIT_RUNNING` for child processes
- Skip sequential execution when appropriate

### 4. Consistent Pre-commit Configuration

All pre-commit hooks now use `pre-commit-safe.sh` wrapper for consistent behavior.

## How Deadlock Detection Works

1. **Dependency Tracking**: When process A waits for lock held by process B, this is recorded in `dependencies.txt`

2. **Periodic Checks**: Every 10 seconds, waiting processes check for circular dependencies

3. **Detection Algorithm**:
   ```
   check_deadlock(start_pid, current_pid):
       waiting_for = get_who_current_pid_waits_for()
       if waiting_for == start_pid:
           DEADLOCK DETECTED
       else:
           check_deadlock(start_pid, waiting_for)
   ```

4. **Resolution**: The process that detects the deadlock exits with code 125

## Environment Variables

### Deadlock Prevention
- `SEQUENTIAL_EXECUTOR_PID`: Set by sequential executor to detect nested calls
- `PRE_COMMIT_RUNNING`: Set when inside pre-commit execution
- `GIT_DIR` / `GIT_WORK_TREE`: Set by git when inside hooks

### Timeouts
- `MAX_LOCK_WAIT`: Maximum time to wait for lock (default: 300s)
- `LOCK_TIMEOUT`: Maximum time to hold lock (default: 1800s)

## Testing the Fixes

### Test 1: Simple Sequential Execution
```bash
./scripts/seq echo "Test 1" & ./scripts/seq echo "Test 2" &
# Should execute sequentially without deadlock
```

### Test 2: Pre-commit Execution
```bash
echo "test" > test.py && git add test.py && git commit -m "test"
# Should complete without hanging
```

### Test 3: Deadlock Simulation
```bash
# This would create a deadlock in the old system but now fails gracefully
MAX_LOCK_WAIT=10 ./scripts/seq bash -c 'sleep 60' &
sleep 2
MAX_LOCK_WAIT=10 ./scripts/seq bash -c 'echo "Should timeout"'
```

## Monitoring and Debugging

### Check for Deadlocks
```bash
# View dependency graph
cat /tmp/seq-exec-*/dependencies.txt

# Check logs for deadlock detection
grep "DEADLOCK" logs/sequential_executor_v2_*.log
```

### Monitor Queue
```bash
./scripts/monitor-queue.sh
```

### Emergency Cleanup
```bash
./scripts/kill-orphans.sh
rm -rf /tmp/seq-exec-*
```

## Best Practices

1. **Always use wrappers**: Never call `uv run` directly in pre-commit hooks
2. **Set appropriate timeouts**: Configure `MAX_LOCK_WAIT` based on expected execution time
3. **Monitor logs**: Check logs regularly for timeout and deadlock warnings
4. **Clean up regularly**: Run `kill-orphans.sh` if you suspect stuck processes

## Migration Guide

To migrate from the old system:

1. Replace `sequential-executor.sh` with the v2 version (already done via symlink)
2. Update all pre-commit hooks to use `pre-commit-safe.sh`
3. Set timeout environment variables in `.env.development`:
   ```bash
   export MAX_LOCK_WAIT=300      # 5 minutes
   export LOCK_TIMEOUT=1800      # 30 minutes
   ```

## Exit Codes

- **0**: Success
- **124**: Lock acquisition timeout
- **125**: Deadlock detected
- **Other**: Command-specific exit codes
