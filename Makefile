.PHONY: build build-image dev sdk help
.DEFAULT_GOAL := help

REMOTE_DIR := build/remote
LOCAL_DIR := build/local

help: ## Show this help message
	@echo "Available targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-15s %s\n", $$1, $$2}'

# Remote EC2 builds (heavy compute)
build-image: instance-start ## Build full Yocto image on EC2
	@$(REMOTE_DIR)/scripts/upload-source.sh
	@$(REMOTE_DIR)/scripts/setup-yocto.sh
	@$(REMOTE_DIR)/scripts/build-image.sh start
	@$(REMOTE_DIR)/scripts/build-image.sh watch

build-status: ## Check if build session is running (does not auto-start instance)
	@$(REMOTE_DIR)/scripts/build-image.sh status

build-watch: ## Tail build log (allows scrolling in local terminal, requires instance running)
	@$(REMOTE_DIR)/scripts/build-image.sh watch

build-terminate: ## Terminate running build session (requires instance running)
	@$(REMOTE_DIR)/scripts/build-image.sh terminate

build-set-auto-stop: ## Enable auto-stop (instance stops when build ends, requires instance running)
	@$(REMOTE_DIR)/scripts/build-image.sh set-auto-stop

build-unset-auto-stop: ## Disable auto-stop (requires instance running)
	@$(REMOTE_DIR)/scripts/build-image.sh unset-auto-stop

build-check-auto-stop: ## Check if auto-stop is enabled (requires instance running)
	@$(REMOTE_DIR)/scripts/build-image.sh check-auto-stop

# Clean operations
clean: ## Clean current image (requires instance running)
	@$(REMOTE_DIR)/scripts/clean.sh --image

clean-all: ## Clean all build artifacts including tmp and cache (requires instance running)
	@$(REMOTE_DIR)/scripts/clean.sh --all

clean-package: ## Clean a specific package (usage: make clean-package PACKAGE=swig-native, requires instance running)
	@if [ -z "$(PACKAGE)" ]; then \
		echo "Error: PACKAGE is required. Usage: make clean-package PACKAGE=swig-native"; \
		exit 1; \
	fi
	@$(REMOTE_DIR)/scripts/clean.sh --package $(PACKAGE)

# SDK management
sdk: ## Download Yocto SDK from EC2 (requires instance running)
	@$(REMOTE_DIR)/scripts/download-sdk.sh

# Artifact management
list-artifacts: ## List available build artifacts on EC2 (requires instance running)
	@$(REMOTE_DIR)/scripts/list-artifacts.sh

download-artifacts: ## Download build artifacts from EC2 (usage: make download-artifacts DEST=/path/to/dest [FILE=artifact.wic], requires instance running)
	@if [ -z "$(DEST)" ]; then \
		echo "Error: DEST is required. Usage: make download-artifacts DEST=/path/to/destination [FILE=artifact.wic]"; \
		exit 1; \
	fi
	@if [ -n "$(FILE)" ]; then \
		$(REMOTE_DIR)/scripts/download-artifacts.sh "$(DEST)" "$(FILE)"; \
	else \
		$(REMOTE_DIR)/scripts/download-artifacts.sh "$(DEST)"; \
	fi

# EC2 management
instance-start: ## Start/ensure EC2 instance is running
	@$(REMOTE_DIR)/scripts/instance.sh start

instance-stop: ## Stop EC2 instance
	@$(REMOTE_DIR)/scripts/instance.sh stop

instance-status: ## Show EC2 instance status
	@$(REMOTE_DIR)/scripts/instance.sh status

instance-ssh: ## SSH into EC2 instance (requires instance running)
	@$(REMOTE_DIR)/scripts/instance.sh ssh

instance-health: ## Run comprehensive instance health diagnostics
	@$(REMOTE_DIR)/scripts/instance.sh health
