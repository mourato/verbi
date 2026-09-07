# Makefile for Prisma - CLI-first development workflow
# =============================================================================
# This Makefile provides common development commands for the Prisma
# project. All commands use xcodebuild CLI tools for maximum compatibility
# with CI/CD pipelines and headless environments.
# =============================================================================

.PHONY: help build build-release build-agent build-test build-test-strict xcodebuild-safe test test-agent test-full test-full-agent test-smoke runtime-smoke test-critical-coverage test-perf test-sensitive test-appkit test-parity test-parity-agent test-verbose test-strict test-ci-strict scope-check scope-check-agent validate validate-lane validate-lane-command validate-agent workflow-test benchmark-summary benchmark-summary-agent lint lint-agent lint-report lint-strict lint-strict-agent lint-fix arch-check preview-check localization-check guidance-check preflight preflight-fast preflight-agent preflight-agent-fast agent-artifacts-report agent-artifacts-dry-run agent-artifacts-clean clean run run-release build-and-run dmg setup-self-signed-cert setup format health ci-build deliverable-gate docs docs-preview docs-clean profile profile-report profile-cpu profile-memory profile-animation profile-animation-report

# Default target
help:
	@echo "$(APP_PRODUCT_NAME) Development Commands"
	@echo "===================================="
	@echo ""
	@echo "Build Commands:"
	@echo "  make build          - Build debug version (default)"
	@echo "  make build-release  - Build release version"
	@echo "  make build-meeting-notes-editor - Rebuild CM6 meeting-notes web bundle (when Editor/ changed)"
	@echo "  make build-agent    - Build debug with compact machine-readable output"
	@echo "  make build-test     - Run build + tests in sequence (fast default, strict in CI)"
	@echo "  make build-test-strict - Run build + tests in strict xcode mode"
	@echo "  make xcodebuild-safe - Build via canonical direct xcodebuild wrapper"
	@echo ""
	@echo "Test Commands:"
	@echo "  make test           - Run fast local dev suite (swift test, parallel)"
	@echo "  make test-agent     - Run fast local dev suite in compact mode"
	@echo "  make test-full      - Run broad swift-test suite for preflight/local gates"
	@echo "  make test-full-agent - Run broad swift-test suite in compact mode"
	@echo "  make test-smoke     - Run curated smoke suite"
	@echo "  make test-critical-coverage - Measure source coverage for critical smoke flows"
	@echo "  make test-perf      - Run isolated performance tests"
	@echo "  make test-sensitive - Run isolated sensitive subsystem tests"
	@echo "  make test-appkit    - Run isolated AppKit lifecycle tests"
	@echo "  make test-parity    - Run xcodebuild parity tests"
	@echo "  make test-parity-agent - Run xcodebuild parity tests in compact mode"
	@echo "  make test-verbose   - Run tests with verbose output"
	@echo "  make test-strict    - Run tests with strict concurrency checking"
	@echo "  make test-ci-strict - Run strict xcodebuild parity gate"
	@echo "  make scope-check    - Run scoped validation (targeted tests + smart escalation)"
	@echo "  make scope-check-agent - Run scoped validation in compact agent mode"
	@echo "  make validate       - Run the canonical automatic validation lane"
	@echo "  make validate-lane  - Run validate through the global baseline/artifact gate"
	@echo "  make validate-agent  - Run the canonical Fast/Full/auto validation lane"
	@echo "  make workflow-test  - Run deterministic validation workflow fixtures"
	@echo "  make benchmark-summary - Run summary benchmark gate in report-only mode"
	@echo "  make benchmark-summary-agent - Run summary benchmark in compact mode"
	@echo ""
	@echo "Code Quality:"
	@echo "  make lint           - Run fail-closed linting checks (use FIX=1 to auto-fix first)"
	@echo "  make lint-agent     - Run fail-closed lint with compact machine-readable output"
	@echo "  make lint-report    - Run report-only lint for existing warnings"
	@echo "  make lint-strict    - Run lint with strict error handling"
	@echo "  make lint-strict-agent - Run strict lint with compact output"
	@echo "  make lint-fix       - Auto-fix linting issues"
	@echo "  make arch-check     - Run architecture boundary checks"
	@echo "  make preview-check  - Verify per-file SwiftUI preview declarations"
	@echo "  make localization-check - Validate locale symmetry and literal keys"
	@echo "  make guidance-check - Validate AGENTS/skills/docs links and make target references"
	@echo "  make preflight      - Run preflight script (build + test + lint + benchmark)"
	@echo "  make preflight-fast - Run fast preflight (lint + build + test)"
	@echo "  make preflight-agent - Run preflight in compact machine-readable mode"
	@echo "  make preflight-agent-fast - Run fast preflight in compact machine-readable mode"
	@echo "  make health         - Run comprehensive code health check"
	@echo ""
	@echo "Run Commands:"
	@echo "  make run            - Build and run debug version"
	@echo "  make run-release    - Build and run release version"
	@echo "  make build-and-run ARGS=... - Interactive Debug/Release build workflow"
	@echo "  make runtime-smoke  - Build isolated Debug and verify recording start"
	@echo ""
	@echo "Distribution:"
	@echo "  make dmg            - Create DMG installer (prompts for auto/keychain identity/adhoc at start)"
	@echo "  make setup-self-signed-cert - Create/import legacy self-signed cert"
	@echo "  make new-release    - Build and publish a signed GitHub release"
	@echo ""
	@echo "Performance Profiling:"
	@echo "  make profile        - Run all performance profiling (CPU, Memory, Animation)"
	@echo "  make profile-report - Run profiling + export summary metrics"
	@echo "  make profile-cpu    - Profile CPU usage with Time Profiler"
	@echo "  make profile-memory - Profile memory usage with Allocations"
	@echo "  make profile-animation - Profile Core Animation performance"
	@echo "  make profile-animation-report - Profile animation and export metrics"
	@echo ""
	@echo "Maintenance:"
	@echo "  make clean          - Clean build artifacts"
	@echo "  make agent-artifacts-report - Report generated agent/build artifact usage"
	@echo "  make agent-artifacts-dry-run - Preview safe artifact cleanup (default: 7 days)"
	@echo "  make agent-artifacts-clean - Delete eligible artifacts with explicit confirmation"
	@echo "  make setup          - Verify toolchain, install dependencies, configure Git hooks"
	@echo ""
	@echo "CI/CD Commands:"
	@echo "  make ci-build       - Full CI build (lint + test + build-release)"
	@echo "  make deliverable-gate - Run build-test + lint"
	@echo ""
	@echo "Documentation:"
	@echo "  make docs           - Build DocC documentation"
	@echo "  make docs-preview   - Preview documentation locally"
	@echo "  make docs-clean     - Clean documentation artifacts"

