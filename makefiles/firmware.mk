# Firmware infrastructure targets (EC2, Yocto builds, controller flashing)

EC2_DIR := firmware/infra/ec2
CONTROLLER_DIR := firmware/infra/controller
YOCTO_DIR := firmware/yocto

# EC2 management
firmware-ec2-setup: ## Run EC2 setup (install dependencies, AWS CLI, etc.)
	@$(EC2_DIR)/scripts/ec2.sh setup

firmware-ec2-start: ## Start/ensure EC2 instance is running
	@$(EC2_DIR)/scripts/ec2.sh start

firmware-ec2-stop: ## Stop EC2 instance
	@$(EC2_DIR)/scripts/ec2.sh stop

firmware-ec2-status: ## Show EC2 instance status
	@$(EC2_DIR)/scripts/ec2.sh status

firmware-ec2-ssh: ## SSH into EC2 instance
	@$(EC2_DIR)/scripts/ec2.sh ssh

firmware-ec2-health: ## Run comprehensive EC2 health diagnostics
	@$(EC2_DIR)/scripts/ec2.sh health

# Yocto builds on EC2
firmware-build: firmware-ec2-start ## Build full Yocto image on EC2 (uploads source, starts build, watches)
	@$(EC2_DIR)/scripts/build.sh start
	@$(EC2_DIR)/scripts/build.sh watch

firmware-build-status: ## Check if build session is running
	@$(EC2_DIR)/scripts/build.sh status

firmware-build-watch: ## Tail build log (allows scrolling in local terminal)
	@$(EC2_DIR)/scripts/build.sh watch

firmware-build-terminate: ## Terminate running build session
	@$(EC2_DIR)/scripts/build.sh terminate

firmware-build-set-auto-stop: ## Enable auto-stop (EC2 stops when build ends)
	@$(EC2_DIR)/scripts/build.sh set-auto-stop

firmware-build-unset-auto-stop: ## Disable auto-stop
	@$(EC2_DIR)/scripts/build.sh unset-auto-stop

firmware-build-check-auto-stop: ## Check if auto-stop is enabled
	@$(EC2_DIR)/scripts/build.sh check-auto-stop

# Clean operations
firmware-clean: ## Clean current image
	@$(EC2_DIR)/scripts/clean.sh --image

firmware-clean-all: ## Clean all build artifacts including tmp and cache
	@$(EC2_DIR)/scripts/clean.sh --all

firmware-clean-package: ## Clean a specific package (usage: make firmware-clean-package PACKAGE=swig-native)
	@if [ -z "$(PACKAGE)" ]; then \
		echo "Error: PACKAGE is required. Usage: make firmware-clean-package PACKAGE=swig-native"; \
		exit 1; \
	fi
	@$(EC2_DIR)/scripts/clean.sh --package $(PACKAGE)

# Controller management (C=controller required)
firmware-controller-list: ## List configured controllers
	@$(CONTROLLER_DIR)/scripts/controller.sh list

firmware-controller-status: ## Show controller status (C=steamdeck)
	@$(CONTROLLER_DIR)/scripts/controller.sh status $(C)

firmware-controller-setup: ## Set up a controller (C=steamdeck)
	@$(CONTROLLER_DIR)/scripts/controller.sh ssh-keys $(C)
	@$(CONTROLLER_DIR)/scripts/controller.sh setup $(C)

firmware-controller-deploy: ## Deploy scripts to controller (C=steamdeck)
	@$(CONTROLLER_DIR)/scripts/controller.sh deploy $(C)

# Controller Jetson flashing
firmware-push-tegraflash: ## Push tegraflash archive from EC2 to controller
	@$(CONTROLLER_DIR)/scripts/push-tegraflash.sh

firmware-flash-usb: ## Flash Jetson via USB from controller (use FULL=--full for full image flash)
	@$(CONTROLLER_DIR)/scripts/flash-usb.sh $(FULL)

firmware-flash-sdcard: ## Flash SD card from controller
	@$(CONTROLLER_DIR)/scripts/flash-sdcard.sh "$(DEVICE)"
