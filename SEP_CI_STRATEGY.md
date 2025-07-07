# SEP CI Strategy - Sequential Execution in GitHub Actions

## The Problem
SEP (Sequential Execution Pipeline) is designed to prevent process explosions and memory issues by executing commands sequentially. However, the initial CI implementation had workflows that:
1. Queued commands with `sep_queue.sh` but never executed them with `--queue-start`
2. Didn't properly install SEP environment in CI

## The Solution

### Option 1: Batch Script Approach (Recommended)
Create a single script containing all commands, then execute it through SEP:

```yaml
- name: Run all checks sequentially
  run: |
    # Create batch script
    cat > run_all.sh << 'EOF'
    #!/usr/bin/env bash
    set -euo pipefail

    echo "=== Command 1 ==="
    command1

    echo "=== Command 2 ==="
    command2
    EOF

    chmod +x run_all.sh

    # Execute through SEP
    ./scripts/sep_queue.sh --timeout 7200 -- ./run_all.sh
    ./scripts/sep_queue.sh --queue-start
```

**Pros:**
- Single SEP invocation
- Clear sequential execution
- Easy to debug (script can be run manually)
- Proper error handling with `set -euo pipefail`

### Option 2: Queue and Execute Approach
Queue multiple commands then execute all at once:

```yaml
- name: Queue commands
  run: |
    ./scripts/sep_queue.sh -- command1
    ./scripts/sep_queue.sh -- command2
    ./scripts/sep_queue.sh -- command3

- name: Execute queue
  run: |
    ./scripts/sep_queue.sh --queue-start
```

**Pros:**
- More granular control
- Can add commands dynamically

**Cons:**
- Multiple SEP invocations
- Less clear what's being executed

### Option 3: Direct SEP Invocation (For Simple Cases)
For single commands or when SEP's atomification isn't needed:

```yaml
- name: Run single command
  run: |
    ./scripts/sep.sh -- uv run pytest
```

## SEP Setup in CI

All workflows need SEP environment setup:

```yaml
- name: Setup SEP for CI
  run: |
    # Create directories
    mkdir -p logs .sequential-locks
    touch .sep.log.lock

    # Create configuration
    cat > .env.development << 'EOF'
    MEMORY_LIMIT_MB=2048
    CHECK_INTERVAL=5
    TIMEOUT=1800
    PIPELINE_TIMEOUT=7200
    VERBOSE=1
    SEQUENTIAL_LOCK_BASE_DIR="./.sequential-locks"
    WAIT_ALL_LOG_LOCK="./.sep.log.lock"
    PYTEST_MAX_WORKERS=1
    CI=true
    GITHUB_ACTIONS=true
    EOF

    # Make executable
    chmod +x scripts/sep*.sh
```

## Benefits of Using SEP in CI

1. **Memory Protection**: Prevents OOM kills in resource-limited CI runners
2. **Sequential Execution**: Ensures commands don't compete for resources
3. **Consistent Behavior**: Same execution model locally and in CI
4. **Better Debugging**: Verbose output shows exactly what's running
5. **Automatic Atomification**: Complex commands are broken down automatically

## Implementation Guidelines

1. **Always Setup SEP First**: Include SEP setup step in every workflow
2. **Use Batch Scripts**: For multiple related commands, create a batch script
3. **Set Appropriate Timeouts**: CI may be slower than local
4. **Enable Verbose Mode**: Set `VERBOSE=1` for better debugging
5. **Check Exit Codes**: SEP preserves command exit codes

## Example: Complete Lint Workflow

```yaml
name: Lint
on: [push, pull_request]
jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v4
    - uses: astral-sh/setup-uv@v3
    - run: uv sync --locked

    - name: Setup SEP
      run: |
        mkdir -p logs .sequential-locks
        touch .sep.log.lock
        cat > .env.development << 'EOF'
        MEMORY_LIMIT_MB=2048
        VERBOSE=1
        CI=true
        EOF
        chmod +x scripts/sep*.sh

    - name: Run all lints sequentially
      run: |
        cat > lint_all.sh << 'EOF'
        #!/usr/bin/env bash
        set -euo pipefail

        uv run ruff check
        uv run ruff format --check
        uv run mypy
        uv run deptry
        EOF

        chmod +x lint_all.sh
        ./scripts/sep_queue.sh -- ./lint_all.sh
        ./scripts/sep_queue.sh --queue-start
```

This ensures all linting happens sequentially, preventing memory issues while maintaining the benefits of SEP.
