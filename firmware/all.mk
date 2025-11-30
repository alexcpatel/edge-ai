# Firmware infrastructure targets (EC2, Yocto builds, controller flashing)

EC2_DIR := firmware/infra/ec2
CONTROLLER_DIR := firmware/infra/controller
YOCTO_DIR := firmware/yocto

# EC2 management
firmware-ec2-setup: ## Run EC2 setup
	@$(EC2_DIR)/scripts/ec2.sh setup

firmware-ec2-start: ## Start EC2 instance
	@$(EC2_DIR)/scripts/ec2.sh start

firmware-ec2-stop: ## Stop EC2 instance
	@$(EC2_DIR)/scripts/ec2.sh stop

firmware-ec2-status: ## Show EC2 status
	@$(EC2_DIR)/scripts/ec2.sh status

firmware-ec2-ssh: ## SSH into EC2
	@$(EC2_DIR)/scripts/ec2.sh ssh

firmware-ec2-health: ## Run EC2 health diagnostics
	@$(EC2_DIR)/scripts/ec2.sh health

# Yocto builds on EC2
firmware-build: firmware-ec2-start ## Build Yocto image on EC2
	@$(EC2_DIR)/scripts/build.sh start
	@$(EC2_DIR)/scripts/build.sh watch

firmware-build-status: ## Check build status
	@$(EC2_DIR)/scripts/build.sh status

firmware-build-watch: ## Tail build log
	@$(EC2_DIR)/scripts/build.sh watch

firmware-build-terminate: ## Terminate build session
	@$(EC2_DIR)/scripts/build.sh terminate

firmware-build-set-auto-stop: ## Enable auto-stop
	@$(EC2_DIR)/scripts/build.sh set-auto-stop

firmware-build-unset-auto-stop: ## Disable auto-stop
	@$(EC2_DIR)/scripts/build.sh unset-auto-stop

firmware-build-check-auto-stop: ## Check auto-stop status
	@$(EC2_DIR)/scripts/build.sh check-auto-stop

# Clean operations
firmware-clean: ## Clean current image
	@$(EC2_DIR)/scripts/clean.sh --image

firmware-clean-all: ## Clean all build artifacts
	@$(EC2_DIR)/scripts/clean.sh --all

firmware-clean-package: ## Clean package (PACKAGE=name)
	@if [ -z "$(PACKAGE)" ]; then \
		echo "Error: PACKAGE is required. Usage: make firmware-clean-package PACKAGE=swig-native"; \
		exit 1; \
	fi
	@$(EC2_DIR)/scripts/clean.sh --package $(PACKAGE)

# Controller management
firmware-controller-list: ## List controllers
	@$(CONTROLLER_DIR)/scripts/controller.sh list

firmware-controller-status: ## Show controller status
	@$(CONTROLLER_DIR)/scripts/controller.sh status $(C)

firmware-controller-setup: ## Set up controller
	@$(CONTROLLER_DIR)/scripts/controller.sh ssh-keys $(C)
	@$(CONTROLLER_DIR)/scripts/controller.sh setup $(C)

firmware-controller-deploy: ## Deploy scripts to controller
	@$(CONTROLLER_DIR)/scripts/controller.sh deploy $(C)

# Controller Jetson flashing
firmware-controller-push-tegraflash: ## Push tegraflash to controller
	@$(CONTROLLER_DIR)/scripts/push-tegraflash.sh

firmware-controller-flash-usb: firmware-controller-deploy ## Flash Jetson via USB (FULL=--full for full image)
	@$(CONTROLLER_DIR)/scripts/flash-usb.sh start $(FULL)

firmware-controller-flash-sdcard: firmware-controller-deploy ## Flash SD card (DEVICE=/dev/sdX)
	@$(CONTROLLER_DIR)/scripts/flash-sdcard.sh start "$(DEVICE)"
	@$(CONTROLLER_DIR)/scripts/flash-sdcard.sh watch

firmware-controller-flash-sdcard-status: ## Check SD card flash status
	@$(CONTROLLER_DIR)/scripts/flash-sdcard.sh status

firmware-controller-flash-sdcard-watch: ## Tail SD card flash log
	@$(CONTROLLER_DIR)/scripts/flash-sdcard.sh watch

firmware-controller-flash-sdcard-terminate: ## Terminate SD card flash session
	@$(CONTROLLER_DIR)/scripts/flash-sdcard.sh terminate
