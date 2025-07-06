# Sequential Queue Design Document

## Core Architecture Principles

### 1. Queue is Eternal and Unique
- **The queue always exists** - It is a permanent fixture of each project
- **One queue per project** - Identified by PROJECT_HASH derived from project root path
- **Cannot be created or destroyed** - The queue is conceptually always present
- **Project-locked** - All queue operations are locked to the project root folder

### 2. Queue States and Operations

#### Allowed Operations:
- **Start/Stop**: Control execution
  - Start: Begin processing queued commands
  - Stop: Halt execution AND clear all pending commands
- **Pause/Resume**: Temporary execution control
  - Pause: Temporarily halt processing (queue remains intact)
  - Resume: Continue processing from where it paused
- **Clear**: Remove all entries without stopping execution
- **Open/Close**: Control whether new commands can be added
  - Close: Block new commands (for debugging)
  - Open: Accept new commands (default state)

#### Queue Characteristics:
- **Dynamic**: Commands can be added asynchronously while queue is running
- **Sequential**: Commands execute one at a time in exact order of addition
- **Atomic**: Commands are atomified when possible (e.g., batch operations on files)
- **Persistent**: Queue state persists across script invocations

### 3. Logging Requirements

#### Log Directory Configuration:
- **Default location**: `./logs` (in project root)
- **Environment variable**: Set `LOG_DIR` to change default location
- **Command line option**: Use `--log-dir PATH` to override for specific execution
- **Priority**: Command line > Environment variable > Default (./logs)

#### Real-time Logs:
- Created for EACH command execution
- Logs command start time, command string, end time, and exit code
- Stored in: `logs/sequential_queue_YYYYMMDD_HHMMSS_PID.log`

#### Session Logs:
- Created for each queue SESSION (start to stop/completion)
- Contains:
  - Session start/end times
  - Total session duration
  - All commands executed during session with their timings
  - Overall exit code
- Stored in: `logs/queue_session_YYYYMMDD_HHMMSS_PID.log`
- Special log created when queue is stopped by user

#### Memory Monitor Logs:
- Created during command execution
- Tracks memory usage of processes
- Stored in: `logs/memory_monitor_YYYYMMDD_HHMMSS_PID.log`

### 4. Lock File Management

All lock files stored in: `PROJECT_ROOT/.sequential-locks/seq-exec-PROJECT_HASH/`

- `executor.lock`: Ensures single command execution
- `queue.txt`: The actual command queue
- `current.pid`: PID of currently executing command
- `pipeline_timeout.txt`: Pipeline timeout tracking
- `paused`: Exists when queue is paused
- `running`: Contains PID of queue runner process
- `closed`: Exists when queue is closed to new commands
- `session_start`: Contains session start timestamp

### 5. Command Flow

1. User adds command: `sequential_queue.sh -- command args`
2. Command is atomified if possible (single operation per file)
3. Atomic commands added to queue.txt
4. Queue runner (if active) picks up commands sequentially
5. Each command executes through wait_all.sh
6. Memory monitoring active during execution
7. Results logged to both real-time and session logs

### 6. Special Command Handling

#### Git Commands:
- Check for concurrent git operations
- Prevent git lock conflicts
- Set GIT_COMMIT_IN_PROGRESS for commits
- Handle pre-commit hooks safely

#### Make Commands:
- Enforce sequential execution with -j1
- Prevent parallel make execution
- Handle recursive makefiles safely

### 7. Atomification

Commands are automatically broken into atomic operations:
- `ruff check src/` → Multiple `ruff check src/file.py` commands
- Single files are already atomic (not atomified further)
- Atomified commands maintain order
- Can be disabled with `--no-atomify`

## Implementation Status

### Completed Features:
- ✅ Project-specific queue with hash-based locking
- ✅ Dynamic queue that accepts commands while running
- ✅ Queue keeps running when empty (waiting for new commands)
- ✅ Start/Stop/Pause/Resume operations
- ✅ Clear queue operation
- ✅ Close/Open queue operations
- ✅ Command atomification
- ✅ Git and Make special handling
- ✅ Memory monitoring integration
- ✅ Real-time command logging
- ✅ Session logging (start to stop)
- ✅ Pipeline timeout management
- ✅ Lock file cleanup on exit

