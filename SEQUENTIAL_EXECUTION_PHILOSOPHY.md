# Sequential Execution Philosophy

## Core Principles

### 1. True Sequential Execution
- **One process at a time** - No exceptions, no shortcuts
- **Indefinite waiting** - Processes wait forever for their turn
- **Order preservation** - Execution order is strictly maintained

### 2. No Individual Timeouts
- **No lock acquisition timeouts** - A process waits indefinitely for the lock
- **No "give up" mechanism** - Sequential means sequential, period
- **Pipeline-level timeout only** - The entire chain has a timeout, not individual steps

### 3. Atomic Operations
- **Git commits are atomic** - The entire git commit (including pre-commit hooks) is one operation
- **No nested locking** - Operations that are part of a larger operation don't get separate locks

## Implementation

### Sequential Executor Strict (`sequential-executor-strict.sh`)

The strict executor enforces these principles:

```bash
# Wait for lock - INDEFINITELY
while true; do
    if mkdir "$LOCKFILE" 2>/dev/null; then
        break  # Got lock
    fi
    # Check if holder is alive, but keep waiting regardless
    sleep 1
done
```

### Pipeline Timeout

While individual processes wait indefinitely, the entire pipeline has a timeout:

```bash
PIPELINE_TIMEOUT="${PIPELINE_TIMEOUT:-7200}"  # 2 hours default
```

If the pipeline times out:
1. ALL queued processes are killed
2. The current process is killed
3. All locks are cleaned up
4. The pipeline is considered failed

### Exit Codes

- **0**: Success
- **126**: Pipeline timeout (entire chain exceeded time limit)
- **127**: Pipeline abort (manual intervention)
- **Other**: Command-specific exit codes

## Why This Matters

### Prevents Race Conditions
By ensuring only one process runs at a time and processes wait indefinitely:
- No process can "skip ahead"
- No partial executions
- No resource conflicts

### Predictable Behavior
- You know exactly what order things will run in
- No surprises from timeout-based decisions
- Clear failure modes (pipeline timeout vs. process failure)

### Simplicity
- No complex deadlock detection needed
- No circular dependency analysis
- Just a simple queue and lock

## Common Misconceptions

### "Deadlocks are possible"
**Wrong**: In a properly designed sequential system, deadlocks can't occur because:
- Only one process runs at a time
- Processes don't hold multiple resources
- There's only one lock (the execution lock)

### "Timeouts prevent hanging"
**Wrong**: Individual timeouts can cause more problems than they solve:
- They break the sequential guarantee
- They can leave the system in an inconsistent state
- Pipeline-level timeout is the proper solution

### "Parallel is always better"
**Wrong**: For many operations (especially involving shared resources):
- Sequential execution prevents conflicts
- It's more predictable
- It's easier to debug

## Best Practices

### 1. Design for Sequential
- Don't try to parallelize within the sequential pipeline
- Keep operations atomic
- Use pipeline timeout appropriately

### 2. Handle Failures Gracefully
- If a process dies, log it as an error
- The next process can decide how to proceed
- Don't try to "fix" it automatically

### 3. Monitor the Pipeline
- Use `monitor-queue.sh` to see what's waiting
- Check logs for unexpected deaths
- Set appropriate pipeline timeouts

## Example Scenarios

### Scenario 1: Git Commit
```bash
git commit -m "message"
# This is ONE atomic operation including:
# - Pre-commit hooks
# - The actual commit
# - Post-commit hooks
```

### Scenario 2: Test Suite
```bash
./scripts/seq pytest test1.py
./scripts/seq pytest test2.py
./scripts/seq pytest test3.py
# Each runs in order, waiting indefinitely for the previous
```

### Scenario 3: Build Pipeline
```bash
PIPELINE_TIMEOUT=3600 make all
# The entire 'make all' has 1 hour to complete
# Individual steps wait indefinitely for each other
```

## Conclusion

Sequential execution is about **guarantees**, not optimization. It guarantees:
- Order of execution
- Resource exclusivity
- Predictable behavior

By following these principles, we eliminate entire classes of problems related to concurrency, at the cost of some parallelism. For many use cases, this tradeoff is worth it.