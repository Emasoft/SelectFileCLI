# Makefile for Safe Sequential Execution
# Enforces safe execution patterns to prevent resource exhaustion

.PHONY: help test lint format check clean install dev-setup monitor kill-all safe-commit git-add git-commit git-push git-status git-pull

# Default shell
SHELL := /bin/bash

# Colors
GREEN := \033[0;32m
YELLOW := \033[1;33m
RED := \033[0;31m
NC := \033[0m # No Color

# Atomic execution wrapper - ensures complete process cleanup
WAIT_ALL := ./scripts/wait_all.sh
# Make sequential wrapper - prevents concurrent make commands
MAKE_SEQ := ./scripts/make-sequential.sh

help: ## Show this help message
	@echo -e "$(GREEN)Safe Sequential Execution Commands$(NC)"
	@echo -e "$(YELLOW)Always use these commands instead of running tools directly!$(NC)"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "$(GREEN)%-20s$(NC) %s\n", $$1, $$2}'

check-env: ## Check system resources
	@echo -e "$(GREEN)Checking system resources...$(NC)"
	@if [ -f .env.development ]; then \
		source .env.development; \
	fi
	@echo "Memory free: $$(free -h 2>/dev/null | grep Mem | awk '{print $$4}' || echo 'N/A')"
	@echo "Load average: $$(uptime | awk -F'load average:' '{print $$2}')"
	@echo "Python processes: $$(pgrep -c python 2>/dev/null || echo 0)"
	@echo "Git processes: $$(pgrep -c git 2>/dev/null || echo 0)"

dev-setup: ## Set up development environment
	@echo -e "$(GREEN)Setting up development environment...$(NC)"
	@if [ ! -f .env.development ]; then \
		echo -e "$(RED)Creating .env.development file...$(NC)"; \
	fi
	@source .env.development 2>/dev/null || true
	@uv venv
	@source .venv/bin/activate && uv sync --all-extras
	@chmod +x scripts/*.sh
	@./scripts/ensure-sequential.sh
	@echo -e "$(GREEN)Development environment ready!$(NC)"
	@echo -e "$(YELLOW)Remember to: source .env.development$(NC)"

install: ## Install dependencies safely
	@echo -e "$(GREEN)Installing dependencies...$(NC)"
	@$(WAIT_ALL) -- uv sync --all-extras

test: check-env ## Run tests safely (sequential)
	@echo -e "$(GREEN)Running tests sequentially...$(NC)"
	@source .env.development 2>/dev/null || true
	@$(WAIT_ALL) -- uv run pytest -v

test-fast: check-env ## Run fast tests only
	@echo -e "$(GREEN)Running fast tests...$(NC)"
	@source .env.development 2>/dev/null || true
	@$(WAIT_ALL) -- uv run pytest -v -m "not slow"

test-file: check-env ## Run specific test file (usage: make test-file FILE=tests/test_foo.py)
	@if [ -z "$(FILE)" ]; then \
		echo -e "$(RED)ERROR: Specify FILE=tests/test_something.py$(NC)"; \
		exit 1; \
	fi
	@echo -e "$(GREEN)Running test: $(FILE)$(NC)"
	@source .env.development 2>/dev/null || true
	@$(WAIT_ALL) -- uv run pytest -v $(FILE)

lint: check-env ## Run linters safely
	@echo -e "$(GREEN)Running linters...$(NC)"
	@source .env.development 2>/dev/null || true
	@$(WAIT_ALL) -- uv run ruff check src tests
	@$(WAIT_ALL) -- uv run mypy src --strict

format: check-env ## Format code safely
	@echo -e "$(GREEN)Formatting code...$(NC)"
	@source .env.development 2>/dev/null || true
	@$(WAIT_ALL) -- uv run ruff format src tests
	@$(WAIT_ALL) -- uv run ruff check --fix src tests

check: lint test ## Run all checks

clean: ## Clean temporary files
	@echo -e "$(GREEN)Cleaning temporary files...$(NC)"
	@find . -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
	@find . -type f -name "*.pyc" -delete 2>/dev/null || true
	@find . -type f -name "*.pyo" -delete 2>/dev/null || true
	@find . -type f -name ".coverage" -delete 2>/dev/null || true
	@rm -rf .pytest_cache 2>/dev/null || true
	@rm -rf .mypy_cache 2>/dev/null || true
	@rm -rf .ruff_cache 2>/dev/null || true
	@rm -rf htmlcov 2>/dev/null || true
	@rm -f /tmp/seq-exec-*/executor.lock 2>/dev/null || true
	@echo -e "$(GREEN)Cleanup complete!$(NC)"

kill-all: ## Emergency: Kill all Python/test processes
	@echo -e "$(RED)EMERGENCY: Killing all Python processes...$(NC)"
	@pkill -f pytest || true
	@pkill -f python || true
	@pkill -f pre-commit || true
	@killall -9 python python3 2>/dev/null || true
	@rm -rf /tmp/seq-exec-*/executor.lock 2>/dev/null || true
	@rm -rf /tmp/seq-exec-*/current.pid 2>/dev/null || true
	@rm -rf /tmp/seq-exec-*/queue.txt 2>/dev/null || true
	@echo -e "$(GREEN)All processes killed$(NC)"

monitor: ## Start sequential execution queue monitor
	@echo -e "$(GREEN)Starting queue monitor...$(NC)"
	@./scripts/monitor-queue.sh

safe-commit: check-env ## Safely commit changes using git-safe wrapper
	@echo -e "$(GREEN)Checking for running git operations...$(NC)"
	@# Check for any git processes
	@if pgrep -f "git (commit|merge|rebase|cherry-pick|push|pull)" > /dev/null; then \
		echo -e "$(RED)ERROR: Git operations already in progress!$(NC)"; \
		ps aux | grep -E "git (commit|merge|rebase|cherry-pick|push|pull)" | grep -v grep; \
		exit 1; \
	fi
	@# Check for git index lock
	@if [ -f .git/index.lock ]; then \
		echo -e "$(RED)ERROR: Git index is locked!$(NC)"; \
		echo -e "$(YELLOW)Remove with: rm -f .git/index.lock$(NC)"; \
		exit 1; \
	fi
	@echo -e "$(GREEN)Safe to proceed with commit$(NC)"
	@echo -e "$(YELLOW)Usage:$(NC)"
	@echo -e "  make git-add              # Stage all changes"
	@echo -e "  make git-commit MSG=\"...\" # Commit with message"
	@echo -e "  make git-push             # Push to remote"

git-add: ## Safely stage all changes
	@echo -e "$(GREEN)Staging all changes...$(NC)"
	@./scripts/git-safe.sh add -A

git-commit: ## Safely commit with message (usage: make git-commit MSG="your message")
	@if [ -z "$(MSG)" ]; then \
		echo -e "$(RED)ERROR: Specify commit message with MSG=\"your message\"$(NC)"; \
		exit 1; \
	fi
	@echo -e "$(GREEN)Committing with message: $(MSG)$(NC)"
	@./scripts/git-safe.sh commit -m "$(MSG)"

git-push: ## Safely push to remote
	@echo -e "$(GREEN)Pushing to remote...$(NC)"
	@./scripts/git-safe.sh push

git-status: ## Check git status safely
	@./scripts/git-safe.sh status

git-pull: ## Safely pull from remote
	@echo -e "$(GREEN)Pulling from remote...$(NC)"
	@./scripts/git-safe.sh pull

# Hidden targets for CI
.ci-test:
	@$(WAIT_ALL) -- uv run pytest --cov=src --cov-report=xml

.ci-lint:
	@$(WAIT_ALL) -- uv run ruff check src tests --format=github
	@$(WAIT_ALL) -- uv run mypy src --no-error-summary
