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

build-image-and-stop: build-image instance-stop ## Build image and stop EC2 instance

build-status: instance-start ## Check if build session is running
	@$(REMOTE_DIR)/scripts/build-image.sh status

build-attach: instance-start ## Attach to running build session to view logs
	@$(REMOTE_DIR)/scripts/build-image.sh attach

build-watch: instance-start ## Tail build log (allows scrolling in local terminal)
	@$(REMOTE_DIR)/scripts/build-image.sh watch

# Clean operations
clean: instance-start ## Clean Yocto build artifacts
	@$(REMOTE_DIR)/scripts/clean.sh

clean-all: instance-start ## Clean all build artifacts including tmp
	@$(REMOTE_DIR)/scripts/clean.sh all

clean-package: instance-start ## Clean a specific package (usage: make clean-package PACKAGE=swig-native)
	@$(REMOTE_DIR)/scripts/clean.sh $(PACKAGE)

# SDK management
sdk: instance-start ## Download Yocto SDK from EC2
	@$(REMOTE_DIR)/scripts/download-sdk.sh

# EC2 management
instance-start: ## Start/ensure EC2 instance is running
	@$(REMOTE_DIR)/scripts/instance.sh start

instance-stop: ## Stop EC2 instance
	@$(REMOTE_DIR)/scripts/instance.sh stop

instance-status: ## Show EC2 instance status
	@$(REMOTE_DIR)/scripts/instance.sh status

instance-ssh: instance-start ## SSH into EC2 instance
	@$(REMOTE_DIR)/scripts/instance.sh ssh

instance-health: ## Run comprehensive instance health diagnostics
	@$(REMOTE_DIR)/scripts/instance.sh health
