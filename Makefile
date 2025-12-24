.PHONY: help install test test-unit test-integration test-contract test-e2e clean lint format check-prerequisites verify

# Default target
.DEFAULT_GOAL := help

# Project configuration
PROJECT_NAME := vps-provision
SHELL := /bin/bash
BATS_VERSION := 1.10.0
PYTHON := python3

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

test: test-unit test-integration test-contract ## Run all tests
	@echo ""
	@printf "$(COLOR_GREEN)✓ All tests passed!$(COLOR_RESET)\n"

test-unit: ## Run unit tests
	@printf "$(COLOR_YELLOW)Running unit tests...$(COLOR_RESET)\n"
	@if [ -d "$(TEST_UNIT_DIR)" ] && [ -n "$$(find $(TEST_UNIT_DIR) -name '*.bats' 2>/dev/null)" ]; then \
		bats $(TEST_UNIT_DIR)/*.bats; \
	else \
		echo "No unit tests found in $(TEST_UNIT_DIR)"; \
	fi

test-integration: ## Run integration tests
	@printf "$(COLOR_YELLOW)Running integration tests...$(COLOR_RESET)\n"
	@if [ -d "$(TEST_INTEGRATION_DIR)" ] && [ -n "$$(find $(TEST_INTEGRATION_DIR) -name '*.bats' 2>/dev/null)" ]; then \
		bats $(TEST_INTEGRATION_DIR)/*.bats; \
	else \
		echo "No integration tests found in $(TEST_INTEGRATION_DIR)"; \
	fi

test-contract: ## Run contract tests
	@printf "$(COLOR_YELLOW)Running contract tests...$(COLOR_RESET)\n"
	@if [ -d "$(TEST_CONTRACT_DIR)" ] && [ -n "$$(find $(TEST_CONTRACT_DIR) -name '*.bats' 2>/dev/null)" ]; then \
		bats $(TEST_CONTRACT_DIR)/*.bats; \
	else \
		echo "No contract tests found in $(TEST_CONTRACT_DIR)"; \
	fi

test-e2e: ## Run end-to-end tests (requires VPS)
	@printf "$(COLOR_YELLOW)Running end-to-end tests...$(COLOR_RESET)\n"
	@printf "$(COLOR_YELLOW)⚠️  E2E tests require a fresh Debian 13 VPS$(COLOR_RESET)\n"
	@if [ -d "$(TEST_E2E_DIR)" ] && [ -n "$$(find $(TEST_E2E_DIR) -name '*.sh' -o -name '*.bats' 2>/dev/null)" ]; then \
		bash $(TEST_E2E_DIR)/test_full_provision.sh; \
	else \
		echo "No E2E tests found in $(TEST_E2E_DIR)"; \
	fi

lint: ## Lint shell scripts with shellcheck
	@printf "$(COLOR_YELLOW)Linting shell scripts...$(COLOR_RESET)\n"
	@if command -v shellcheck &> /dev/null; then \
		find $(BIN_DIR) $(LIB_DIR) -type f -name '*.sh' -exec shellcheck {} + ; \
		printf "$(COLOR_GREEN)✓ Linting passed!$(COLOR_RESET)\n"; \
	else \
		printf "$(COLOR_YELLOW)⚠️  shellcheck not installed. Install with: sudo apt-get install shellcheck$(COLOR_RESET)\n"; \
	fi

format: ## Format shell scripts with shfmt
	@echo "$(COLOR_YELLOW)Formatting shell scripts...$(COLOR_RESET)"
	@if command -v shfmt &> /dev/null; then \
		find $(BIN_DIR) $(LIB_DIR) -type f -name '*.sh' -exec shfmt -w -i 2 -ci {} + ; \
		printf "$(COLOR_GREEN)✓ Formatting complete!$(COLOR_RESET)\n"; \
	else \
		printf "$(COLOR_YELLOW)⚠️  shfmt not installed. Install with: go install mvdan.cc/sh/v3/cmd/shfmt@latest$(COLOR_RESET)\n"; \
	fi

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

clean: ## Clean temporary files and logs
	@printf "$(COLOR_YELLOW)Cleaning temporary files...$(COLOR_RESET)\n"
	@find . -type f -name '*.log' -delete
	@find . -type f -name '*.tmp' -delete
	@find . -type f -name '*.swp' -delete
	@find . -type f -name '*.bak' -delete
	@find . -type d -name '__pycache__' -exec rm -rf {} + 2>/dev/null || true
	@find . -type d -name '.pytest_cache' -exec rm -rf {} + 2>/dev/null || true
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
