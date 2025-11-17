# Local development Makefile
# Use Yocto SDK for building applications locally

SDK_DIR ?= $(shell find ../sdk -name "environment-setup-*" -type f 2>/dev/null | head -1 | xargs dirname)

ifndef SDK_DIR
$(error SDK not found. Run 'make sdk' from repo root to download SDK from EC2)
endif

.PHONY: setup-sdk build-apps

setup-sdk: ## Setup SDK environment (source this in your shell)
	@echo "export SDK_DIR=$(SDK_DIR)"
	@echo "source $(SDK_DIR)/environment-setup-aarch64-poky-linux"

build-apps: ## Build all applications using SDK
	@echo "Building applications with Yocto SDK..."
	@for app in ../../apps/*/; do \
		if [ -f "$$app/Makefile" ] || [ -f "$$app/build.sh" ]; then \
			echo "Building $$app"; \
			(cd "$$app" && source $(SDK_DIR)/environment-setup-aarch64-poky-linux && \
				[ -f Makefile ] && make || [ -f build.sh ] && ./build.sh || true); \
		fi; \
	done

