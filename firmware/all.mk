# Firmware infrastructure targets (EC2, Yocto builds, controller flashing)

EC2_DIR := firmware/infra/ec2
CONTROLLER_DIR := firmware/infra/controller
APPS_SCRIPTS_DIR := firmware/apps/scripts

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
firmware-build: firmware-ec2-start ## Build image (uploads to S3, stops EC2 automatically)
	@$(EC2_DIR)/scripts/build.sh start
	@$(EC2_DIR)/scripts/build.sh watch

firmware-build-status: ## Check build status
	@$(EC2_DIR)/scripts/build.sh status

firmware-build-watch: ## Tail build log
	@$(EC2_DIR)/scripts/build.sh watch

firmware-build-terminate: ## Terminate build session
	@$(EC2_DIR)/scripts/build.sh terminate

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

firmware-controller-usb-device: ## Check for NVIDIA USB device on controller
	@$(CONTROLLER_DIR)/scripts/controller.sh usb-device $(C)

firmware-controller-setup: ## Set up controller
	@$(CONTROLLER_DIR)/scripts/controller.sh ssh-keys $(C)
	@$(CONTROLLER_DIR)/scripts/controller.sh setup $(C)

firmware-controller-deploy: ## Deploy scripts to controller
	@$(CONTROLLER_DIR)/scripts/controller.sh deploy $(C)

# Forced recovery mode (uses raspberrypi)
firmware-recovery-enable: ## Hold FC_REC low (power cycle Jetson to enter recovery)
	@$(CONTROLLER_DIR)/scripts/controller.sh deploy raspberrypi
	@$(CONTROLLER_DIR)/scripts/forced-recovery-mode.sh enable

firmware-recovery-disable: ## Release FC_REC
	@$(CONTROLLER_DIR)/scripts/forced-recovery-mode.sh disable

firmware-recovery-status: ## Check GPIO state and NVIDIA USB device
	@$(CONTROLLER_DIR)/scripts/forced-recovery-mode.sh status

# Flashing (downloads from S3, enables recovery, flashes via steamdeck)
firmware-flash: ## Pull from S3 and flash Jetson (MODE=bootloader|rootfs)
	@$(CONTROLLER_DIR)/scripts/controller.sh deploy steamdeck
	@$(CONTROLLER_DIR)/scripts/controller.sh deploy raspberrypi
	@$(CONTROLLER_DIR)/scripts/flash.sh pull
	@$(CONTROLLER_DIR)/scripts/flash.sh flash $(MODE)
	@$(CONTROLLER_DIR)/scripts/flash.sh watch

firmware-flash-status: ## Check flash status
	@$(CONTROLLER_DIR)/scripts/flash.sh status

firmware-flash-watch: ## Tail flash log
	@$(CONTROLLER_DIR)/scripts/flash.sh watch

firmware-flash-terminate: ## Terminate flash session
	@$(CONTROLLER_DIR)/scripts/flash.sh terminate

# App management on device
firmware-app-deploy: ## Deploy app container to device (APP=, DEVICE_HOST=, DEVICE_USER=)
	@$(APPS_SCRIPTS_DIR)/app-deploy.sh "$(APP)" "$(DEVICE_HOST)" "$(DEVICE_USER)"

firmware-app-stop: ## Stop and disable app on device (APP=, DEVICE_HOST=, DEVICE_USER=)
	@$(APPS_SCRIPTS_DIR)/app-stop.sh "$(APP)" "$(DEVICE_HOST)" "$(DEVICE_USER)"

firmware-app-logs: ## Tail app logs on device (APP=, DEVICE_HOST=, DEVICE_USER=)
	@$(APPS_SCRIPTS_DIR)/app-logs.sh "$(APP)" "$(DEVICE_HOST)" "$(DEVICE_USER)"

firmware-device-check: ## Check that Jetson is reachable (DEVICE_HOST=, DEVICE_USER=)
	@$(APPS_SCRIPTS_DIR)/device-check.sh "$(DEVICE_HOST)" "$(DEVICE_USER)"
