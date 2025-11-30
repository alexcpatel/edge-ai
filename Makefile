.PHONY: build help
.DEFAULT_GOAL := help

EC2_DIR := firmware/infra/ec2
CONTROLLER_DIR := firmware/infra/controller
YOCTO_DIR := firmware/yocto

help: ## Show this help message
	@echo "Available targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-15s %s\n", $$1, $$2}'

# EC2 management
ec2-setup: ## Run EC2 setup (install dependencies, AWS CLI, etc.)
	@$(EC2_DIR)/scripts/ec2.sh setup

ec2-start: ## Start/ensure EC2 instance is running
	@$(EC2_DIR)/scripts/ec2.sh start

ec2-stop: ## Stop EC2 instance
	@$(EC2_DIR)/scripts/ec2.sh stop

ec2-status: ## Show EC2 instance status
	@$(EC2_DIR)/scripts/ec2.sh status

ec2-ssh: ## SSH into EC2 instance
	@$(EC2_DIR)/scripts/ec2.sh ssh

ec2-health: ## Run comprehensive EC2 health diagnostics
	@$(EC2_DIR)/scripts/ec2.sh health

# Yocto builds on EC2
build: ec2-start ## Build full Yocto image on EC2 (uploads source, starts build, watches)
	@$(EC2_DIR)/scripts/build.sh start
	@$(EC2_DIR)/scripts/build.sh watch

build-status: ## Check if build session is running
	@$(EC2_DIR)/scripts/build.sh status

build-watch: ## Tail build log (allows scrolling in local terminal)
	@$(EC2_DIR)/scripts/build.sh watch

build-terminate: ## Terminate running build session
	@$(EC2_DIR)/scripts/build.sh terminate

build-set-auto-stop: ## Enable auto-stop (EC2 stops when build ends)
	@$(EC2_DIR)/scripts/build.sh set-auto-stop

build-unset-auto-stop: ## Disable auto-stop
	@$(EC2_DIR)/scripts/build.sh unset-auto-stop

build-check-auto-stop: ## Check if auto-stop is enabled
	@$(EC2_DIR)/scripts/build.sh check-auto-stop

# Clean operations
clean: ## Clean current image
	@$(EC2_DIR)/scripts/clean.sh --image

clean-all: ## Clean all build artifacts including tmp and cache
	@$(EC2_DIR)/scripts/clean.sh --all

clean-package: ## Clean a specific package (usage: make clean-package PACKAGE=swig-native)
	@if [ -z "$(PACKAGE)" ]; then \
		echo "Error: PACKAGE is required. Usage: make clean-package PACKAGE=swig-native"; \
		exit 1; \
	fi
	@$(EC2_DIR)/scripts/clean.sh --package $(PACKAGE)

# Controller management (C=controller required)
controller-list: ## List configured controllers
	@$(CONTROLLER_DIR)/scripts/controller.sh list

controller-status: ## Show controller status (C=steamdeck)
	@$(CONTROLLER_DIR)/scripts/controller.sh status $(C)

controller-setup: ## Set up a controller (C=steamdeck)
	@$(CONTROLLER_DIR)/scripts/controller.sh ssh-keys $(C)
	@$(CONTROLLER_DIR)/scripts/controller.sh setup $(C)

controller-deploy: ## Deploy scripts to controller (C=steamdeck)
	@$(CONTROLLER_DIR)/scripts/controller.sh deploy $(C)

# Controller Jetson flashing
controller-push-tegraflash: ## Push tegraflash archive from EC2 to controller
	@$(CONTROLLER_DIR)/scripts/push-tegraflash.sh

controller-flash-usb: ## Flash Jetson via USB from controller (use FULL=--full for full image flash)
	@$(CONTROLLER_DIR)/scripts/flash-usb.sh $(FULL)

controller-flash-sdcard: ## Flash SD card from controller
	@$(CONTROLLER_DIR)/scripts/flash-sdcard.sh "$(DEVICE)"
