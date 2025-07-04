#!/usr/bin/env bash
# ensure-sequential.sh - Ensures ALL operations use sequential executor

set -euo pipefail

PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
SEQUENTIAL_EXECUTOR="$PROJECT_ROOT/scripts/sequential-executor.sh"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}=== Ensuring Sequential Execution Setup ===${NC}"

# 1. Check sequential executor exists and is executable
if [ ! -f "$SEQUENTIAL_EXECUTOR" ]; then
    echo -e "${RED}ERROR: Sequential executor not found at: $SEQUENTIAL_EXECUTOR${NC}"
    exit 1
fi

if [ ! -x "$SEQUENTIAL_EXECUTOR" ]; then
    echo -e "${YELLOW}Making sequential executor executable...${NC}"
    chmod +x "$SEQUENTIAL_EXECUTOR"
fi

# 2. Check safe-run.sh delegates to sequential executor
SAFE_RUN="$PROJECT_ROOT/scripts/safe-run.sh"
if [ -f "$SAFE_RUN" ]; then
    if ! grep -q "sequential-executor.sh" "$SAFE_RUN"; then
        echo -e "${RED}ERROR: safe-run.sh does not use sequential executor${NC}"
        exit 1
    fi
    chmod +x "$SAFE_RUN"
    echo -e "${GREEN}✓ safe-run.sh properly configured${NC}"
fi

# 3. Update ALL git hooks to use sequential execution
HOOKS_DIR="$PROJECT_ROOT/.git/hooks"
if [ -d "$HOOKS_DIR" ]; then
    # Check pre-commit hook uses wait_all.sh
    if [ -f "$HOOKS_DIR/pre-commit" ]; then
        if ! grep -q "wait_all.sh" "$HOOKS_DIR/pre-commit"; then
            echo -e "${YELLOW}Updating pre-commit hook to use wait_all.sh...${NC}"
            cat > "$HOOKS_DIR/pre-commit" << 'EOF'
#!/usr/bin/env bash
# This hook uses wait_all.sh to ensure proper process completion

# Find the wait_all.sh and sequential executor
PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
WAIT_ALL="$PROJECT_ROOT/scripts/wait_all.sh"
SEQUENTIAL_EXECUTOR="$PROJECT_ROOT/scripts/sequential-executor.sh"

if [ ! -x "$WAIT_ALL" ]; then
    echo "ERROR: wait_all.sh not found at: $WAIT_ALL" >&2
    exit 1
fi

if [ ! -x "$SEQUENTIAL_EXECUTOR" ]; then
    echo "ERROR: sequential-executor.sh not found at: $SEQUENTIAL_EXECUTOR" >&2
    exit 1
fi

# Execute pre-commit through sequential executor
"$WAIT_ALL" -- "$SEQUENTIAL_EXECUTOR" pre-commit "$@"
EOF
            chmod +x "$HOOKS_DIR/pre-commit"
        fi
    fi
fi

# 4. Create wrapper for direct commands
DIRECT_WRAPPER="$PROJECT_ROOT/scripts/seq"
if [ -f "$DIRECT_WRAPPER" ]; then
    chmod +x "$DIRECT_WRAPPER"
    echo -e "${GREEN}✓ 'seq' wrapper ready for easy sequential execution${NC}"
fi

# 5. Check Python/pytest configuration
if [ -f "$PROJECT_ROOT/pytest.ini" ]; then
    if grep -q "addopts.*-n" "$PROJECT_ROOT/pytest.ini"; then
        if ! grep -q "addopts.*-n 0" "$PROJECT_ROOT/pytest.ini"; then
            echo -e "${YELLOW}WARNING: pytest.ini may allow parallel execution${NC}"
        fi
    fi
    echo -e "${GREEN}✓ pytest.ini checked${NC}"
fi

# 6. Check environment file
if [ -f "$PROJECT_ROOT/.env.development" ]; then
    if ! grep -q "PYTEST_MAX_WORKERS=1" "$PROJECT_ROOT/.env.development"; then
        echo -e "${YELLOW}WARNING: .env.development missing PYTEST_MAX_WORKERS=1${NC}"
    fi
    echo -e "${GREEN}✓ .env.development checked${NC}"
fi

# 7. Create command intercept aliases
INTERCEPT_FILE="$PROJECT_ROOT/.sequential-aliases"
cat > "$INTERCEPT_FILE" << 'EOF'
# Sequential execution aliases - source this file to enforce sequential execution
# Usage: source .sequential-aliases

# Get the directory of this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SEQ_EXEC="$SCRIPT_DIR/scripts/sequential-executor.sh"

# Intercept common commands that can spawn multiple processes
alias pytest="$SEQ_EXEC uv run pytest"
alias python="$SEQ_EXEC python"
alias uv="$SEQ_EXEC uv"
alias git="$SEQ_EXEC git"
alias make="$SEQ_EXEC make"
alias npm="$SEQ_EXEC npm"
alias pnpm="$SEQ_EXEC pnpm"
alias yarn="$SEQ_EXEC yarn"

# Show active intercepts
echo "Sequential execution enforced for: pytest, python, uv, git, make, npm, pnpm, yarn"
echo "To run without sequential execution, use: command <cmd> or \<cmd>"
EOF

echo -e "${GREEN}✓ Created command intercept aliases${NC}"
echo -e "${YELLOW}To enforce sequential execution for ALL commands:${NC}"
echo -e "  source .sequential-aliases"

# 8. Verify no background processes are running
echo -e "\n${GREEN}Checking for background processes...${NC}"
PYTHON_PROCS=$(pgrep -c python 2>/dev/null || echo 0)
GIT_PROCS=$(pgrep -c git 2>/dev/null || echo 0)
if [ "$PYTHON_PROCS" -gt 1 ] || [ "$GIT_PROCS" -gt 1 ]; then
    echo -e "${YELLOW}WARNING: Multiple processes detected:${NC}"
    echo "  Python processes: $PYTHON_PROCS"
    echo "  Git processes: $GIT_PROCS"
    echo -e "${YELLOW}Consider running: make kill-all${NC}"
fi

# 9. Summary
echo -e "\n${GREEN}=== Sequential Execution Setup Summary ===${NC}"
echo "1. Sequential executor: $SEQUENTIAL_EXECUTOR"
echo "2. Safe wrapper: $SAFE_RUN"
echo "3. Direct wrapper: seq (use as: ./scripts/seq <command>)"
echo "4. Git hooks: Updated to use sequential execution"
echo "5. Command aliases: source .sequential-aliases"
echo ""
echo -e "${GREEN}CRITICAL RULES:${NC}"
echo "- NEVER use & for background execution"
echo "- NEVER run pytest with -n auto or -n >1"
echo "- ALWAYS use 'make' commands or './scripts/seq' wrapper"
echo "- ALWAYS wait for commands to complete"
echo ""
echo -e "${YELLOW}Monitor queue in another terminal:${NC} make monitor"