### Queue Management Commands:
- `--queue-start`: Start processing the queue
- `--queue-status`: Show current queue status
- `--queue-pause`: Pause queue execution
- `--queue-resume`: Resume queue execution
- `--queue-stop`: Stop queue and clear all pending commands
- `--clear-queue`: Clear all entries (queue keeps running)
- `--close-queue`: Close queue (stop accepting new commands)
- `--reopen-queue`: Reopen closed queue

### File Structure:
```
PROJECT_ROOT/
├── .sequential-locks/
│   └── seq-exec-PROJECT_HASH/
│       ├── executor.lock
│       ├── queue.txt
│       ├── current.pid
│       ├── pipeline_timeout.txt
│       ├── paused
│       ├── running
│       ├── closed
│       └── session_start
└── logs/
    ├── sequential_queue_*.log      # Real-time logs
    ├── queue_session_*.log         # Session logs
    └── memory_monitor_*.log        # Memory monitoring logs
```

## GitHub CLI-like View and Watch Commands

### Terminology Update (v8.0.0+):
- **Run**: A sequence from start to stop of the queue (previously "session")
- **Job**: An atomic command in the queue or any independent command executed via wait_all.sh
- Both runs and jobs have unique IDs matching their log files for easy identification

### View Command Requirements (v8.0.0):
- Implement `gh run view` functionality: https://cli.github.com/manual/gh_run_view
- Allow viewing specific runs by ID or latest runs
- Support `--log` to view full logs
- Support `--log-failed` to view only failed job logs
- Support `--verbose` to show job steps in detail
- Support `--job` to view specific job within a run

### List Command Requirements (v8.1.0):
- Implement `gh run list` functionality: https://cli.github.com/manual/gh_run_list
- Support listing recent runs with various filters
- Support `--branch` to filter by branch (if in git repo)
- Support `--limit` to control number of runs shown
- Support `--status` to filter by run status (completed, in_progress, failed, etc.)
- Support `--workflow` to filter by workflow name (map to queue operations)
- Support `--json` for JSON output
- Support `--template` for custom formatting

### Watch Command Requirements (v8.1.0):
- Implement `gh run watch` functionality: https://cli.github.com/manual/gh_run_watch
- Real-time monitoring of run progress
- Support `--exit-status` to exit with same status as run
- Support `--interval` to control refresh rate
- Support watching specific run by ID or latest run
- Display job progress with live updates
- Show job status changes in real-time

### Logging Architecture:
- **One log per job**: Each atomic command (job) executed via wait_all.sh has exactly one log file
- **One log per run**: Each queue run (from start to stop) has exactly one log file
- **Real-time updates**: Logs are updated in real-time with timestamps from start to end
- **No summary logs**: No extra files or summary logs - just one log per job and one per run
- **Universal IDs**: Each log has a unique ID matching the job/run ID for easy identification
- **View-only through sequential_queue.sh**: Only sequential_queue.sh can view logs using gh CLI syntax

### Implementation Plan:
1. Update all documentation to use run/job terminology ✓
2. Enhance metadata storage to support all required fields ✓
3. Implement list command with filtering and formatting options ✓
4. Implement watch command with real-time updates ✓
5. Add JSON output support for programmatic access ✓
6. Ensure all logs are timestamped and ordered for easy retrieval ✓

### Implementation Details:

#### List Command (--list):
- Lists recent runs with various filters
- Options implemented:
  - `-L, --limit N`: Maximum number of runs to fetch (default: 20)
  - `-s, --status STR`: Filter by status (running, completed, stopped)
  - `-b, --branch STR`: Filter by branch
  - `-w, --workflow STR`: Filter by workflow name
  - `--json [FIELDS]`: Output JSON with specified fields
  - `-t, --template STR`: Format JSON output using Go template
  - `-a, --all`: Include all workflows
- Shows run status with colored icons (⚡ running, ✓ completed, ✗ failed, ⊘ stopped)
- Displays branch, job count, and duration for each run

#### Watch Command (--watch):
- Real-time monitoring of run progress
- Options implemented:
  - `--exit-status`: Exit with same status as run
  - `-i, --interval N`: Refresh interval in seconds (default: 3)
  - `--compact`: Show only relevant/failed steps
- Automatically finds latest running run if no run ID specified
- Displays job progress with live updates
- Shows job status changes in real-time with colored icons
- Clears screen and refreshes at specified interval
- Exits when run completes (optionally with same exit code)

## Version History
- v7.0.0: Dynamic queue with session logging and configurable log directories
- v8.0.0: Added view command with GitHub CLI-like syntax, run/job terminology
- v8.1.0: Added list and watch commands with full GitHub CLI compatibility