# Configuration
PROJECT_DIR = $(shell pwd)
IDENTITY_SCRIPT = $(PROJECT_DIR)/scripts/config/app_identity.sh
APP_SCHEME = $(shell . "$(IDENTITY_SCRIPT)"; printf "%s" "$$APP_SCHEME")
APP_PRODUCT_NAME = $(shell . "$(IDENTITY_SCRIPT)"; printf "%s" "$$APP_PRODUCT_NAME")
XCODEPROJ_NAME = $(shell . "$(IDENTITY_SCRIPT)"; printf "%s" "$$XCODEPROJ_NAME")
XCODEPROJ = $(PROJECT_DIR)/$(XCODEPROJ_NAME)
DERIVED_DATA = $(PROJECT_DIR)/.xcode-build
DIST_DIR = $(PROJECT_DIR)/dist
AGENT_LOG_DIR ?= /tmp/ma-agent
ARTIFACT_RETENTION_DAYS ?= 7
AGENT_ENV = MA_AGENT_MODE=1 MA_AGENT_LOG_DIR="$(AGENT_LOG_DIR)"
AGENT_CONFIG_HOME ?= $(HOME)/.agents
VALIDATE_LANE ?= $(AGENT_CONFIG_HOME)/scripts/validate-lane
VALIDATE_BASE ?= $(shell git merge-base origin/main HEAD 2>/dev/null || git rev-parse HEAD^)

