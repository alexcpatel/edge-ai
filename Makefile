.PHONY: build build-image dev sdk help
.DEFAULT_GOAL := help

INFRA_DIR := build/infrastructure
REMOTE_DIR := build/remote
LOCAL_DIR := build/local

help: ## Show this help message
	@echo "Available targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-15s %s\n", $$1, $$2}'

# Remote EC2 builds (heavy compute)
build-image: ## Build full Yocto image on EC2
	@$(INFRA_DIR)/scripts/instance.sh start
	@$(INFRA_DIR)/scripts/sync-repo.sh
	@$(REMOTE_DIR)/scripts/setup-yocto.sh
	@$(REMOTE_DIR)/scripts/build-yocto.sh

build-image-stop: build-image ## Build image and stop EC2 instance
	@$(INFRA_DIR)/scripts/instance.sh stop

# SDK management
sdk: ## Download Yocto SDK from EC2 (requires instance running)
	@$(REMOTE_DIR)/scripts/download-sdk.sh

# EC2 management
status: ## Show EC2 instance status
	@$(INFRA_DIR)/scripts/instance.sh

stop: ## Stop EC2 instance
	@$(INFRA_DIR)/scripts/instance.sh stop

clean: ## Clean Yocto build artifacts on EC2
	@$(REMOTE_DIR)/scripts/clean-build.sh

clean-all: ## Clean all build artifacts on EC2
	@$(REMOTE_DIR)/scripts/clean-all.sh
