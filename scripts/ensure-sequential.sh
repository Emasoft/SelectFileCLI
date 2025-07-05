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

# 2. Check wait_all.sh exists and is executable
WAIT_ALL="$PROJECT_ROOT/scripts/wait_all.sh"
if [ -f "$WAIT_ALL" ]; then
    chmod +x "$WAIT_ALL"
    echo -e "${GREEN}✓ wait_all.sh properly configured${NC}"
else
    echo -e "${RED}ERROR: wait_all.sh not found${NC}"
    exit 1
fi

# 3. Install/Update ALL git hooks with safety checks
HOOKS_DIR="$PROJECT_ROOT/.git/hooks"
if [ -d "$HOOKS_DIR" ]; then
    echo -e "${YELLOW}Installing/updating git hooks with safety checks...${NC}"

    # Function to create hook with standard header
    create_hook() {
        local hook_name=$1
        local hook_path="$HOOKS_DIR/$hook_name"

        # Backup existing hook if it exists and isn't ours
        if [ -f "$hook_path" ] && ! grep -q "Sequential execution safety" "$hook_path" 2>/dev/null; then
            echo -e "${YELLOW}Backing up existing $hook_name hook to ${hook_name}.backup${NC}"
            mv "$hook_path" "${hook_path}.backup"
        fi

        # Copy our enhanced hooks
        case "$hook_name" in
            pre-commit)
                if [ -f "$PROJECT_ROOT/.git/hooks/pre-commit" ] && grep -q "wait_all.sh" "$hook_path" 2>/dev/null; then
                    echo -e "${GREEN}✓ pre-commit hook already updated${NC}"
                else
                    echo -e "${YELLOW}Creating pre-commit hook...${NC}"
                    cat > "$hook_path" << 'EOF'
#!/usr/bin/env bash
# Sequential execution safety hook
PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
# Sequential executor will use wait_all.sh internally for atomic operations
"$PROJECT_ROOT/scripts/sequential-executor.sh" pre-commit "$@"
EOF
                fi
                ;;
            pre-push)
                echo -e "${YELLOW}Creating pre-push hook...${NC}"
                cat > "$hook_path" << 'EOF'
#!/usr/bin/env bash
# Sequential execution safety hook
PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
WAIT_ALL="$PROJECT_ROOT/scripts/wait_all.sh"

echo "[PRE-PUSH] Checking for concurrent git operations..."
"$WAIT_ALL" -- bash -c '
pgrep -f "git (push|pull|fetch)" | grep -v $$ && {
    echo "ERROR: Other git network operations detected!" >&2
    exit 1
}
exit 0
'
EOF
                ;;
            commit-msg)
                echo -e "${YELLOW}Creating commit-msg hook...${NC}"
                cat > "$hook_path" << 'EOF'
#!/usr/bin/env bash
# Sequential execution safety hook
PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
WAIT_ALL="$PROJECT_ROOT/scripts/wait_all.sh"

# Verify no other git operations are running using wait_all.sh
"$WAIT_ALL" -- bash -c '
pgrep -f "git (commit|merge|rebase)" | grep -v $$ >/dev/null && {
    echo "ERROR: Other git operations in progress!" >&2
    exit 1
}
exit 0
'

# Pass through to commitizen or conventional commits if available
if command -v cz >/dev/null 2>&1; then
    "$WAIT_ALL" -- cz check --commit-msg-file "$1"
fi
exit 0
EOF
                ;;
        esac

        chmod +x "$hook_path"
    }

    # Install all safety hooks
    for hook in pre-commit pre-push commit-msg; do
        create_hook "$hook"
    done

    echo -e "${GREEN}✓ Git hooks updated with safety checks${NC}"
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
echo "2. Atomic executor: $WAIT_ALL"
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
