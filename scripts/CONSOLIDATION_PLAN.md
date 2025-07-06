# Script Consolidation Plan

## Current 10 Scripts → Final 6 Scripts

### 1. **Core Execution (Keep Separate)**
- `wait_all.sh` - Atomic execution (keep as-is)
- `memory_monitor.sh` - Background memory monitoring (keep as-is)

### 2. **Merge Queue Management**
Combine into `sequential_queue.sh`:
- `sequential-executor.sh` - Queue management
- `git-safe.sh` - Git-specific safety (auto-detected)
- `make-sequential.sh` - Make-specific handling (auto-detected)

The new script auto-detects command types and applies appropriate handling.

### 3. **Merge Setup Scripts**
Combine into `install_sequential.sh`:
- `ensure-sequential.sh` - Setup verification
- `test-bash-compatibility.sh` - Compatibility testing
- `install-deps.sh` - Dependency management

The new script provides three commands:
- `install` - Complete installation and configuration
- `doctor` - Health check and verification
- `uninstall` - Clean configuration (preserves scripts)

### 4. **Keep Monitoring/Maintenance Separate**
- `monitor-queue.sh` - Real-time monitoring tool (keep separate)
- `kill-orphans.sh` - Emergency cleanup tool (keep separate)

## Benefits:
1. Reduced from 10 to 6 scripts (60% reduction)
2. Clear separation: Core (3), Setup (1), Monitoring (2)
3. Each script has a well-defined purpose
4. Single entry point for installation/setup
5. Auto-detection in queue management
6. Much easier to understand and maintain

## Final Structure:
```
scripts/
├── wait_all.sh                  # Core: Atomic execution
├── sequential_queue.sh          # Core: Universal queue (auto-detects git/make)
├── memory_monitor.sh            # Core: Memory monitoring
├── install_sequential.sh        # Setup: Install/Doctor/Uninstall
├── monitor-queue.sh             # Tool: Real-time monitoring
├── kill-orphans.sh              # Tool: Emergency cleanup
└── CONSOLIDATION_PLAN.md        # Documentation
```

## Usage Examples:
```bash
# Installation and setup
install_sequential.sh install    # Complete installation
install_sequential.sh doctor     # Health check
install_sequential.sh uninstall  # Remove configuration

# Queue management (auto-detects git/make)
sequential_queue.sh -- git commit -m "message"
sequential_queue.sh -- make test
sequential_queue.sh -- pytest
./seq -- any-command            # Convenience symlink

# Monitoring and maintenance
monitor-queue.sh                 # Watch queue in real-time
kill-orphans.sh                  # Clean up stuck processes
```

## Migration Path:
1. Run `install_sequential.sh install` to set up the sequential pipeline
2. Run `install_sequential.sh doctor` to verify the installation
3. Manually update any references to old scripts in your workflows
4. Remove old scripts when ready (they're symlinked for compatibility)
