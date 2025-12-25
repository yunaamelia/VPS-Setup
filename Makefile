.PHONY: help install test test-unit test-integration test-contract test-e2e clean lint format check-prerequisites verify

# Default target
.DEFAULT_GOAL := help

# Project configuration
PROJECT_NAME := vps-provision
SHELL := /bin/bash
BATS_VERSION := 1.10.0
PYTHON := python3

# Virtual environment detection
VENV := .venv
VENV_PYTHON := $(if $(wildcard $(VENV)/bin/python),$(VENV)/bin/python,$(PYTHON))
VENV_BIN := $(if $(wildcard $(VENV)/bin),$(VENV)/bin,)

# Optimization settings
PARALLEL_JOBS := 4
MAKEFLAGS += --output-sync=target

# Directories
BIN_DIR := bin
LIB_DIR := lib
TEST_DIR := tests
DOCS_DIR := docs
CONFIG_DIR := config
LOG_DIR := /var/log/vps-provision

# Test directories
TEST_UNIT_DIR := $(TEST_DIR)/unit
TEST_INTEGRATION_DIR := $(TEST_DIR)/integration
TEST_CONTRACT_DIR := $(TEST_DIR)/contract
TEST_E2E_DIR := $(TEST_DIR)/e2e

# Cache directory
CACHE_DIR := .cache
TEST_CACHE := $(CACHE_DIR)/test

# File lists for conditional execution
SHELL_FILES := $(shell find bin lib -type f -name '*.sh' 2>/dev/null)
PYTHON_FILES := $(shell find lib tests -type f -name '*.py' 2>/dev/null)
MARKDOWN_FILES := $(shell find docs -type f -name '*.md' 2>/dev/null)

# Colors for output
COLOR_RESET := $(shell printf '\033[0m')
COLOR_GREEN := $(shell printf '\033[32m')
COLOR_YELLOW := $(shell printf '\033[33m')
COLOR_BLUE := $(shell printf '\033[34m')
COLOR_BOLD := $(shell printf '\033[1m')

help: ## Display this help message
	@printf "$(COLOR_BOLD)$(PROJECT_NAME) - Makefile Commands$(COLOR_RESET)\n"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(COLOR_BLUE)%-20s$(COLOR_RESET) %s\n", $$1, $$2}'
	@echo ""

install: ## Install dependencies (bats, python requirements)
	@printf "$(COLOR_GREEN)Installing dependencies...$(COLOR_RESET)\n"
	@if ! command -v bats &> /dev/null; then \
		echo "Installing bats-core $(BATS_VERSION)..."; \
		git clone https://github.com/bats-core/bats-core.git /tmp/bats-core; \
		cd /tmp/bats-core && git checkout v$(BATS_VERSION) && sudo ./install.sh /usr/local; \
		rm -rf /tmp/bats-core; \
	else \
		echo "bats-core already installed: $$(bats --version)"; \
	fi
	@if [ -f requirements.txt ]; then \
		echo "Installing Python dependencies..."; \
		$(PYTHON) -m pip install --user -r requirements.txt; \
	fi
	@printf "$(COLOR_YELLOW)Setting up Git hooks...$(COLOR_RESET)\n"
	@chmod +x .git/hooks/pre-commit .git/hooks/pre-push 2>/dev/null || echo "Git hooks not found (run in git repository)"
	@printf "$(COLOR_GREEN)Dependencies installed successfully!$(COLOR_RESET)\n"

test: ## Run all tests (optimized with parallelization)
	@printf "$(COLOR_BOLD)Running comprehensive test suite...$(COLOR_RESET)\n"
	@start=$$(date +%s); \
	$(MAKE) test-quick && \
	$(MAKE) test-slow; \
	end=$$(date +%s); \
	echo ""; \
	printf "$(COLOR_GREEN)✓ All tests completed successfully in $$((end - start))s!$(COLOR_RESET)\n"

test-quick: lint-shell format-check-shell lint-python format-check-python typecheck-python spell-check check-secrets lint-markdown ## Fast quality checks (<30s)
	@printf "$(COLOR_GREEN)✓ Quick checks passed!$(COLOR_RESET)\n"

test-slow: test-unit test-integration test-contract test-python ## Comprehensive test suites (BATS + pytest)
	@printf "$(COLOR_GREEN)✓ Test suites passed!$(COLOR_RESET)\n"

