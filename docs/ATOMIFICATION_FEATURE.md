# Atomification Feature for Sequential Queue

## Overview

The atomification feature automatically breaks down batch commands into atomic operations, processing one file at a time. This ensures true sequential execution and prevents resource exhaustion from processing multiple files simultaneously.

## Requirements

### Core Requirement
Instead of commands like:
```bash
sequential_queue.sh -- ruff check ./tests
```

The sequential_queue.sh script should automatically break this down into atomic elements:
```bash
sequential_queue.sh -- ruff check ./tests/test_file1.py
sequential_queue.sh -- ruff check ./tests/test_file2.py
# ... one command per file
```

### Key Implementation Details

1. **Automatic Expansion**: The script must:
   - Read the path/pattern from the command
   - Filter files based on the tool's expected file types (e.g., .py for Python tools)
   - Generate separate commands for each file
   - Handle recursive directory scanning

2. **Path Resolution**: Must resolve:
   - `~` to home directory
   - Environment variables like `$HOME`
   - Glob patterns like `*.py` or `src/**/*.py`

3. **Tool Awareness**: The script must know:
   - File extensions each tool processes
   - Argument syntax for each tool
   - Position of file arguments (beginning, after subcommand, or end)

4. **Full Sequential Queue Logic**: Each atomic command must go through:
   - Git safety checks
   - Make command preparation  
   - Queue management
   - Lock acquisition
   - Memory monitoring
   - Timeout handling
   - Special tool-specific handling

## Supported Tools

The atomifier must support these tools with their specific syntaxes:

### Python Tools
- **ruff** (check/format): `*.py *.pyi`
- **mypy**: `*.py *.pyi`
- **pytest**, **pytest-cov**, **pytest-watcher**, **pytest-asyncio**: `*.py`
- **pytest-sugar**, **pytest-mock**, **hypothesis**: `*.py`
- **coverage**: `*.py`
- **docformatter**, **nbqa**, **isort**, **pyupgrade**: `*.py`

### JavaScript/TypeScript Tools
- **eslint**, **prettier**, **pnpm**: `*.js *.jsx *.ts *.tsx *.mjs *.cjs`

### YAML Tools
- **yamllint**, **yamlfmt**: `*.yml *.yaml`

### JSON Tools
- **jq**, **jsonlint**: `*.json`

### Other Tools
- **shellcheck**: `*.sh *.bash`
- **actionlint**: `*.yml *.yaml` (GitHub Actions)
- **sqlfluff**: `*.sql`
- **mkdocs**: `*.md *.markdown`
- **trufflehog**, **pre-commit**, **bfg**: All files

### Special Cases

#### UV Commands
- `uv run <tool> <args> <files>` - files come after the tool
- `uv tool run <tool> <args> <files>` - files come after the tool

#### GitHub CLI (gh)
- `gh repo`, `gh pr`, `gh issue`, `gh release` - files after subcommand

#### Pre-commit
- `pre-commit run --files <files>` - files after --files flag

## Implementation Architecture

### 1. Tool Configuration (`tool_atomifier.sh`)
Contains:
- `get_tool_extensions()` - Returns file patterns for each tool
- `supports_multiple_files()` - Whether tool can handle multiple files
- `get_file_arg_position()` - Where file arguments appear
- `parse_command()` - Extracts tool and subcommand info
- `find_file_args()` - Locates file arguments in command
- `expand_path()` - Expands directories and globs to individual files
- `generate_atomic_commands()` - Creates atomic commands

### 2. Sequential Queue Integration (`sequential_queue.sh`)
- Sources `tool_atomifier.sh` when atomification is enabled
- Generates atomic commands before processing
- Executes each atomic command with full queue logic
- Preserves all safety checks and special handling

### 3. Command Flow
1. User runs: `sequential_queue.sh -- ruff check src/`
2. Script detects atomification is needed
3. Generates atomic commands for each .py file in src/
4. Each atomic command goes through full sequential processing:
   - Waits in queue
   - Acquires lock
   - Runs with all safety checks
   - Releases lock
5. Process continues until all files are processed

## Testing

### Basic Tests
```bash
# Python tool
./scripts/tool_atomifier.sh ruff check src/
# Should output individual commands for each .py file

# JavaScript tool  
./scripts/tool_atomifier.sh eslint src/
# Should output individual commands for each .js/.ts file

# YAML tool with glob
./scripts/tool_atomifier.sh yamllint .github/workflows/*.yml
# Should expand glob and create individual commands
```

### Integration Tests
```bash
# Test with sequential queue
./scripts/sequential_queue.sh -- ruff check src/
# Should process each file individually

# Test with --no-atomify flag
./scripts/sequential_queue.sh --no-atomify -- ruff check src/
# Should process as single batch command
```

## Configuration Options

### Environment Variables
- `ATOMIFY=0` - Disable atomification globally

### Command Line Flags
- `--no-atomify` - Disable atomification for this command

## Edge Cases Handled

1. **No Files Found**: If expansion produces no files, runs original command
2. **Single File**: If only one file found, still uses atomic execution
3. **Mixed Arguments**: Preserves all non-file arguments in correct positions
4. **Special Characters**: Handles spaces in filenames, special shell characters
5. **Nested Directories**: Recursively scans subdirectories
6. **Hidden Files**: Excludes files in hidden directories (starting with .)

## Known Limitations

1. Tools not in the supported list default to generic handling
2. Complex command structures may not parse correctly
3. Some tools may have undocumented argument positions

## Future Enhancements

1. Add more tools to the supported list
2. Support for custom file patterns via configuration
3. Parallel execution option (with controlled concurrency)
4. Progress reporting for large file sets
5. Dry-run mode to preview atomic commands

## Debugging

Enable debug mode to see atomification details:
```bash
DEBUG=1 ./scripts/tool_atomifier.sh ruff check src/
```

Enable verbose mode for sequential queue:
```bash
./scripts/sequential_queue.sh --verbose -- ruff check src/
```

## Files Created

1. `/scripts/tool_atomifier.sh` - Core atomification logic
2. `/scripts/sequential_queue_v4.sh` - Updated queue with atomification support
3. `/docs/ATOMIFICATION_FEATURE.md` - This documentation

## Migration Path

1. Test tool_atomifier.sh with various commands
2. Test sequential_queue_v4.sh with atomification
3. Replace sequential_queue.sh with v4 when stable
4. Update all workflows to use simplified commands

## Current Status

- ✅ Tool configuration complete (tool_atomifier.sh)
- ✅ Path expansion working (handles directories, globs, ~, env vars)
- ✅ Atomic command generation working (40+ tools supported)
- ✅ Sequential queue v5 created with correct recursive architecture
- ✅ Each atomic command goes through full sequential processing
- ✅ Integration testing successful
- ⏳ Workflow updates pending

## Version History

- **v4**: Initial attempt with incorrect internal execution
- **v5**: Correct implementation with recursive calls to sequential_queue.sh

## Test Results

### Successful Tests Performed

1. **Basic Python atomification**:
   ```bash
   ./scripts/sequential_queue_v5.sh -- ruff check /tmp/test_atomify/
   # Successfully atomified into 2 commands, each processed individually
   ```

2. **Tool-specific file filtering**:
   - Python tools only process .py files
   - YAML tools only process .yml/.yaml files
   - JavaScript tools only process .js/.ts files

3. **Full sequential processing preserved**:
   - Each atomic command acquires lock
   - Memory monitoring active
   - Pipeline timeout enforced
   - Git/Make special handling preserved

4. **Edge cases handled**:
   - Single file: Still uses atomic execution
   - No files found: Runs original command
   - Mixed file types: Filters by tool requirements