# Colors for output
RED = \033[0;31m
GREEN = \033[0;32m
YELLOW = \033[1;33m
BLUE = \033[0;34m
NC = \033[0m

# Build Commands
build:
	@./scripts/run-build.sh --configuration Debug

build-release:
	@./scripts/run-build.sh --configuration Release

build-agent:
	@$(AGENT_ENV) ./scripts/run-build.sh --configuration Debug --agent

build-meeting-notes-editor:
	@./scripts/build-meeting-notes-editor.sh

build-test:
	@$(AGENT_ENV) ./scripts/run-build-and-test.sh

build-test-strict:
	@$(AGENT_ENV) MA_BUILD_TEST_STRICT_XCODE=1 ./scripts/run-build-and-test.sh

xcodebuild-safe:
	@./scripts/xcodebuild-safe.sh

# Test Commands
test:
	@./scripts/run-tests.sh --suite dev

test-agent:
	@$(AGENT_ENV) ./scripts/run-tests.sh --suite dev --agent

test-full:
	@./scripts/run-tests.sh --suite full

test-full-agent:
	@$(AGENT_ENV) ./scripts/run-tests.sh --suite full --agent

test-smoke:
	@./scripts/run-tests.sh --suite smoke

test-critical-coverage:
	@./scripts/run-critical-coverage.sh

test-perf:
	@./scripts/run-tests.sh --suite perf

test-sensitive:
	@./scripts/run-tests.sh --suite sensitive

test-appkit:
	@./scripts/run-tests.sh --suite appkit

test-parity:
	@./scripts/run-tests-xcode.sh

test-parity-agent:
	@$(AGENT_ENV) ./scripts/run-tests-xcode.sh --agent

test-verbose:
	@echo -e "$(BLUE)Running tests (verbose)...$(NC)"
	@./scripts/run-tests.sh --verbose

test-strict:
	@echo -e "$(BLUE)Running tests (Strict Concurrency)...$(NC)"
	@./scripts/run-tests.sh --strict

test-ci-strict:
	@./scripts/run-tests-xcode.sh --strict-xcode

scope-check:
	@./scripts/scope-check.sh $(ARGS)

scope-check-agent:
	@$(AGENT_ENV) ./scripts/scope-check.sh --agent $(ARGS)

validate:
	@$(AGENT_ENV) ./scripts/validate-agent.sh --lane auto $(ARGS)

validate-lane:
	@set -eu; \
		derived_parent="$(PROJECT_DIR)/.xcode-build-tests"; \
		scratch_parent="$(PROJECT_DIR)/.tmp"; \
		derived_parent_existed=0; \
		scratch_parent_existed=0; \
		if [ -e "$$derived_parent" ] || [ -L "$$derived_parent" ]; then derived_parent_existed=1; fi; \
		if [ -e "$$scratch_parent" ] || [ -L "$$scratch_parent" ]; then scratch_parent_existed=1; fi; \
		mkdir -p "$$derived_parent" "$$scratch_parent"; \
		derived_data="$$(mktemp -d "$$derived_parent/validate-lane.XXXXXX")"; \
		scratch_path="$$(mktemp -d "$$scratch_parent/validate-lane.XXXXXX")"; \
		cleanup() { \
			rm -rf "$$derived_data" "$$scratch_path"; \
			if [ "$$derived_parent_existed" -eq 0 ]; then rmdir "$$derived_parent" 2>/dev/null || true; fi; \
			if [ "$$scratch_parent_existed" -eq 0 ]; then rmdir "$$scratch_parent" 2>/dev/null || true; fi; \
		}; \
		trap cleanup EXIT; \
		$(VALIDATE_LANE) --repo "$(PROJECT_DIR)" --base "$(VALIDATE_BASE)" --artifacts "$$derived_data/Build" --artifacts "$$scratch_path" -- $(MAKE) validate-lane-command VALIDATE_DERIVED_DATA_PATH="$$derived_data" MA_VALIDATE_SCRATCH_PATH="$$scratch_path"

validate-lane-command:
	@set -eu; \
		derived_data="$(VALIDATE_DERIVED_DATA_PATH)"; \
		scratch_path="$(MA_VALIDATE_SCRATCH_PATH)"; \
		[ -n "$$derived_data" ] || { echo "VALIDATE_DERIVED_DATA_PATH is required" >&2; exit 2; }; \
		[ -n "$$scratch_path" ] || { echo "MA_VALIDATE_SCRATCH_PATH is required" >&2; exit 2; }; \
		cleanup() { rm -rf "$$derived_data" "$$scratch_path"; }; \
		trap cleanup EXIT; \
		VALIDATE_DERIVED_DATA_PATH="$$derived_data" MA_SWIFTPM_SCRATCH_PATH="$$scratch_path" $(MAKE) validate ARGS="$(ARGS) --base $(VALIDATE_BASE)"

validate-agent:
	@$(AGENT_ENV) ./scripts/validate-agent.sh $(ARGS)

workflow-test:
	@./scripts/tests/workflow-test.sh

benchmark-summary:
	@./scripts/run-summary-benchmark.sh --report-only

benchmark-summary-agent:
	@$(AGENT_ENV) ./scripts/run-summary-benchmark.sh --report-only --agent

# Code Quality
lint:
	@echo -e "$(BLUE)Running SwiftLint...$(NC)"
	@if [ "$(FIX)" = "1" ] || [ "$(FIX)" = "true" ] || [ "$(FIX)" = "yes" ]; then \
		echo -e "$(YELLOW)Autofix enabled (SwiftFormat + SwiftLint --fix)$(NC)"; \
		./scripts/lint-fix.sh && ./scripts/lint.sh $(if $(FILES),--files "$(FILES)"); \
	else \
		./scripts/lint.sh $(if $(FILES),--files "$(FILES)"); \
	fi

lint-agent:
	@$(AGENT_ENV) ./scripts/lint.sh --agent $(if $(FILES),--files "$(FILES)")

lint-report:
	@STRICT_LINT=0 ./scripts/lint.sh $(if $(FILES),--files "$(FILES)")

lint-strict:
	@$(MAKE) STRICT_LINT=1 lint

lint-strict-agent:
	@$(MAKE) STRICT_LINT=1 lint-agent

lint-fix:
	@echo -e "$(BLUE)Auto-fixing lint issues...$(NC)"
	@./scripts/lint-fix.sh

arch-check:
	@echo -e "$(BLUE)Running architecture checks...$(NC)"
	@./scripts/architecture-check.sh

preview-check:
	@echo -e "$(BLUE)Checking SwiftUI preview coverage...$(NC)"
	@./scripts/preview-check.sh --settings

localization-check:
	@echo -e "$(BLUE)Checking localization key integrity...$(NC)"
	@python3 ./scripts/check-localization.py

guidance-check:
	@echo -e "$(BLUE)Validating AGENTS/skills/docs guidance...$(NC)"
	@python3 ./scripts/validate-agent-guidance.py
	@./scripts/config/generate_app_identity.swift --check
	@$(MAKE) localization-check

preflight:
	@echo -e "$(BLUE)Running preflight checks...$(NC)"
	@./scripts/preflight.sh

preflight-fast:
	@echo -e "$(BLUE)Running fast preflight checks...$(NC)"
	@./scripts/preflight.sh --fast

preflight-agent:
	@$(AGENT_ENV) ./scripts/preflight.sh --agent

preflight-agent-fast:
	@$(AGENT_ENV) ./scripts/preflight.sh --agent --fast

format:
	@echo -e "$(BLUE)Running SwiftFormat...$(NC)"
	@if ! command -v swiftformat &> /dev/null; then \
		echo "❌ SwiftFormat not installed. Install with: brew install swiftformat"; \
		exit 1; \
	fi
	@swiftformat --base-config .swiftformat App Packages
	@echo -e "$(GREEN)✓ Code formatted$(NC)"

health:
	@echo -e "$(BLUE)Running code health check...$(NC)"
	@./scripts/code-health-check.sh

# Run Commands
run: build
	@echo -e "$(YELLOW)Launching $(APP_PRODUCT_NAME) (Debug)...$(NC)"
	@open "$(DERIVED_DATA)/Build/Products/Debug/$(APP_PRODUCT_NAME).app"

run-release: build-release
	@echo -e "$(YELLOW)Launching $(APP_PRODUCT_NAME) (Release)...$(NC)"
	@open "$(DERIVED_DATA)/Build/Products/Release/$(APP_PRODUCT_NAME).app"

build-and-run:
	@./scripts/build-and-run.sh $(ARGS)

runtime-smoke:
	@./scripts/runtime-smoke.sh

# Distribution
new-release:
	@latest=$$(git describe --tags --abbrev=0 2>/dev/null || echo "None"); \
	echo -e "$(BLUE)Last release was: $$latest$(NC)"; \
	read -p "Enter new release version (e.g., v1.0.1): " version; \
	if [ -z "$$version" ]; then \
		echo -e "$(RED)Error: Version cannot be empty.$(NC)"; \
		exit 1; \
	fi; \
	semantic_version="$${version#v}"; \
	if ! printf '%s\n' "$$semantic_version" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$$'; then \
		echo -e "$(RED)Error: Version must use semantic versioning, for example v1.0.1.$(NC)"; \
		exit 1; \
	fi; \
	app_version="$$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' App/Info.plist)"; \
	if [ "$$app_version" != "$$semantic_version" ]; then \
		echo -e "$(RED)Error: App version is $$app_version, but release tag is $$version. Run scripts/bump-version.sh first.$(NC)"; \
		exit 1; \
	fi; \
	release_signing_mode="$${MA_RELEASE_SIGNING_MODE:-identity}"; \
	if [ "$$release_signing_mode" != "identity" ] && [ "$$release_signing_mode" != "self-signed" ]; then \
		echo -e "$(RED)Error: AppUpdater releases must use MA_RELEASE_SIGNING_MODE=identity.$(NC)"; \
		exit 1; \
	fi; \
	echo ""; \
	echo -e "$(YELLOW)Building signed release $$version...$(NC)"; \
	MA_RELEASE_SIGNING_MODE="$$release_signing_mode" ./scripts/build-release.sh --no-interactive; \
	archive="$(DIST_DIR)/$(APP_PRODUCT_NAME)-$$semantic_version.zip"; \
	if [ ! -f "$$archive" ]; then \
		echo -e "$(RED)Error: Update archive not found at $$archive.$(NC)"; \
		exit 1; \
	fi; \
	echo -e "$(YELLOW)Creating release $$version with auto-generated notes...$(NC)"; \
	gh release create "$$version" "$$archive" --generate-notes; \
	echo -e "$(GREEN)✓ Successfully created release $$version!$(NC)"

dmg:
	@echo -e "$(BLUE)Creating DMG installer...$(NC)"
	@./scripts/create-dmg.sh --auto-signing

setup-self-signed-cert:
	@./scripts/setup-self-signed-cert.sh

# Maintenance
agent-artifacts-report:
	@python3 ./scripts/agent-artifacts.py

agent-artifacts-dry-run:
	@python3 ./scripts/agent-artifacts.py --clean --dry-run --older-than-days "$(ARTIFACT_RETENTION_DAYS)"

agent-artifacts-clean:
	@if [ "$(ARTIFACT_CLEAN_CONFIRM)" != "1" ]; then echo "Refusing cleanup. Re-run with ARTIFACT_CLEAN_CONFIRM=1 after reviewing make agent-artifacts-dry-run." >&2; exit 2; fi
	@python3 ./scripts/agent-artifacts.py --clean --confirm --older-than-days "$(ARTIFACT_RETENTION_DAYS)"

clean:
	@echo -e "$(YELLOW)Cleaning build artifacts...$(NC)"
	@rm -rf "$(DERIVED_DATA)"
	@rm -rf "$(DIST_DIR)"
	@echo -e "$(GREEN)✓ Clean completed$(NC)"

setup:
	@./scripts/setup-dev-environment.sh

# Profiling Commands
profile: build
	@echo -e "$(BLUE)Running performance profiling (all)...$(NC)"
	@./scripts/profile-performance.sh --all

profile-report: build
	@echo -e "$(BLUE)Running performance profiling with report extraction...$(NC)"
	@./scripts/profile-performance.sh --all --report

profile-cpu: build
	@echo -e "$(BLUE)Running CPU profiling...$(NC)"
	@./scripts/profile-performance.sh --cpu

profile-memory: build
	@echo -e "$(BLUE)Running memory profiling...$(NC)"
	@./scripts/profile-performance.sh --memory

profile-animation: build
	@echo -e "$(BLUE)Running animation profiling...$(NC)"
	@./scripts/profile-performance.sh --animation

profile-animation-report: build
	@echo -e "$(BLUE)Running animation profiling with report extraction...$(NC)"
	@./scripts/profile-performance.sh --animation --report


# CI/CD Commands
ci-build: arch-check lint test build-release
	@echo -e "$(GREEN)✓ CI build completed successfully$(NC)"

deliverable-gate:
	@$(MAKE) lint
	@$(MAKE) build-test
# Documentation
docs:
	@echo -e "$(BLUE)Building DocC documentation...$(NC)"
	@cd Packages/MeetingAssistantCore && \
		swift package --allow-writing-to-directory "$(PROJECT_DIR)/.agents/docs/api" \
		generate-documentation \
		--target MeetingAssistantCore \
		--transform-for-static-hosting \
		--output-path "$(PROJECT_DIR)/.agents/docs/api"
	@echo -e "$(GREEN)✓ Documentation built at .agents/docs/api$(NC)"

docs-preview:
	@echo -e "$(BLUE)Previewing documentation...$(NC)"
	@cd Packages/MeetingAssistantCore && swift package --disable-sandbox preview-documentation --target MeetingAssistantCore

docs-clean:
	@echo -e "$(YELLOW)Cleaning documentation...$(NC)"
	@rm -rf "$(PROJECT_DIR)/.agents/docs/api"
	@echo -e "$(GREEN)✓ Documentation cleaned$(NC)"