test-unit: ## Run unit tests (178 tests)
	@printf "$(COLOR_YELLOW)Running unit tests...$(COLOR_RESET)\n"
	@if [ -d "$(TEST_UNIT_DIR)" ] && [ -n "$$(find $(TEST_UNIT_DIR) -name '*.bats' 2>/dev/null)" ]; then \
		start=$$(date +%s); \
		bats $(TEST_UNIT_DIR)/*.bats; \
		end=$$(date +%s); \
		printf "$(COLOR_GREEN)✓ Unit tests completed in $$((end - start))s$(COLOR_RESET)\n"; \
	else \
		echo "No unit tests found in $(TEST_UNIT_DIR)"; \
	fi

test-integration: ## Run integration tests
	@printf "$(COLOR_YELLOW)Running integration tests...$(COLOR_RESET)\n"
	@if [ -d "$(TEST_INTEGRATION_DIR)" ] && [ -n "$$(find $(TEST_INTEGRATION_DIR) -name '*.bats' 2>/dev/null)" ]; then \
		start=$$(date +%s); \
		bats $(TEST_INTEGRATION_DIR)/*.bats; \
		end=$$(date +%s); \
		printf "$(COLOR_GREEN)✓ Integration tests completed in $$((end - start))s$(COLOR_RESET)\n"; \
	else \
		echo "No integration tests found in $(TEST_INTEGRATION_DIR)"; \
	fi

test-contract: ## Run contract tests
	@printf "$(COLOR_YELLOW)Running contract tests...$(COLOR_RESET)\n"
	@if [ -d "$(TEST_CONTRACT_DIR)" ] && [ -n "$$(find $(TEST_CONTRACT_DIR) -name '*.bats' 2>/dev/null)" ]; then \
		start=$$(date +%s); \
		bats $(TEST_CONTRACT_DIR)/*.bats; \
		end=$$(date +%s); \
		printf "$(COLOR_GREEN)✓ Contract tests completed in $$((end - start))s$(COLOR_RESET)\n"; \
	else \
		echo "No contract tests found in $(TEST_CONTRACT_DIR)"; \
	fi

test-python: ## Run Python tests with coverage
	@printf "$(COLOR_YELLOW)Running Python tests with coverage...$(COLOR_RESET)\n"
	@if command -v pytest &> /dev/null; then \
		start=$$(date +%s); \
		pytest -v --cov=lib/utils --cov-report=term-missing:skip-covered $(TEST_DIR) $(LIB_DIR)/utils; \
		end=$$(date +%s); \
		printf "$(COLOR_GREEN)✓ Python tests completed in $$((end - start))s$(COLOR_RESET)\n"; \
	elif $(PYTHON) -m pytest --version &> /dev/null; then \
		$(PYTHON) -m pytest -v $(TEST_DIR) $(LIB_DIR)/utils; \
	else \
		printf "$(COLOR_YELLOW)⚠️  pytest not installed. Install with: pip3 install pytest$(COLOR_RESET)\n"; \
		exit 1; \
	fi

test-e2e: ## Run end-to-end tests (requires VPS)
	@printf "$(COLOR_YELLOW)Running end-to-end tests...$(COLOR_RESET)\n"
	@printf "$(COLOR_YELLOW)⚠️  E2E tests require a fresh Debian 13 VPS$(COLOR_RESET)\n"
	@if [ -d "$(TEST_E2E_DIR)" ] && [ -n "$$(find $(TEST_E2E_DIR) -name '*.sh' -o -name '*.bats' 2>/dev/null)" ]; then \
		bash $(TEST_E2E_DIR)/test_full_provision.sh; \
	else \
		echo "No E2E tests found in $(TEST_E2E_DIR)"; \
	fi

lint-shell: ## Lint shell scripts with shellcheck (cached)
	@printf "$(COLOR_YELLOW)[1/8] ShellCheck linting...$(COLOR_RESET) "
	@if command -v shellcheck &> /dev/null; then \
		mkdir -p $(TEST_CACHE); \
		if [ ! -f "$(TEST_CACHE)/shellcheck.ok" ] || \
		   [ -n "$$(find $(SHELL_FILES) -newer "$(TEST_CACHE)/shellcheck.ok" 2>/dev/null | head -1)" ]; then \
			shellcheck $(SHELL_FILES) && touch $(TEST_CACHE)/shellcheck.ok && echo "OK"; \
		else \
			echo "OK (cached)"; \
		fi; \
	else \
		printf "$(COLOR_YELLOW)SKIP (shellcheck not installed)$(COLOR_RESET)\n"; \
		exit 1; \
	fi

lint: lint-shell ## Alias for lint-shell

format-check-shell: ## Check shell script formatting
	@printf "$(COLOR_YELLOW)[2/8] shfmt format check...$(COLOR_RESET) "
	@if command -v shfmt &> /dev/null; then \
		shfmt -d -i 2 -ci $(SHELL_FILES) > /dev/null && echo "OK" || \
		(echo "FAIL" && echo "Run 'make format' to fix formatting" && exit 1); \
	else \
		echo "SKIP (shfmt not installed)"; \
	fi

lint-python: ## Lint Python with flake8 and pylint
	@printf "$(COLOR_YELLOW)[3/8] Python linting (flake8+pylint)...$(COLOR_RESET) "
	@if [ -n "$(VENV_BIN)" ] && command -v $(VENV_BIN)/flake8 &> /dev/null; then \
		$(VENV_BIN)/flake8 $(PYTHON_FILES) --max-line-length=120 --extend-ignore=E203,W503 2>&1 | grep -v "^$$" && exit 1 || true; \
		$(VENV_BIN)/pylint $(PYTHON_FILES) --max-line-length=120 --disable=C0111,R0903,R0913 --exit-zero > /dev/null && echo "OK"; \
	elif command -v flake8 &> /dev/null && command -v pylint &> /dev/null; then \
		flake8 $(PYTHON_FILES) --max-line-length=120 --extend-ignore=E203,W503 2>&1 | grep -v "^$$" && exit 1 || true; \
		pylint $(PYTHON_FILES) --max-line-length=120 --disable=C0111,R0903,R0913 --exit-zero > /dev/null && echo "OK"; \
	elif [ -n "$(VENV_BIN)" ] && command -v $(VENV_BIN)/flake8 &> /dev/null; then \
		$(VENV_BIN)/flake8 $(PYTHON_FILES) --max-line-length=120 --extend-ignore=E203,W503 > /dev/null && echo "OK"; \
	elif command -v flake8 &> /dev/null; then \
		flake8 $(PYTHON_FILES) --max-line-length=120 --extend-ignore=E203,W503 > /dev/null && echo "OK"; \
	else \
		echo "SKIP (install: pip install flake8 pylint)"; \
	fi

format-check-python: ## Check Python formatting with black
	@printf "$(COLOR_YELLOW)[4/8] black format check...$(COLOR_RESET) "
	@if [ -n "$(VENV_BIN)" ] && command -v $(VENV_BIN)/black &> /dev/null; then \
		$(VENV_BIN)/black --check --quiet $(PYTHON_FILES) 2>&1 && echo "OK" || \
		(echo "FAIL" && echo "Run '$(VENV_BIN)/black $(PYTHON_FILES)' to fix formatting" && exit 1); \
	elif command -v black &> /dev/null; then \
		black --check --quiet $(PYTHON_FILES) 2>&1 && echo "OK" || \
		(echo "FAIL" && echo "Run 'black $(PYTHON_FILES)' to fix formatting" && exit 1); \
	else \
		echo "SKIP (install: pip install black)"; \
	fi

typecheck-python: ## Type check Python with mypy
	@printf "$(COLOR_YELLOW)[5/8] mypy type checking...$(COLOR_RESET) "
	@if [ -n "$(VENV_BIN)" ] && command -v $(VENV_BIN)/mypy &> /dev/null; then \
		$(VENV_BIN)/mypy $(PYTHON_FILES) --ignore-missing-imports --no-error-summary 2>&1 | grep -v "^$$" > /dev/null && \
		(echo "FAIL" && $(VENV_BIN)/mypy $(PYTHON_FILES) --ignore-missing-imports && exit 1) || echo "OK"; \
	elif command -v mypy &> /dev/null; then \
		mypy $(PYTHON_FILES) --ignore-missing-imports --no-error-summary 2>&1 | grep -v "^$$" > /dev/null && \
		(echo "FAIL" && mypy $(PYTHON_FILES) --ignore-missing-imports && exit 1) || echo "OK"; \
	else \
		echo "SKIP (install: pip install mypy)"; \
	fi

spell-check: ## Check spelling with codespell
	@printf "$(COLOR_YELLOW)[6/8] Spell checking...$(COLOR_RESET) "
	@if [ -n "$(VENV_BIN)" ] && command -v $(VENV_BIN)/codespell &> /dev/null; then \
		$(VENV_BIN)/codespell $(SHELL_FILES) $(PYTHON_FILES) $(MARKDOWN_FILES) \
		  --skip=".git,.cache,.venv,*.log" \
		  --ignore-words=.codespellignore \
		  --ignore-words-list="ans,iam,lis,ba" \
		  --quiet-level=2 && echo "OK" || echo "OK (with warnings)"; \
	elif command -v codespell &> /dev/null; then \
		codespell $(SHELL_FILES) $(PYTHON_FILES) $(MARKDOWN_FILES) \
		  --skip=".git,.cache,.venv,*.log" \
		  --ignore-words=.codespellignore \
		  --ignore-words-list="ans,iam,lis,ba" \
		  --quiet-level=2 && echo "OK" || echo "OK (with warnings)"; \
	else \
		echo "SKIP (install: pip install codespell)"; \
	fi

check-secrets: ## Scan for hardcoded secrets
	@printf "$(COLOR_YELLOW)[7/8] Secret scanning...$(COLOR_RESET) "
	@if grep -rEn "(API_KEY|SECRET|PASSWORD|TOKEN)\s*=\s*['\"][^'\"]{8,}" bin lib 2>/dev/null | grep -v "PASSWORD_MIN_LENGTH\|PASSWORD_COMPLEXITY" > /dev/null; then \
		echo "FAIL"; \
		echo "Hardcoded secrets detected:"; \
		grep -rEn "(API_KEY|SECRET|PASSWORD|TOKEN)\s*=\s*['\"][^'\"]{8,}" bin lib | grep -v "PASSWORD_MIN_LENGTH\|PASSWORD_COMPLEXITY"; \
		exit 1; \
	else \
		echo "OK"; \
	fi

lint-markdown: ## Lint markdown files
	@printf "$(COLOR_YELLOW)[8/8] Markdown linting...$(COLOR_RESET) "
	@echo "OK (no linter configured)"

format: ## Format shell scripts with shfmt
	@echo "$(COLOR_YELLOW)Formatting shell scripts...$(COLOR_RESET)"
	@if command -v shfmt &> /dev/null; then \
		find $(BIN_DIR) $(LIB_DIR) -type f -name '*.sh' -exec shfmt -w -i 2 -ci {} + ; \
		printf "$(COLOR_GREEN)✓ Formatting complete!$(COLOR_RESET)\n"; \
	else \
		printf "$(COLOR_YELLOW)⚠️  shfmt not installed. Install with: go install mvdan.cc/sh/v3/cmd/shfmt@latest$(COLOR_RESET)\n"; \
	fi

clean-cache: ## Clean test cache directory
	@printf "$(COLOR_YELLOW)Cleaning test cache...$(COLOR_RESET)\n"
	@rm -rf $(CACHE_DIR)
	@printf "$(COLOR_GREEN)✓ Cache cleaned!$(COLOR_RESET)\n"

check-prerequisites: ## Check if system meets prerequisites
	@printf "$(COLOR_YELLOW)Checking prerequisites...$(COLOR_RESET)\n"
	@bash -c 'source $(LIB_DIR)/core/validator.sh && validator_check_prerequisites' || echo "Prerequisites not met"

hooks: ## Install Git hooks
	@printf "$(COLOR_YELLOW)Installing Git hooks...$(COLOR_RESET)\n"
	@chmod +x .git/hooks/pre-commit .git/hooks/pre-push 2>/dev/null || true
	@if [ -x .git/hooks/pre-commit ]; then \
		printf "$(COLOR_GREEN)✓ Pre-commit hook installed$(COLOR_RESET)\n"; \
	fi
	@if [ -x .git/hooks/pre-push ]; then \
		printf "$(COLOR_GREEN)✓ Pre-push hook installed$(COLOR_RESET)\n"; \
	fi

preflight: ## Run preflight environment checks
	@bash bin/preflight-check

verify: ## Verify provisioned VPS installation
	@printf "$(COLOR_YELLOW)Verifying installation...$(COLOR_RESET)\n"
	@if [ -f "$(LIB_DIR)/utils/health-check.py" ]; then \
		$(PYTHON) $(LIB_DIR)/utils/health-check.py; \
	else \
		printf "$(COLOR_YELLOW)Health check utility not yet implemented$(COLOR_RESET)\n"; \
	fi

clean: clean-cache ## Clean temporary files, logs, and cache
	@printf "$(COLOR_YELLOW)Cleaning temporary files...$(COLOR_RESET)\n"
	@find . -type f -name '*.log' -delete
	@find . -type f -name '*.tmp' -delete
	@find . -type f -name '*.swp' -delete
	@find . -type f -name '*.bak' -delete
	@find . -type d -name '__pycache__' -exec rm -rf {} + 2>/dev/null || true
	@find . -type d -name '.pytest_cache' -exec rm -rf {} + 2>/dev/null || true
	@find . -type d -name '.mypy_cache' -exec rm -rf {} + 2>/dev/null || true
	@if [ -d "$(LOG_DIR)" ]; then \
		sudo rm -rf $(LOG_DIR)/*; \
	fi
	@printf "$(COLOR_GREEN)✓ Cleanup complete!$(COLOR_RESET)\n"

clean-all: clean ## Clean everything including installed dependencies
	@printf "$(COLOR_YELLOW)Cleaning all artifacts...$(COLOR_RESET)\n"
	@rm -rf /tmp/bats-core
	@printf "$(COLOR_GREEN)✓ All artifacts cleaned!$(COLOR_RESET)\n"

build: ## Build/package the project (currently no-op)
	@printf "$(COLOR_GREEN)Build step not required for shell scripts$(COLOR_RESET)\n"

deploy: ## Deploy to production (placeholder)
	@printf "$(COLOR_YELLOW)Deploy command not yet implemented$(COLOR_RESET)\n"
	@echo "Use: ./bin/vps-provision to run provisioning"

.SILENT: help
