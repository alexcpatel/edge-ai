.PHONY: build build-image dev sdk help
.DEFAULT_GOAL := help

REMOTE_DIR := build/remote
LOCAL_DIR := build/local
CONTROLLER_DIR := build/controller

help: ## Show this help message
	@echo "Available targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-15s %s\n", $$1, $$2}'

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
download-sdk: ## Download Yocto SDK from EC2 (requires instance running)
	@$(REMOTE_DIR)/scripts/download-sdk.sh

# Local Jetson flashing
download-tegraflash: ## Download tegraflash archive from EC2 (required for flashing)
	@$(REMOTE_DIR)/scripts/download-tegraflash.sh

flash-sdcard: ## Flash SD card (interactive device selection, or specify DEVICE=/dev/diskX)
	@$(LOCAL_DIR)/scripts/flash-sdcard.sh "$(DEVICE)"

# Controller (Raspberry Pi) management
controller-setup: ## Set up controller remotely (installs Docker, creates directories - one-time setup)
	@$(CONTROLLER_DIR)/scripts/setup-ssh-keys.sh
	@$(CONTROLLER_DIR)/scripts/setup-controller-remote.sh

controller-update: ## Update everything: Docker image + scripts (use this after making changes)
	@$(CONTROLLER_DIR)/scripts/update-controller.sh

# Controller Jetson flashing
controller-push-tegraflash: ## Push tegraflash archive from EC2 to controller
	@$(CONTROLLER_DIR)/scripts/push-tegraflash.sh

controller-flash-usb: ## Flash Jetson via USB from controller
	@$(CONTROLLER_DIR)/scripts/flash-usb.sh
